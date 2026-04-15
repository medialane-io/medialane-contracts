// DESIGN: Medialane1155 is a dedicated marketplace for ERC-1155 IP assets.
//
// Order lifecycle: None → Created → Filled | Cancelled
//
// Key differences from the ERC-721 Medialane Protocol:
// - Orders are always ERC-1155 offer (token_id + amount) × STRK/ERC-20 consideration.
// - Price is price_per_unit × amount (supports multi-unit sales).
// - ERC-2981 royalties are automatically distributed at fulfillment:
//     buyer's payment is split → royalty_receiver (royalty) + offerer (remainder).
// - Same SNIP-12 signature scheme, nonce consumption, and CEI pattern.
//
// Compatible with IP-Programmable-ERC1155-Collections (deployed via IPCollectionFactory)
// which implements both ERC-1155 and ERC-2981.

#[starknet::contract]
pub mod Medialane1155 {
    use openzeppelin_access::accesscontrol::AccessControlComponent::InternalTrait;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_upgrades::interface::IUpgradeable;
    use openzeppelin_upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin_utils::cryptography::nonces::NoncesComponent;
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_caller_address};
    use core::num::traits::Zero;
    use crate::core::errors::*;
    use crate::core::events::*;
    use crate::core::interface::IMedialane1155;
    use crate::core::types::*;
    use crate::core::utils::*;

    // -----------------------------------------------------------------------
    // Inline interface definitions for ERC-2981 and SRC5 external queries.
    // Defined here to avoid dependency on a specific OZ package import path.
    // -----------------------------------------------------------------------

    #[starknet::interface]
    trait ISRC5Query<T> {
        fn supports_interface(self: @T, interface_id: felt252) -> bool;
    }

    #[starknet::interface]
    trait IERC2981<T> {
        fn royalty_info(self: @T, token_id: u256, sale_price: u256) -> (ContractAddress, u256);
    }

    // -----------------------------------------------------------------------
    // Components
    // -----------------------------------------------------------------------

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
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    #[storage]
    struct Storage {
        /// Order registry: order_hash → OrderDetails.
        orders: Map<felt252, OrderDetails>,
        /// STRK token address — used when payment_token == zero.
        native_token_address: ContractAddress,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
    }

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

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

    // -----------------------------------------------------------------------
    // SNIP-12 domain
    // -----------------------------------------------------------------------

    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Medialane1155'
        }
        fn version() -> felt252 {
            1
        }
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /// Deploys the Medialane1155 marketplace.
    ///
    /// # Arguments
    /// * `manager`              - Address granted DEFAULT_ADMIN_ROLE (can upgrade the contract)
    /// * `native_token_address` - STRK token contract address (used when payment_token == 0)
    #[constructor]
    fn constructor(
        ref self: ContractState,
        manager: ContractAddress,
        native_token_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, manager);
        self.native_token_address.write(native_token_address);
    }

    // -----------------------------------------------------------------------
    // Upgradeable
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    // -----------------------------------------------------------------------
    // IMedialane1155
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl Medialane1155Impl of IMedialane1155<ContractState> {
        /// Registers a new ERC-1155 sell order.
        ///
        /// Validates the offerer's SNIP-12 signature, order timing, and input sanity.
        /// Consumes the offerer's nonce to prevent replay.
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let signature = order.signature;
            let offerer = params.offerer;

            assert(!offerer.is_zero(), errors::INVALID_OFFERER);
            assert(!params.nft_contract.is_zero(), errors::INVALID_NFT_CONTRACT);
            assert(params.amount != 0, errors::INVALID_AMOUNT);
            assert(params.price_per_unit != 0, errors::INVALID_PRICE);

            // Fixed-price only: start_amount == end_amount (no Dutch auction)
            // (amounts are the same field here — price_per_unit is immutable)

            let order_hash = params.get_message_hash(offerer);

            // Cheap state check before the expensive SRC-6 external call
            self._assert_order_status(order_hash, OrderStatus::None);

            let start_time = felt_to_u64(params.start_time);
            let end_time = felt_to_u64(params.end_time);
            self._validate_future_order(start_time, end_time);

            // Signature verification (external call) only after all cheap checks pass
            self._validate_hash_signature(order_hash, offerer, signature);

            self.nonces.use_checked_nonce(offerer, params.nonce);

            let order_details = OrderDetails {
                offerer,
                nft_contract: params.nft_contract,
                token_id: params.token_id,
                amount: params.amount,
                payment_token: params.payment_token,
                price_per_unit: params.price_per_unit,
                start_time,
                end_time,
                order_status: OrderStatus::Created,
                fulfiller: Option::None,
            };

            self.orders.write(order_hash, order_details);

            self.emit(Event::OrderCreated(OrderCreated {
                order_hash,
                offerer,
                nft_contract: params.nft_contract,
                token_id: params.token_id,
                amount: params.amount,
            }));
        }

        /// Fulfills a registered order.
        ///
        /// Validates the buyer's SNIP-12 signature, order timing, and executes:
        ///   1. ERC-1155 safe_transfer_from (seller → buyer)
        ///   2. ERC-2981 royalty payment (buyer → royalty_receiver, if applicable)
        ///   3. Remaining payment (buyer → seller)
        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            let fulfillment_intent = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment_intent.order_hash;

            // Single storage read; reused for the rest of this function
            let mut order_details = self._assert_order_status(order_hash, OrderStatus::Created);

            let fulfiller = fulfillment_intent.fulfiller;

            // Caller must be the fulfiller — prevents front-running via tx replay
            assert(get_caller_address() == fulfiller, errors::CALLER_NOT_FULFILLER);

            let fulfillment_hash = fulfillment_intent.get_message_hash(fulfiller);
            self._validate_hash_signature(fulfillment_hash, fulfiller, signature);

            self._validate_active_order(order_details.start_time, order_details.end_time);

            self.nonces.use_checked_nonce(fulfiller, fulfillment_intent.nonce);

            // CEI: mark filled before external calls so a re-entrant ERC-1155
            // onReceived callback cannot re-enter fulfill_order
            order_details.order_status = OrderStatus::Filled;
            order_details.fulfiller = Option::Some(fulfiller);
            self.orders.write(order_hash, order_details);

            // Execute transfers (Interaction — after state committed)
            let (royalty_receiver, royalty_amount) = self
                ._execute_transfers(order_details, fulfiller);

            self.emit(Event::OrderFulfilled(OrderFulfilled {
                order_hash,
                offerer: order_details.offerer,
                fulfiller,
                royalty_receiver,
                royalty_amount,
            }));
        }

        /// Cancels a registered order.
        ///
        /// Only the original offerer can cancel. Validates the offerer's SNIP-12 signature.
        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancelation_intent = cancel_request.cancelation;
            let signature = cancel_request.signature;

            let offerer = cancelation_intent.offerer;
            let order_hash = cancelation_intent.order_hash;

            let mut order_details = self._assert_order_status(order_hash, OrderStatus::Created);

            // Verify the cancellation signer is the order's offerer
            assert(offerer == order_details.offerer, errors::CALLER_NOT_OFFERER);

            let cancelation_hash = cancelation_intent.get_message_hash(offerer);
            self._validate_hash_signature(cancelation_hash, offerer, signature);

            order_details.order_status = OrderStatus::Cancelled;
            self.nonces.use_checked_nonce(offerer, cancelation_intent.nonce);
            self.orders.write(order_hash, order_details);

            self.emit(Event::OrderCancelled(OrderCancelled { order_hash, offerer }));
        }

        fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails {
            self.orders.read(order_hash)
        }

        fn get_order_hash(
            self: @ContractState, parameters: OrderParameters, signer: ContractAddress,
        ) -> felt252 {
            parameters.get_message_hash(signer)
        }

        fn get_native_token(self: @ContractState) -> ContractAddress {
            self.native_token_address.read()
        }
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Validates that the current block is at or before start_time (order not yet active).
        /// Used at registration — ensures the order window is still in the future.
        fn _validate_future_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert(now <= start_time, errors::ORDER_NOT_YET_VALID);
            if end_time != 0 {
                assert(now < end_time, errors::ORDER_EXPIRED);
            }
        }

        /// Validates that the current block is within the order's active window.
        /// Used at fulfillment.
        fn _validate_active_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert(now >= start_time, errors::ORDER_NOT_YET_VALID);
            if end_time != 0 {
                assert(now < end_time, errors::ORDER_EXPIRED);
            }
        }

        /// Reads the order and asserts its status matches `expected`.
        /// Returns the order so callers avoid a second storage read.
        fn _assert_order_status(
            self: @ContractState, order_hash: felt252, expected: OrderStatus,
        ) -> OrderDetails {
            let order_details = self.orders.read(order_hash);
            let actual = order_details.order_status;
            assert(
                actual == expected,
                match actual {
                    OrderStatus::None => errors::ORDER_NOT_FOUND,
                    OrderStatus::Created => errors::ORDER_ALREADY_CREATED,
                    OrderStatus::Filled => errors::ORDER_ALREADY_FILLED,
                    OrderStatus::Cancelled => errors::ORDER_CANCELLED,
                },
            );
            order_details
        }

        /// Verifies a SNIP-12 signature using the signer's SRC-6 account.
        fn _validate_hash_signature(
            self: @ContractState,
            hash: felt252,
            signer: ContractAddress,
            signature: Array<felt252>,
        ) {
            let result = ISRC6Dispatcher { contract_address: signer }
                .is_valid_signature(hash, signature);
            assert(
                result == starknet::VALIDATED || result == 1,
                errors::INVALID_SIGNATURE,
            );
        }

        /// Executes the three-step ERC-1155 trade:
        ///   1. Transfer tokens from seller to buyer.
        ///   2. Pay ERC-2981 royalty (if applicable) from buyer to royalty_receiver.
        ///   3. Pay remaining price from buyer to seller.
        ///
        /// Returns (royalty_receiver, royalty_amount) for event emission.
        fn _execute_transfers(
            ref self: ContractState,
            order: OrderDetails,
            fulfiller: ContractAddress,
        ) -> (ContractAddress, u256) {
            let offerer = order.offerer;
            let token_id = felt_to_u256(order.token_id);
            let amount = felt_to_u256(order.amount);
            let price_per_unit = felt_to_u256(order.price_per_unit);
            let total_price = price_per_unit * amount;

            // Step 1: Transfer ERC-1155 tokens from seller to buyer.
            // Seller must have called setApprovalForAll(this_contract, true) on the ERC-1155.
            IERC1155Dispatcher { contract_address: order.nft_contract }
                .safe_transfer_from(offerer, fulfiller, token_id, amount, array![].span());

            // Resolve the payment token (zero address = use STRK).
            let payment_token = if order.payment_token.is_zero() {
                self.native_token_address.read()
            } else {
                order.payment_token
            };
            let erc20 = IERC20Dispatcher { contract_address: payment_token };

            // Step 2: Query ERC-2981 and pay royalty from buyer.
            let (royalty_receiver, royalty_amount) = self
                ._get_royalty(order.nft_contract, token_id, total_price);

            if royalty_amount > 0 {
                assert(royalty_amount <= total_price, errors::ROYALTY_EXCEEDS_PRICE);
                let success = erc20.transfer_from(fulfiller, royalty_receiver, royalty_amount);
                assert(success, errors::ROYALTY_TRANSFER_FAILED);
            }

            // Step 3: Pay seller the remainder.
            let seller_amount = total_price - royalty_amount;
            if seller_amount > 0 {
                let success = erc20.transfer_from(fulfiller, offerer, seller_amount);
                assert(success, errors::TRANSFER_FAILED);
            }

            (royalty_receiver, royalty_amount)
        }

        /// Queries ERC-2981 royalty from the NFT contract via SRC5 capability check.
        ///
        /// Returns (zero_address, 0) if:
        ///   - The NFT contract does not advertise IERC2981 via SRC5.
        ///   - The royalty receiver is the zero address.
        ///   - The royalty amount is zero.
        fn _get_royalty(
            self: @ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            sale_price: u256,
        ) -> (ContractAddress, u256) {
            let zero: ContractAddress = 0.try_into().unwrap();

            // Check SRC5 support before calling royalty_info to avoid panicking on
            // ERC-1155 contracts that don't implement ERC-2981.
            let supports = ISRC5QueryDispatcher { contract_address: nft_contract }
                .supports_interface(IERC2981_ID);

            if !supports {
                return (zero, 0);
            }

            let (receiver, royalty_amount) = IERC2981Dispatcher { contract_address: nft_contract }
                .royalty_info(token_id, sale_price);

            if receiver.is_zero() || royalty_amount == 0 {
                return (zero, 0);
            }

            (receiver, royalty_amount)
        }
    }
}
