#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, Address,
    Env, String, Symbol,
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
}

mod test;
