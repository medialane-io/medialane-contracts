/// Medialane1155 — immutable ERC1155 marketplace venue (Seaport-style signed orders,
/// with partial fills and per-unit pricing).
///
/// Safety model — every check is on-chain and falls in exactly one bucket:
///   1. Statically determinable from the signed order → validated at registration,
///      fail-fast: offerer != 0, marketplace == self, counter, royalty_max_bps <= 10000,
///      trade shape (ERC1155 <-> {NATIVE, ERC20}, both directions, NFT contract != the
///      resolved payment token), recipient != 0, time window, offerer signature.
///   2. Mutable on-chain state (ownership, approval, balance, live EIP-2981) → not
///      pre-simulated; enforced by atomic revert at fill. Settlement pulls payment
///      before delivering the units, under a reentrancy guard with CEI. Per-unit
///      pricing (sale = price_per_unit * quantity) is overflow-checked.
///
/// No owner/admin/upgrade/pause. A future fix is a fresh declare + deploy.
#[starknet::contract]
pub mod Medialane1155 {
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::syscalls::call_contract_syscall;
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use core::num::traits::{CheckedMul, Zero};
    use core::panic_with_felt252;
    use crate::core::errors::errors;
    use crate::core::events::*;
    use crate::core::interface::IMedialane1155;
    use crate::core::types::*;
    use crate::core::utils::{felt_to_u256, felt_to_u64};

    #[storage]
    struct Storage {
        orders: Map<felt252, OrderDetails>,
        native_token_address: ContractAddress,
        cancel_counter: Map<ContractAddress, felt252>,
        entered: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OrderCreated: OrderCreated,
        OrderFulfilled: OrderFulfilled,
        OrderCancelled: OrderCancelled,
        CounterIncremented: CounterIncremented,
    }

    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Medialane'
        }
        /// Bumped on every deploy (audit S1). v3 = redesigned ERC1155 venue lineage.
        fn version() -> felt252 {
            3
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, native_token_address: ContractAddress) {
        assert!(!native_token_address.is_zero(), "Native token cannot be zero");
        self.native_token_address.write(native_token_address);
    }

    #[abi(embed_v0)]
    impl Medialane1155Impl of IMedialane1155<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let offerer = params.offerer;

            assert(!offerer.is_zero(), errors::INVALID_OFFERER);
            assert(params.marketplace == get_contract_address(), errors::WRONG_MARKETPLACE);
            assert(params.counter == self.cancel_counter.read(offerer), errors::INVALID_COUNTER);
            // royalty_max_bps is a percentage in basis points; bound it to [0, 10000]
            // so the cap math at fill cannot overflow and the invariant is explicit.
            assert(
                felt_to_u256(params.royalty_max_bps) <= 10000_u256, errors::ROYALTY_BPS_TOO_HIGH,
            );

            // Shape: ERC1155 <-> {NATIVE, ERC20}, both directions. Returns the
            // ERC1155 quantity, which seeds remaining_amount for partial fills.
            let erc1155_amount = self._validate_order_shape(params.offer, params.consideration);

            let start_time = felt_to_u64(params.start_time);
            let end_time = felt_to_u64(params.end_time);
            self._validate_registration_window(start_time, end_time);

            let order_hash = params.get_message_hash(offerer);
            self._assert_status_none(order_hash);
            self._validate_signature(order_hash, offerer, order.signature);

            let details = OrderDetails {
                offerer,
                offer: params.offer,
                consideration: params.consideration,
                royalty_max_bps: params.royalty_max_bps,
                start_time,
                end_time,
                order_status: OrderStatus::Created,
                remaining_amount: erc1155_amount,
            };
            self.orders.write(order_hash, details);
            self.emit(Event::OrderCreated(OrderCreated { order_hash, offerer }));
        }

        fn fulfill_order(ref self: ContractState, order_hash: felt252, quantity: felt252) {
            self._reentrancy_start();

            let mut details = self._assert_status_created(order_hash);
            let fulfiller = get_caller_address();
            assert(fulfiller != details.offerer, errors::SELF_FILL);
            assert(quantity != 0, errors::INVALID_QUANTITY);

            let quantity_u256 = felt_to_u256(quantity);
            let remaining_u256 = felt_to_u256(details.remaining_amount);
            assert(quantity_u256 <= remaining_u256, errors::INSUFFICIENT_REMAINING);

            self._validate_active_order(details.start_time, details.end_time);

            // CEI: persist the new remaining/status before any external call.
            let new_remaining_u256 = remaining_u256 - quantity_u256;
            let new_remaining: felt252 = new_remaining_u256.try_into().unwrap();
            details.remaining_amount = new_remaining;
            details.order_status = if new_remaining == 0 {
                OrderStatus::Filled
            } else {
                OrderStatus::Created
            };
            self.orders.write(order_hash, details);

            let (sale_amount, royalty_receiver, royalty_amount) = self
                ._execute_transfers(details, fulfiller, quantity);

            self
                .emit(
                    Event::OrderFulfilled(
                        OrderFulfilled {
                            order_hash,
                            offerer: details.offerer,
                            fulfiller,
                            quantity,
                            remaining_amount: new_remaining,
                            sale_amount,
                            royalty_receiver,
                            royalty_amount,
                        },
                    ),
                );

            self._reentrancy_end();
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancellation = cancel_request.cancelation;
            let offerer = cancellation.offerer;
            let order_hash = cancellation.order_hash;

            let mut details = self._assert_status_created(order_hash);
            assert(offerer == details.offerer, errors::CALLER_NOT_OFFERER);

            let cancel_hash = cancellation.get_message_hash(offerer);
            self._validate_signature(cancel_hash, offerer, cancel_request.signature);

            details.order_status = OrderStatus::Cancelled;
            self.orders.write(order_hash, details);
            self.emit(Event::OrderCancelled(OrderCancelled { order_hash, offerer }));
        }

        fn increment_counter(ref self: ContractState) {
            let caller = get_caller_address();
            let new_counter = self.cancel_counter.read(caller) + 1;
            self.cancel_counter.write(caller, new_counter);
            self
                .emit(
                    Event::CounterIncremented(
                        CounterIncremented { offerer: caller, new_counter },
                    ),
                );
        }

        fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails {
            self.orders.read(order_hash)
        }

        fn get_order_hash(
            self: @ContractState, parameters: OrderParameters, signer: ContractAddress,
        ) -> felt252 {
            parameters.get_message_hash(signer)
        }

        fn get_cancellation_hash(
            self: @ContractState, cancellation: OrderCancellation, signer: ContractAddress,
        ) -> felt252 {
            cancellation.get_message_hash(signer)
        }

        fn get_counter(self: @ContractState, offerer: ContractAddress) -> felt252 {
            self.cancel_counter.read(offerer)
        }

        fn get_native_token_address(self: @ContractState) -> ContractAddress {
            self.native_token_address.read()
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Enforces ERC1155 <-> payment shape (both directions) and returns the
        /// ERC1155 quantity (used to seed remaining_amount).
        fn _validate_order_shape(
            self: @ContractState, offer: OfferItem, consideration: ConsiderationItem,
        ) -> felt252 {
            let offer_type: Option<ItemType> = offer.item_type.try_into();
            assert(offer_type.is_some(), errors::INVALID_ITEM_TYPE);
            let consideration_type: Option<ItemType> = consideration.item_type.try_into();
            assert(consideration_type.is_some(), errors::INVALID_ITEM_TYPE);

            assert(!consideration.recipient.is_zero(), errors::INVALID_RECIPIENT);

            match offer_type.unwrap() {
                // Listing: ERC1155 for payment.
                ItemType::ERC1155 => {
                    self._validate_erc1155_item(offer.token, offer.amount);
                    self
                        ._validate_payment_item(
                            consideration_type.unwrap(),
                            consideration.token,
                            consideration.identifier_or_criteria,
                        );
                    // The ERC1155 contract must not double as the payment token
                    // (resolved for NATIVE), or settlement is an incoherent trade.
                    let pay = self._payment_token(consideration.item_type, consideration.token);
                    assert(offer.token != pay, errors::PAYMENT_TOKEN_IS_NFT);
                    offer.amount
                },
                // Bid: payment for ERC1155.
                ItemType::NATIVE | ItemType::ERC20 => {
                    self
                        ._validate_payment_item(
                            offer_type.unwrap(), offer.token, offer.identifier_or_criteria,
                        );
                    match consideration_type.unwrap() {
                        ItemType::ERC1155 => {},
                        _ => panic_with_felt252(errors::UNSUPPORTED_SHAPE),
                    }
                    self._validate_erc1155_item(consideration.token, consideration.amount);
                    // The ERC1155 contract must not double as the payment token
                    // (resolved for NATIVE), or settlement is an incoherent trade.
                    let pay = self._payment_token(offer.item_type, offer.token);
                    assert(consideration.token != pay, errors::PAYMENT_TOKEN_IS_NFT);
                    consideration.amount
                },
            }
        }

        fn _validate_erc1155_item(self: @ContractState, token: ContractAddress, amount: felt252) {
            assert(!token.is_zero(), errors::INVALID_TOKEN_ADDRESS);
            assert(amount != 0, errors::INVALID_AMOUNT);
        }

        /// Payment leg. `amount` may be zero (F9: free orders allowed).
        fn _validate_payment_item(
            self: @ContractState,
            item_type: ItemType,
            token: ContractAddress,
            identifier: felt252,
        ) {
            match item_type {
                ItemType::NATIVE => {
                    assert(token.is_zero(), errors::NONZERO_NATIVE_TOKEN);
                    assert(identifier == 0, errors::INVALID_IDENTIFIER);
                },
                ItemType::ERC20 => {
                    assert(!token.is_zero(), errors::INVALID_TOKEN_ADDRESS);
                    assert(identifier == 0, errors::INVALID_IDENTIFIER);
                },
                ItemType::ERC1155 => panic_with_felt252(errors::UNSUPPORTED_SHAPE),
            }
        }

        fn _validate_registration_window(self: @ContractState, start_time: u64, end_time: u64) {
            if end_time != 0 {
                assert(start_time < end_time, errors::INVALID_TIME_WINDOW);
                assert(get_block_timestamp() < end_time, errors::ORDER_EXPIRED);
            }
        }

        fn _validate_active_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert(now >= start_time, errors::ORDER_NOT_YET_VALID);
            if end_time != 0 {
                assert(now < end_time, errors::ORDER_EXPIRED);
            }
        }

        fn _assert_status_none(self: @ContractState, order_hash: felt252) {
            match self.orders.read(order_hash).order_status {
                OrderStatus::None => {},
                OrderStatus::Created => panic_with_felt252(errors::ORDER_ALREADY_CREATED),
                OrderStatus::Filled => panic_with_felt252(errors::ORDER_ALREADY_FILLED),
                OrderStatus::Cancelled => panic_with_felt252(errors::ORDER_CANCELLED),
            }
        }

        fn _assert_status_created(self: @ContractState, order_hash: felt252) -> OrderDetails {
            let details = self.orders.read(order_hash);
            match details.order_status {
                OrderStatus::None => panic_with_felt252(errors::ORDER_NOT_FOUND),
                OrderStatus::Created => {},
                OrderStatus::Filled => panic_with_felt252(errors::ORDER_ALREADY_FILLED),
                OrderStatus::Cancelled => panic_with_felt252(errors::ORDER_CANCELLED),
            }
            details
        }

        fn _validate_signature(
            self: @ContractState,
            hash: felt252,
            signer: ContractAddress,
            signature: Array<felt252>,
        ) {
            let result = ISRC6Dispatcher { contract_address: signer }
                .is_valid_signature(hash, signature);
            assert(result == starknet::VALIDATED || result == 1, errors::INVALID_SIGNATURE);
        }

        fn _reentrancy_start(ref self: ContractState) {
            assert(!self.entered.read(), errors::REENTRANT_CALL);
            self.entered.write(true);
        }

        fn _reentrancy_end(ref self: ContractState) {
            self.entered.write(false);
        }

        /// Settles `quantity` units. Pulls payment from the payer (royalty first,
        /// then the seller's remainder) and only THEN delivers the ERC1155 units
        /// (payment-before-delivery, audit R1). Per-unit pricing (audit R3):
        /// sale = price_per_unit * quantity.
        fn _execute_transfers(
            self: @ContractState,
            details: OrderDetails,
            fulfiller: ContractAddress,
            quantity: felt252,
        ) -> (u256, ContractAddress, u256) {
            let offer_type: ItemType = details.offer.item_type.try_into().unwrap();
            let amount = felt_to_u256(quantity);

            match offer_type {
                // Listing: buyer (fulfiller) pays; units go offerer -> fulfiller.
                ItemType::ERC1155 => {
                    let token_id = felt_to_u256(details.offer.identifier_or_criteria);
                    let sale_amount = self
                        ._unit_sale(details.consideration.amount, amount);
                    let (royalty_receiver, royalty_amount) = self
                        ._pay(
                            details.consideration.item_type,
                            details.consideration.token,
                            fulfiller,
                            details.consideration.recipient,
                            details.offer.token,
                            token_id,
                            sale_amount,
                            details.royalty_max_bps,
                        );
                    IERC1155Dispatcher { contract_address: details.offer.token }
                        .safe_transfer_from(
                            details.offerer, fulfiller, token_id, amount, array![].span(),
                        );
                    (sale_amount, royalty_receiver, royalty_amount)
                },
                // Bid: bidder (offerer) pays; units go fulfiller -> bidder (recipient).
                ItemType::NATIVE | ItemType::ERC20 => {
                    let token_id = felt_to_u256(details.consideration.identifier_or_criteria);
                    let sale_amount = self._unit_sale(details.offer.amount, amount);
                    let (royalty_receiver, royalty_amount) = self
                        ._pay(
                            details.offer.item_type,
                            details.offer.token,
                            details.offerer,
                            fulfiller,
                            details.consideration.token,
                            token_id,
                            sale_amount,
                            details.royalty_max_bps,
                        );
                    IERC1155Dispatcher { contract_address: details.consideration.token }
                        .safe_transfer_from(
                            fulfiller,
                            details.consideration.recipient,
                            token_id,
                            amount,
                            array![].span(),
                        );
                    (sale_amount, royalty_receiver, royalty_amount)
                },
            }
        }

        /// price_per_unit * quantity, overflow-checked.
        fn _unit_sale(self: @ContractState, price_per_unit: felt252, quantity: u256) -> u256 {
            match felt_to_u256(price_per_unit).checked_mul(quantity) {
                Option::Some(v) => v,
                Option::None => panic_with_felt252(errors::PRICE_OVERFLOW),
            }
        }

        fn _pay(
            self: @ContractState,
            payment_item_type: felt252,
            payment_token: ContractAddress,
            payer: ContractAddress,
            seller_recipient: ContractAddress,
            nft: ContractAddress,
            token_id: u256,
            sale_amount: u256,
            royalty_max_bps: felt252,
        ) -> (ContractAddress, u256) {
            let token_address = self._payment_token(payment_item_type, payment_token);
            let erc20 = IERC20Dispatcher { contract_address: token_address };

            let (royalty_receiver, royalty_amount) = self
                ._get_royalty(nft, token_id, sale_amount, royalty_max_bps);

            if royalty_amount > 0 {
                assert(royalty_amount <= sale_amount, errors::ROYALTY_EXCEEDS_SALE);
                let ok = erc20.transfer_from(payer, royalty_receiver, royalty_amount);
                assert(ok, errors::ROYALTY_TRANSFER_FAILED);
            }
            let seller_amount = sale_amount - royalty_amount;
            if seller_amount > 0 {
                let ok = erc20.transfer_from(payer, seller_recipient, seller_amount);
                assert(ok, errors::TRANSFER_FAILED);
            }
            (royalty_receiver, royalty_amount)
        }

        fn _payment_token(
            self: @ContractState, payment_item_type: felt252, payment_token: ContractAddress,
        ) -> ContractAddress {
            let parsed: ItemType = payment_item_type.try_into().unwrap();
            match parsed {
                ItemType::NATIVE => self.native_token_address.read(),
                ItemType::ERC20 => payment_token,
                ItemType::ERC1155 => panic_with_felt252(errors::UNSUPPORTED_SHAPE),
            }
        }

        /// EIP-2981 royalty capped at the seller-signed `royalty_max_bps` (/10_000).
        /// Non-2981 NFTs or any failure => no royalty.
        fn _get_royalty(
            self: @ContractState,
            nft: ContractAddress,
            token_id: u256,
            sale_amount: u256,
            royalty_max_bps: felt252,
        ) -> (ContractAddress, u256) {
            let zero: ContractAddress = 0.try_into().unwrap();
            if sale_amount == 0 {
                return (zero, 0);
            }

            let supports = match call_contract_syscall(
                nft, selector!("supports_interface"), array![IERC2981_ID].span(),
            ) {
                Result::Ok(ret) => ret.len() > 0 && *ret.at(0) != 0,
                Result::Err(_) => false,
            };
            if !supports {
                return (zero, 0);
            }

            let calldata = array![
                token_id.low.into(), token_id.high.into(), sale_amount.low.into(),
                sale_amount.high.into(),
            ];
            let (receiver, raw_amount) = match call_contract_syscall(
                nft, selector!("royalty_info"), calldata.span(),
            ) {
                Result::Ok(ret) => {
                    if ret.len() < 3 {
                        return (zero, 0);
                    }
                    let recv: Option<ContractAddress> = (*ret.at(0)).try_into();
                    let low: Option<u128> = (*ret.at(1)).try_into();
                    let high: Option<u128> = (*ret.at(2)).try_into();
                    match (recv, low, high) {
                        (
                            Option::Some(r), Option::Some(l), Option::Some(h),
                        ) => (r, u256 { low: l, high: h }),
                        _ => { return (zero, 0); },
                    }
                },
                Result::Err(_) => { return (zero, 0); },
            };

            if receiver.is_zero() || raw_amount == 0 {
                return (zero, 0);
            }

            let max_amount = (sale_amount * felt_to_u256(royalty_max_bps)) / 10000_u256;
            let capped = if raw_amount > max_amount {
                max_amount
            } else {
                raw_amount
            };
            if capped == 0 {
                return (zero, 0);
            }
            (receiver, capped)
        }
    }
}
