#[starknet::contract]
pub mod Medialane {
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_utils::cryptography::nonces::NoncesComponent;
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use core::num::traits::Zero;
    use crate::core::interface::*;
    use crate::core::types::*;
    use crate::core::utils::*;

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        orders: Map<felt252, OrderDetails>,
        // Immutable after construction — set once, never changed (no admin key).
        native_token_address: ContractAddress,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OrderCreated: OrderCreated,
        OrderFulfilled: OrderFulfilled,
        OrderCancelled: OrderCancelled,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
    }

    use crate::core::events::*;

    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Medialane'
        }
        fn version() -> felt252 {
            1
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, native_token_address: ContractAddress) {
        assert!(!native_token_address.is_zero(), "Native token cannot be zero");
        self.native_token_address.write(native_token_address);
    }

    #[abi(embed_v0)]
    impl MedialaneImpl of IMedialane<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let order_parameters = order.parameters;
            let signature = order.signature;
            let offerer = order_parameters.offerer;

            assert!(!offerer.is_zero(), "Offerer cannot be zero");

            let offer_type_valid: Option<ItemType> = order_parameters.offer.item_type.try_into();
            assert!(offer_type_valid.is_some(), "Invalid item type");
            let consideration_type_valid: Option<ItemType> = order_parameters
                .consideration
                .item_type
                .try_into();
            assert!(consideration_type_valid.is_some(), "Invalid item type");

            // Fixed price only — Dutch auction interpolation is not supported.
            assert!(
                order_parameters.offer.start_amount == order_parameters.offer.end_amount,
                "End amount must equal start",
            );
            assert!(
                order_parameters.consideration.start_amount == order_parameters
                    .consideration
                    .end_amount,
                "End amount must equal start",
            );

            let order_hash = order_parameters.get_message_hash(offerer);

            // Cheap state checks before the expensive SRC-6 external call.
            self._assert_order_status_none(order_hash);

            let start_time = felt_to_u64(order_parameters.start_time);
            let end_time = felt_to_u64(order_parameters.end_time);
            self._validate_future_order(start_time, end_time);

            self._validate_hash_signature(order_hash, offerer, signature);

            self.nonces.use_checked_nonce(offerer, order_parameters.nonce);

            let order_details = OrderDetails {
                offerer: order_parameters.offerer,
                offer: order_parameters.offer,
                consideration: order_parameters.consideration,
                start_time: start_time,
                end_time: end_time,
                order_status: OrderStatus::Created,
                fulfiller: Option::None,
            };

            self.orders.write(order_hash, order_details);

            self
                .emit(
                    Event::OrderCreated(
                        OrderCreated { order_hash: order_hash, offerer: order_parameters.offerer },
                    ),
                );
        }

        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            let fulfillment_intent = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment_intent.order_hash;

            let mut order_details = self._assert_order_status_created(order_hash);

            let fulfiller = fulfillment_intent.fulfiller;

            // Caller must be the fulfiller — prevents front-running via mempool replay.
            assert!(get_caller_address() == fulfiller, "Caller not fulfiller");

            let fulfillment_hash = fulfillment_intent.get_message_hash(fulfiller);
            self._validate_hash_signature(fulfillment_hash, fulfiller, signature);

            self._validate_active_order(order_details.start_time, order_details.end_time);

            self.nonces.use_checked_nonce(fulfiller, fulfillment_intent.nonce);

            // CEI: mark filled before external token transfers.
            order_details.order_status = OrderStatus::Filled;
            order_details.fulfiller = Option::Some(fulfiller);
            self.orders.write(order_hash, order_details);

            self._execute_transfers(order_details, fulfiller);

            self
                .emit(
                    Event::OrderFulfilled(
                        OrderFulfilled {
                            order_hash: order_hash,
                            offerer: order_details.offerer,
                            fulfiller: fulfiller,
                        },
                    ),
                );
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancelation_intent = cancel_request.cancelation;
            let signature = cancel_request.signature;

            let offerer = cancelation_intent.offerer;
            let order_hash = cancelation_intent.order_hash;

            let mut order_details = self._assert_order_status_created(order_hash);

            // Only the original offerer may cancel.
            assert!(offerer == order_details.offerer, "Caller not offerer");

            let cancelation_hash = cancelation_intent.get_message_hash(offerer);
            self._validate_hash_signature(cancelation_hash, offerer, signature);

            order_details.order_status = OrderStatus::Cancelled;

            self.nonces.use_checked_nonce(offerer, cancelation_intent.nonce);

            self.orders.write(order_hash, order_details);

            self
                .emit(
                    Event::OrderCancelled(
                        OrderCancelled { order_hash: order_hash, offerer: order_details.offerer },
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

        fn get_native_token_address(self: @ContractState) -> ContractAddress {
            self.native_token_address.read()
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Asserts current timestamp is at or before start_time (used during registration).
        fn _validate_future_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert!(now <= start_time, "Order not yet valid");
            if end_time != 0 {
                assert!(now < end_time, "Order expired");
            }
        }

        /// Asserts current timestamp is within the active window (used during fulfillment).
        fn _validate_active_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert!(now >= start_time, "Order not yet valid");
            if end_time != 0 {
                assert!(now < end_time, "Order expired");
            }
        }

        /// Reads the order and asserts it has not been registered before (status == None).
        fn _assert_order_status_none(self: @ContractState, order_hash: felt252) {
            let order_details = self.orders.read(order_hash);
            match order_details.order_status {
                OrderStatus::None => {},
                OrderStatus::Created => panic!("Order already created"),
                OrderStatus::Filled => panic!("Order already filled"),
                OrderStatus::Cancelled => panic!("Order cancelled"),
            }
        }

        /// Reads the order, asserts it is in Created status, and returns the details.
        /// Callers reuse the returned struct to avoid a second storage read.
        fn _assert_order_status_created(
            self: @ContractState, order_hash: felt252,
        ) -> OrderDetails {
            let order_details = self.orders.read(order_hash);
            match order_details.order_status {
                OrderStatus::None => panic!("Order not found"),
                OrderStatus::Created => {},
                OrderStatus::Filled => panic!("Order already filled"),
                OrderStatus::Cancelled => panic!("Order cancelled"),
            }
            order_details
        }

        /// Calls `is_valid_signature` on the signer's SRC-6 account contract.
        fn _validate_hash_signature(
            self: @ContractState,
            order_hash: felt252,
            signer_address: ContractAddress,
            signature: Array<felt252>,
        ) {
            let result = ISRC6Dispatcher { contract_address: signer_address }
                .is_valid_signature(order_hash, signature);
            assert!(
                result == starknet::VALIDATED || result == 1, "Invalid signature",
            );
        }

        /// Transfers offered asset offerer→fulfiller and consideration fulfiller→recipient.
        fn _execute_transfers(
            ref self: ContractState, parameters: OrderDetails, fulfiller: ContractAddress,
        ) {
            let offerer = parameters.offerer;

            let offer_type: Option<ItemType> = parameters.offer.item_type.try_into();
            assert!(offer_type.is_some(), "Invalid item type");

            self
                ._transfer_item(
                    felt_to_u256(parameters.offer.start_amount),
                    parameters.offer.token,
                    offer_type.unwrap(),
                    felt_to_u256(parameters.offer.identifier_or_criteria),
                    offerer,
                    fulfiller,
                );

            let consideration = parameters.consideration;
            assert!(!consideration.recipient.is_zero(), "Recipient cannot be zero");

            let consideration_type: Option<ItemType> = consideration.item_type.try_into();
            assert!(consideration_type.is_some(), "Invalid item type");

            self
                ._transfer_item(
                    felt_to_u256(consideration.start_amount),
                    consideration.token,
                    consideration_type.unwrap(),
                    felt_to_u256(consideration.identifier_or_criteria),
                    fulfiller,
                    consideration.recipient,
                );
        }

        fn _transfer_item(
            ref self: ContractState,
            amount: u256,
            token: ContractAddress,
            item_type: ItemType,
            identifier: u256,
            from: ContractAddress,
            to: ContractAddress,
        ) {
            assert!(amount > 0_u256, "Invalid amount");

            match item_type {
                ItemType::NATIVE => {
                    let success = IERC20Dispatcher {
                        contract_address: self.native_token_address.read(),
                    }
                        .transfer_from(from, to, amount);
                    assert!(success, "STRK transfer failed");
                },
                ItemType::ERC20 => {
                    assert!(!token.is_zero(), "Token address cannot be zero");
                    let success = IERC20Dispatcher { contract_address: token }
                        .transfer_from(from, to, amount);
                    assert!(success, "Transfer failed");
                },
                ItemType::ERC721 => {
                    assert!(amount == 1_u256, "Invalid amount");
                    assert!(!token.is_zero(), "Token address cannot be zero");
                    IERC721Dispatcher { contract_address: token }
                        .transfer_from(from, to, identifier);
                },
                ItemType::ERC1155 => {
                    assert!(!token.is_zero(), "Token address cannot be zero");
                    IERC1155Dispatcher { contract_address: token }
                        .safe_transfer_from(from, to, identifier, amount, array![].span());
                },
            }
        }
    }
}
