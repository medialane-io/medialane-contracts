#[starknet::contract]
pub mod Medialane {
    use openzeppelin_access::accesscontrol::AccessControlComponent::InternalTrait;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_upgrades::interface::IUpgradeable;
    use openzeppelin_upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin_utils::cryptography::nonces::NoncesComponent;
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_caller_address};
    use crate::core::errors::*;
    use crate::core::events::*;
    use crate::core::interface::*;
    use crate::core::types::*;
    use crate::core::utils::*;

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;


    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        orders: Map<felt252, OrderDetails>,
        native_token_address: ContractAddress, // STRK token address
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OrderCreated: OrderCreated,
        OrderFulfilled: OrderFulfilled,
        OrderCancelled: OrderCancelled,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
    }

    /// Required for hash computation.
    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Medialane'
        }
        fn version() -> felt252 {
            1
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, manager: ContractAddress, native_token_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, manager);
        self.native_token_address.write(native_token_address);
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl MedialaneImpl of IMedialane<ContractState> {
        /// Registers a new order in the contract.
        ///
        /// This function validates the order's signature, status, and timing, then stores the order
        /// details in contract storage and emits an `OrderCreated` event.
        ///
        /// # Arguments
        /// * `order` - The `Order` struct containing order parameters and signature.
        ///
        /// # Panics
        /// * `errors::INVALID_SIGNATURE` if the signature is invalid.
        /// * `errors::ORDER_ALREADY_CREATED` if the order already exists.
        /// * `errors::ORDER_NOT_YET_VALID` if the order's start time is in the future.
        /// * `errors::ORDER_EXPIRED` if the order's end time has passed.
        /// * `NoncesComponent` errors if the nonce is invalid or reused.
        fn register_order(ref self: ContractState, order: Order) {
            let order_parameters = order.parameters;
            let signature = order.signature;

            let offerer = order_parameters.offerer;

            // M-09: Reject zero-address offerer
            assert(offerer != 0.try_into().unwrap(), errors::INVALID_OFFERER);

            // M-07: Validate item types are recognised at registration, not only at fulfillment
            let offer_type_valid: Option<ItemType> = order_parameters.offer.item_type.try_into();
            assert(offer_type_valid.is_some(), errors::INVALID_ITEM_TYPE);
            let consideration_type_valid: Option<ItemType> = order_parameters
                .consideration
                .item_type
                .try_into();
            assert(consideration_type_valid.is_some(), errors::INVALID_ITEM_TYPE);

            // M-04: Dutch-auction interpolation is not implemented — enforce fixed price
            assert(
                order_parameters.offer.start_amount == order_parameters.offer.end_amount,
                errors::END_AMOUNT_MISMATCH,
            );
            assert(
                order_parameters.consideration.start_amount == order_parameters
                    .consideration
                    .end_amount,
                errors::END_AMOUNT_MISMATCH,
            );

            let order_hash = order_parameters.get_message_hash(offerer);

            // Cheap checks first — avoid paying for the SRC-6 external call on a doomed order
            self._assert_order_status(order_hash, OrderStatus::None);

            let start_time = felt_to_u64(order_parameters.start_time);
            let end_time = felt_to_u64(order_parameters.end_time);
            self._validate_future_order(start_time, end_time);

            // Signature verify (expensive external call) only after all cheap checks pass
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

        /// Fulfills an existing order.
        ///
        /// This function validates the order's status, the fulfiller's signature, and timing, then
        /// executes the asset transfers between offerer and fulfiller, updates the order status,
        /// and emits an `OrderFulfilled` event.
        ///
        /// # Arguments
        /// * `fulfillment_request` - The `FulfillmentRequest` struct containing fulfillment intent
        /// and signature.
        ///
        /// # Panics
        /// * `errors::ORDER_NOT_FOUND` if the order does not exist.
        /// * `errors::ORDER_ALREADY_FILLED` if the order is already filled.
        /// * `errors::ORDER_CANCELLED` if the order is cancelled.
        /// * `errors::INVALID_SIGNATURE` if the fulfiller's signature is invalid.
        /// * `errors::ORDER_NOT_YET_VALID` if the order's start time is in the future.
        /// * `errors::ORDER_EXPIRED` if the order's end time has passed.
        /// * `NoncesComponent` errors if the nonce is invalid or reused.
        /// * Transfer errors as described in `_transfer_item`.
        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            let fulfillment_intent = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment_intent.order_hash;

            // Single storage read — _assert_order_status returns the order we already fetched
            let mut order_details = self._assert_order_status(order_hash, OrderStatus::Created);

            let fulfiller = fulfillment_intent.fulfiller;

            // M-02: Caller must be the fulfiller — prevents front-running via mempool replay
            assert(get_caller_address() == fulfiller, errors::CALLER_NOT_FULFILLER);

            let fulfillment_hash = fulfillment_intent.get_message_hash(fulfiller);

            self._validate_hash_signature(fulfillment_hash, fulfiller, signature);

            // Validate Order Timing (Start/End Time)
            self._validate_active_order(order_details.start_time, order_details.end_time);

            self.nonces.use_checked_nonce(fulfiller, fulfillment_intent.nonce);

            // M-05: Effects before Interactions (CEI) — mark order filled before external calls
            // so a re-entrant ERC-1155 onReceived callback cannot re-enter fulfill_order
            order_details.order_status = OrderStatus::Filled;
            order_details.fulfiller = Option::Some(fulfiller);
            self.orders.write(order_hash, order_details);

            // Execute Transfers (Interaction — after state is committed)
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

        /// Cancels an existing order.
        ///
        /// This function validates the order's status and the offerer's signature, marks the order
        /// as cancelled, consumes the nonce, updates storage, and emits an `OrderCancelled` event.
        ///
        /// # Arguments
        /// * `cancel_request` - The `CancelRequest` struct containing cancellation intent and
        /// signature.
        ///
        /// # Panics
        /// * `errors::ORDER_NOT_FOUND` if the order does not exist.
        /// * `errors::ORDER_ALREADY_FILLED` if the order is already filled.
        /// * `errors::ORDER_CANCELLED` if the order is already cancelled.
        /// * `errors::INVALID_SIGNATURE` if the offerer's signature is invalid.
        /// * `NoncesComponent` errors if the nonce is invalid or reused.
        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancelation_intent = cancel_request.cancelation;
            let signature = cancel_request.signature;

            let offerer = cancelation_intent.offerer;
            let order_hash = cancelation_intent.order_hash;

            // Single storage read — _assert_order_status returns the order we already fetched
            let mut order_details = self._assert_order_status(order_hash, OrderStatus::Created);

            // M-03: Verify the cancellation signer is the actual offerer of this order.
            // Without this, any SRC-6 account could cancel any other user's order.
            assert(offerer == order_details.offerer, errors::CALLER_NOT_OFFERER);

            let cancelation_hash = cancelation_intent.get_message_hash(offerer);
            self._validate_hash_signature(cancelation_hash, offerer, signature);

            order_details.order_status = OrderStatus::Cancelled;

            self.nonces.use_checked_nonce(offerer, cancelation_intent.nonce);

            // Update Order Status
            self.orders.write(order_hash, order_details);

            self
                .emit(
                    Event::OrderCancelled(
                        OrderCancelled { order_hash: order_hash, offerer: order_details.offerer },
                    ),
                );
        }

        /// Retrieves the details of an order by its hash.
        ///
        /// # Arguments
        /// * `order_hash` - The hash of the order to retrieve.
        ///
        /// # Returns
        /// * `OrderDetails` - The details of the order.
        fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails {
            self.orders.read(order_hash)
        }

        /// Computes the hash for a given set of order parameters and signer.
        ///
        /// # Arguments
        /// * `parameters` - The `OrderParameters` struct to hash.
        /// * `signer` - The address of the signer.
        ///
        /// # Returns
        /// * `felt252` - The computed order hash.
        fn get_order_hash(
            self: @ContractState, parameters: OrderParameters, signer: ContractAddress,
        ) -> felt252 {
            parameters.get_message_hash(signer)
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Validates the order's timing constraints.
        ///
        /// Ensures the current block timestamp is before the order's `start_time`,
        /// meaning the order is scheduled for the future and not yet valid.
        ///
        /// # Arguments
        /// * `start_time` - The start time of the order (inclusive).
        /// * `end_time` - The end time of the order (exclusive). If zero, no expiry is enforced.
        ///
        /// # Panics
        /// * `errors::ORDER_NOT_YET_VALID` if the current time is already past or equal to
        /// `start_time`.
        /// * `errors::ORDER_EXPIRED` if the current time is after or equal to `end_time` (when
        /// `end_time` is nonzero).

        /// Validates that the order is scheduled for the future (not yet valid)
        fn _validate_future_order(self: @ContractState, start_time: u64, end_time: u64) {
            let current_timestamp = get_block_timestamp();
            // Allow start_time == current block (immediately-active orders)
            assert(current_timestamp <= start_time, errors::ORDER_NOT_YET_VALID);

            if end_time != 0 {
                assert(current_timestamp < end_time, errors::ORDER_EXPIRED);
            }
        }

        /// Validates the order's timing constraints.
        ///
        /// Ensures the current block timestamp is within the order's valid time window.
        ///
        /// # Arguments
        /// * `start_time` - The start time of the order (inclusive).
        /// * `end_time` - The end time of the order (exclusive). If zero, no expiry is enforced.
        ///
        /// # Panics
        /// * `errors::ORDER_NOT_YET_VALID` if the current time is before `start_time`.
        /// * `errors::ORDER_EXPIRED` if the current time is after or equal to `end_time` (when
        /// `end_time` is nonzero).

        fn _validate_active_order(self: @ContractState, start_time: u64, end_time: u64) {
            let current_timestamp = get_block_timestamp();
            assert(current_timestamp >= start_time, errors::ORDER_NOT_YET_VALID);

            if end_time != 0 {
                assert(current_timestamp < end_time, errors::ORDER_EXPIRED);
            }
        }


        /// Validates the order's status (nonce, filled, cancelled). Reverts if invalid.
        ///
        /// Checks that the order's current status matches the expected status.
        ///
        /// # Arguments
        /// * `order_hash` - The hash of the order to check.
        /// * `expected` - The expected `OrderStatus`.
        ///
        /// # Panics
        /// * `errors::ORDER_NOT_FOUND` if the order does not exist.
        /// * `errors::ORDER_ALREADY_CREATED` if the order is already created.
        /// * `errors::ORDER_ALREADY_FILLED` if the order is already filled.
        /// * `errors::ORDER_CANCELLED` if the order is cancelled.
        /// Asserts the order is in `expected` status and returns its details.
        /// Callers reuse the returned struct instead of reading storage a second time.
        fn _assert_order_status(
            self: @ContractState, order_hash: felt252, expected: OrderStatus,
        ) -> OrderDetails {
            let order_details = self.orders.read(order_hash);
            let actual_status = order_details.order_status;
            assert(
                actual_status == expected,
                match actual_status {
                    OrderStatus::None => errors::ORDER_NOT_FOUND,
                    OrderStatus::Created => errors::ORDER_ALREADY_CREATED,
                    OrderStatus::Filled => errors::ORDER_ALREADY_FILLED,
                    OrderStatus::Cancelled => errors::ORDER_CANCELLED,
                },
            );
            order_details
        }

        /// Verifies the order signature against the order hash and signer address.
        ///
        /// Uses the ISRC6 interface to check if the provided signature is valid for the given hash
        /// and signer.
        ///
        /// # Arguments
        /// * `order_hash` - The hash of the order/message.
        /// * `signer_address` - The address expected to have signed the message.
        /// * `signature` - The signature to verify.
        ///
        /// # Panics
        /// * `errors::INVALID_SIGNATURE` if the signature is invalid.
        fn _validate_hash_signature(
            self: @ContractState,
            order_hash: felt252,
            signer_address: ContractAddress,
            signature: Array<felt252>,
        ) {
            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: signer_address }
                .is_valid_signature(order_hash, signature);

            let is_valid_signature = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;

            assert(is_valid_signature, errors::INVALID_SIGNATURE);
        }

        /// Executes the actual asset transfers based on the order parameters.
        ///
        /// Transfers the offered asset from the offerer to the fulfiller, and the consideration
        /// asset from the fulfiller to the specified recipient.
        ///
        /// # Arguments
        /// * `parameters` - The `OrderDetails` struct containing offer and consideration items.
        /// * `fulfiller` - The address fulfilling the order.
        ///
        /// # Panics
        /// * Panics as described in `_transfer_item` for each transfer.
        fn _execute_transfers(
            ref self: ContractState, parameters: OrderDetails, fulfiller: ContractAddress,
        ) {
            let offerer = parameters.offerer;

            // Process Offers: Offerer -> Fulfiller
            let offer_item = parameters.offer;

            // M-08: Clean error on invalid item_type (defensive — M-07 already guards at registration)
            let offer_type: Option<ItemType> = offer_item.item_type.try_into();
            assert(offer_type.is_some(), errors::INVALID_ITEM_TYPE);

            self
                ._transfer_item(
                    felt_to_u256(offer_item.start_amount),
                    offer_item.token,
                    offer_type.unwrap(),
                    felt_to_u256(offer_item.identifier_or_criteria),
                    offerer,
                    fulfiller,
                );

            // Process Considerations: Fulfiller -> Recipient specified in item
            let consideration_item = parameters.consideration;

            assert(
                consideration_item.recipient != 0.try_into().unwrap(), 'Recipient cannot be zero',
            );

            let consideration_type: Option<ItemType> = consideration_item.item_type.try_into();
            assert(consideration_type.is_some(), errors::INVALID_ITEM_TYPE);

            self
                ._transfer_item(
                    felt_to_u256(consideration_item.start_amount),
                    consideration_item.token,
                    consideration_type.unwrap(),
                    felt_to_u256(consideration_item.identifier_or_criteria),
                    fulfiller,
                    consideration_item.recipient,
                );
        }

        /// Transfers a single item of a specified type (NATIVE, ERC20, ERC721, or ERC1155) from one
        /// address to another.
        ///
        /// This is an internal helper function called by `_execute_transfers`. It handles the
        /// specific transfer logic based on the `item_type`.
        ///
        /// # Arguments
        /// * `start_amount:` - The amount of the item to transfer. For ERC721, this must be 1.
        /// * `end_amount` - The ending amount for the item.
        /// * `token` - The contract address of the token.
        /// * `item_type` - The type of the item to transfer.
        /// * `identifier_or_criteria` - The token ID for ERC721/ERC1155 items. Expected to be
        /// `Some(id)` for these types.
        /// * `from` - The address sending the item. This address must have approved the Medialane
        /// contract or have sufficient balance.
        /// * `to` - The address receiving the item.
        ///
        /// # Panics
        /// * `errors::INVALID_AMOUNT` if `start_amount` is zero, or if `start_amount` is not 1 for
        /// an `ERC721` item.
        /// * `errors::NATIVE_TRANSFER_FAILED` if the transfer of NATIVE (STRK) tokens fails.
        /// * `errors::TRANSFER_FAILED` if the transfer of ERC20 tokens fails.
        fn _transfer_item(
            ref self: ContractState,
            amount: u256,
            token: ContractAddress,
            item_type: ItemType,
            identifier: u256,
            from: ContractAddress,
            to: ContractAddress,
        ) {
            assert(amount > 0.into(), errors::INVALID_AMOUNT);

            match item_type {
                ItemType::NATIVE => {
                    // `token` param is ignored for NATIVE — uses the stored STRK address
                    // Need allowance: `from` must approve this contract address
                    let dispatcher = IERC20Dispatcher {
                        contract_address: self.native_token_address.read(),
                    };
                    let success = dispatcher.transfer_from(from, to, amount);
                    assert(success, errors::NATIVE_TRANSFER_FAILED);
                },
                ItemType::ERC20 => {
                    // Need allowance: `from` must approve this contract address
                    let success = IERC20Dispatcher { contract_address: token }
                        .transfer_from(from, to, amount);
                    assert(success, errors::TRANSFER_FAILED);
                },
                ItemType::ERC721 => {
                    assert(amount == 1.into(), errors::INVALID_AMOUNT);
                    // Need approval: `from` must setApprovalForAll for this contract address
                    IERC721Dispatcher { contract_address: token }.transfer_from(from, to, identifier);
                },
                ItemType::ERC1155 => {
                    // Need approval: `from` must setApprovalForAll for this contract address
                    IERC1155Dispatcher { contract_address: token }
                        .safe_transfer_from(from, to, identifier, amount, array![].span());
                },
            }
        }
    }
}

