#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, token,
    vec, Address, Env, IntoVal, String, Symbol, Val,
};

/// Medialane marketplace — immutable venue for NFT collections on Stellar.
///
/// Safety model — every check is on-chain and falls in exactly one bucket:
///   1. Statically determinable from the order → validated at registration,
///      fail-fast. The offerer authorizes registration.
///   2. Mutable on-chain state (ownership, approvals, allowances, live
///      royalties) → not pre-simulated; enforced by atomic revert at fill.
///      Settlement pays before delivering the NFT.
///
/// No admin functions, no fees, no upgrade path.
#[contract]
pub struct MedialaneMarketplace;

#[contracttype]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Side {
    Listing,
    Bid,
}

#[contracttype]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum OrderStatus {
    Created,
    Filled,
    Cancelled,
}

/// Stored order. An order's identity is its storage key (offerer, salt) in
/// this contract instance — a registration cannot be replayed against another
/// deployment. The payment token is any SEP-41 token, including native XLM
/// via the Stellar Asset Contract.
#[contracttype]
#[derive(Clone, Debug)]
pub struct Order {
    pub offerer: Address,
    pub side: Side,
    pub collection: Address,
    pub token_id: u32,
    pub payment_token: Address,
    pub amount: i128,
    pub royalty_max_bps: u32,
    pub start_time: u64,
    /// 0 = no expiry.
    pub end_time: u64,
    pub counter: u64,
    pub status: OrderStatus,
}

#[contracttype]
pub enum DataKey {
    Order(Address, u64),
    Counter(Address),
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum VenueError {
    RoyaltyBpsTooHigh = 1,
    InvalidCounter = 2,
    InvalidTimeWindow = 3,
    OrderExpired = 4,
    OrderAlreadyExists = 5,
    InvalidAmount = 6,
    OrderNotFound = 7,
    OrderAlreadyFilled = 8,
    OrderCancelled = 9,
    SelfFill = 10,
    OrderNotYetValid = 11,
    RoyaltyExceedsSale = 12,
}

const EVT_CREATED: Symbol = symbol_short!("created");
const EVT_FILLED: Symbol = symbol_short!("filled");
const EVT_CANCELLED: Symbol = symbol_short!("cancelled");
const EVT_COUNTER: Symbol = symbol_short!("counter");

#[contractimpl]
impl MedialaneMarketplace {
    /// Register an order. The offerer authorizes; settlement approvals (NFT
    /// for listings, payment token for bids) are granted separately and
    /// enforced atomically at fill.
    #[allow(clippy::too_many_arguments)]
    pub fn register_order(
        e: Env,
        offerer: Address,
        salt: u64,
        side: Side,
        collection: Address,
        token_id: u32,
        payment_token: Address,
        amount: i128,
        royalty_max_bps: u32,
        start_time: u64,
        end_time: u64,
        counter: u64,
    ) {
        offerer.require_auth();
        if royalty_max_bps > 10_000 {
            panic_with_error!(&e, VenueError::RoyaltyBpsTooHigh);
        }
        if amount < 0 {
            panic_with_error!(&e, VenueError::InvalidAmount);
        }
        if counter != Self::get_counter(e.clone(), offerer.clone()) {
            panic_with_error!(&e, VenueError::InvalidCounter);
        }
        let now = e.ledger().timestamp();
        if end_time != 0 {
            if start_time >= end_time {
                panic_with_error!(&e, VenueError::InvalidTimeWindow);
            }
            if now >= end_time {
                panic_with_error!(&e, VenueError::OrderExpired);
            }
        }
        let key = DataKey::Order(offerer.clone(), salt);
        if e.storage().persistent().has(&key) {
            panic_with_error!(&e, VenueError::OrderAlreadyExists);
        }
        let order = Order {
            offerer: offerer.clone(),
            side,
            collection,
            token_id,
            payment_token,
            amount,
            royalty_max_bps,
            start_time,
            end_time,
            counter,
            status: OrderStatus::Created,
        };
        e.storage().persistent().set(&key, &order);
        e.events().publish((EVT_CREATED, offerer), salt);
    }

    /// Fulfil an open order. The caller IS the fulfiller. Listings: the
    /// fulfiller pays directly (their authorization covers the token
    /// transfer) and the NFT moves under the venue's approval granted by the
    /// offerer. Bids: payment is pulled through the offerer's token allowance
    /// to the venue, and the fulfiller (the NFT owner) delivers under their
    /// own authorization. Royalties are read via the collection's
    /// royalty_info interface (absent or failing => none), capped at the
    /// offerer-signed maximum. Payment settles before the NFT moves.
    pub fn fulfill_order(e: Env, fulfiller: Address, offerer: Address, salt: u64) {
        fulfiller.require_auth();
        let key = DataKey::Order(offerer.clone(), salt);
        let mut order: Order = e
            .storage()
            .persistent()
            .get(&key)
            .unwrap_or_else(|| panic_with_error!(&e, VenueError::OrderNotFound));

        match order.status {
            OrderStatus::Created => {}
            OrderStatus::Filled => panic_with_error!(&e, VenueError::OrderAlreadyFilled),
            OrderStatus::Cancelled => panic_with_error!(&e, VenueError::OrderCancelled),
        }
        if fulfiller == order.offerer {
            panic_with_error!(&e, VenueError::SelfFill);
        }
        if order.counter != Self::get_counter(e.clone(), order.offerer.clone()) {
            panic_with_error!(&e, VenueError::InvalidCounter);
        }
        let now = e.ledger().timestamp();
        if now < order.start_time {
            panic_with_error!(&e, VenueError::OrderNotYetValid);
        }
        if order.end_time != 0 && now >= order.end_time {
            panic_with_error!(&e, VenueError::OrderExpired);
        }

        order.status = OrderStatus::Filled;
        e.storage().persistent().set(&key, &order);

        let (royalty_receiver, royalty_amount) =
            Self::capped_royalty(&e, &order.collection, order.token_id, order.amount, order.royalty_max_bps);
        if royalty_amount > order.amount {
            panic_with_error!(&e, VenueError::RoyaltyExceedsSale);
        }
        let seller_amount = order.amount - royalty_amount;

        let pay = token::Client::new(&e, &order.payment_token);
        let venue = e.current_contract_address();
        match order.side {
            Side::Listing => {
                // Payment from the fulfiller, then the NFT via the venue's approval.
                if royalty_amount > 0 {
                    pay.transfer(&fulfiller, royalty_receiver.as_ref().unwrap(), &royalty_amount);
                }
                if seller_amount > 0 {
                    pay.transfer(&fulfiller, &order.offerer, &seller_amount);
                }
                Self::nft_transfer_from(&e, &order.collection, &venue, &order.offerer, &fulfiller, order.token_id);
            }
            Side::Bid => {
                // Payment through the bidder's allowance, then the NFT under
                // the fulfiller's own authorization.
                if royalty_amount > 0 {
                    pay.transfer_from(&venue, &order.offerer, royalty_receiver.as_ref().unwrap(), &royalty_amount);
                }
                if seller_amount > 0 {
                    pay.transfer_from(&venue, &order.offerer, &fulfiller, &seller_amount);
                }
                Self::nft_transfer_from(&e, &order.collection, &fulfiller, &fulfiller, &order.offerer, order.token_id);
            }
        }

        e.events().publish(
            (EVT_FILLED, order.offerer.clone(), fulfiller),
            (salt, order.amount, royalty_receiver, royalty_amount),
        );
    }

    /// Bulk-cancel: bump the caller's counter, invalidating all of their
    /// outstanding orders registered under the previous counter.
    pub fn increment_counter(e: Env, offerer: Address) {
        offerer.require_auth();
        let new_counter = Self::get_counter(e.clone(), offerer.clone()) + 1;
        e.storage().persistent().set(&DataKey::Counter(offerer.clone()), &new_counter);
        e.events().publish((EVT_COUNTER, offerer), new_counter);
    }

    pub fn get_order(e: Env, offerer: Address, salt: u64) -> Order {
        e.storage()
            .persistent()
            .get(&DataKey::Order(offerer, salt))
            .unwrap_or_else(|| panic_with_error!(&e, VenueError::OrderNotFound))
    }

    pub fn get_counter(e: Env, offerer: Address) -> u64 {
        e.storage().persistent().get(&DataKey::Counter(offerer)).unwrap_or(0)
    }

    pub fn version(e: Env) -> String {
        String::from_str(&e, "1.0.0")
    }

    /// Royalty via the collection's royalty_info interface, capped at the
    /// signed maximum. Absent interface, failed call, or zero amounts yield
    /// no royalty.
    fn capped_royalty(
        e: &Env,
        collection: &Address,
        token_id: u32,
        sale_amount: i128,
        royalty_max_bps: u32,
    ) -> (Option<Address>, i128) {
        if sale_amount == 0 {
            return (None, 0);
        }
        let args = vec![e, token_id.into_val(e), sale_amount.into_val(e)];
        let result: Result<(Address, i128), _> = e
            .try_invoke_contract::<(Address, i128), soroban_sdk::Error>(
                collection,
                &Symbol::new(e, "royalty_info"),
                args,
            )
            .map_err(|_| ())
            .and_then(|inner| inner.map_err(|_| ()));
        let Ok((receiver, raw_amount)) = result else {
            return (None, 0);
        };
        if raw_amount <= 0 {
            return (None, 0);
        }
        let max_amount = sale_amount * (royalty_max_bps as i128) / 10_000;
        let capped = raw_amount.min(max_amount);
        if capped <= 0 {
            return (None, 0);
        }
        (Some(receiver), capped)
    }

    /// NFT delivery through the collection's transfer_from surface.
    fn nft_transfer_from(
        e: &Env,
        collection: &Address,
        spender: &Address,
        from: &Address,
        to: &Address,
        token_id: u32,
    ) {
        let args = vec![
            e,
            spender.into_val(e),
            from.into_val(e),
            to.into_val(e),
            token_id.into_val(e),
        ];
        let _: Val = e.invoke_contract(collection, &Symbol::new(e, "transfer_from"), args);
    }
}

mod test;
