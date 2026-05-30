#[starknet::contract]
pub mod Medialane1155 {
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use crate::core::errors::errors;
    use crate::core::events::*;
    use crate::core::interface::IMedialane1155;
    use crate::core::types::*;
    use crate::core::utils::felt_to_u64;

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
            panic!("not implemented");
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            panic!("not implemented");
        }

        fn increment_counter(ref self: ContractState) {
            panic!("not implemented");
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
    }
}
