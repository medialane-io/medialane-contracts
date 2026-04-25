// DESIGN: Medialane1155 is a dedicated marketplace for ERC-1155 IP assets.
//
// Order lifecycle: None → Created → Filled | Cancelled
//
// Key differences from the ERC-721 Medialane Protocol:
// - Orders are always ERC-1155 offer (token_id + amount) × STRK/ERC-20 consideration.
// - Price is price_per_unit × quantity (supports multi-unit / partial fills).
// - ERC-2981 royalties are automatically distributed at fulfillment:
//     buyer's payment is split → royalty_receiver (royalty) + offerer (remainder).
// - Same SNIP-12 signature scheme, nonce consumption, and CEI pattern.
//
// Immutable — no owner, no admin role, no upgrade function.
//
// Compatible with IP-Programmable-ERC1155-Collections (deployed via IPCollectionFactory)
// which implements both ERC-1155 and ERC-2981.
//
// Note on royalty compatibility: _get_royalty uses a low-level syscall to probe
// supports_interface so that ERC-1155 contracts without SRC5 degrade gracefully
// (royalties skipped) rather than causing fulfill_order to revert.

#[starknet::contract]
pub mod Medialane1155 {
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_utils::cryptography::nonces::NoncesComponent;
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use core::num::traits::{CheckedMul, Zero};
    use crate::core::interface::IMedialane1155;
    use crate::core::types::*;
    use crate::core::utils::*;

    // -----------------------------------------------------------------------
    // Inline ERC-2981 return type (ContractAddress, u256) — decoded manually
    // from the raw syscall span to avoid a hard dependency on a specific OZ path.
    // -----------------------------------------------------------------------

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    #[storage]
    struct Storage {
        /// Order registry: order_hash → OrderDetails.
        orders: Map<felt252, OrderDetails>,
        /// STRK token address — used when payment_token == zero.
        /// Immutable after construction — set once, never changed (no admin key).
        native_token_address: ContractAddress,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
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
    }

    use crate::core::events::*;

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

    #[constructor]
    fn constructor(ref self: ContractState, native_token_address: ContractAddress) {
        assert!(!native_token_address.is_zero(), "Native token cannot be zero");
        self.native_token_address.write(native_token_address);
    }

    // -----------------------------------------------------------------------
    // IMedialane1155
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl Medialane1155Impl of IMedialane1155<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let signature = order.signature;
            let offerer = params.offerer;

            assert!(!offerer.is_zero(), "Offerer cannot be zero");
            assert!(!params.nft_contract.is_zero(), "NFT contract cannot be zero");
            assert!(params.amount != 0, "Amount must be nonzero");
            assert!(params.price_per_unit != 0, "Price must be nonzero");

            let order_hash = params.get_message_hash(offerer);

            // Cheap state check before the expensive SRC-6 external call.
            self._assert_order_status_none(order_hash);

            let start_time = felt_to_u64(params.start_time);
            let end_time = felt_to_u64(params.end_time);
            self._validate_registration(start_time, end_time);

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
                remaining_amount: params.amount,
            };

            self.orders.write(order_hash, order_details);

            self.emit(Event::OrderCreated(OrderCreated {
                order_hash,
                offerer,
                nft_contract: params.nft_contract,
                token_id: params.token_id,
                amount: params.amount,
                price_per_unit: params.price_per_unit,
                payment_token: params.payment_token,
            }));
        }

        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            let fulfillment_intent = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment_intent.order_hash;

            // Single storage read; reused for the rest of this function.
            let mut order_details = self._assert_order_status_created(order_hash);

            let fulfiller = fulfillment_intent.fulfiller;
            let quantity = fulfillment_intent.quantity;

            // Caller must be the fulfiller — prevents front-running via tx replay.
            assert!(get_caller_address() == fulfiller, "Caller not fulfiller");
            // Offerer cannot fill their own order.
            assert!(fulfiller != order_details.offerer, "Cannot fill own order");
            assert!(quantity != 0, "Quantity must be nonzero");

            // Use u256 for the comparison to avoid felt252 ordering pitfalls
            // (felt252 ordering is field-element order, not natural number order).
            let quantity_u256 = felt_to_u256(quantity);
            let remaining_u256 = felt_to_u256(order_details.remaining_amount);
            assert!(quantity_u256 <= remaining_u256, "Insufficient remaining units");

            let fulfillment_hash = fulfillment_intent.get_message_hash(fulfiller);
            self._validate_hash_signature(fulfillment_hash, fulfiller, signature);

            self._validate_active_order(order_details.start_time, order_details.end_time);

            self.nonces.use_checked_nonce(fulfiller, fulfillment_intent.nonce);

            // Compute new remaining; transition to Filled only when all units are consumed.
            let new_remaining_u256 = remaining_u256 - quantity_u256;
            let new_remaining: felt252 = new_remaining_u256.try_into().unwrap();
            let new_status = if new_remaining == 0 {
                OrderStatus::Filled
            } else {
                OrderStatus::Created
            };

            // CEI: commit state before external calls to block re-entrant fill attempts
            // on the same order. The ERC-1155 safe_transfer_from triggers onERC1155Received
            // on the fulfiller — at that point this order is already marked Filled/decremented,
            // so any re-entrant attempt on this order will fail the status check.
            order_details.remaining_amount = new_remaining;
            order_details.order_status = new_status;
            self.orders.write(order_hash, order_details);

            let (royalty_receiver, royalty_amount) = self
                ._execute_transfers(order_details, fulfiller, quantity);

            self.emit(Event::OrderFulfilled(OrderFulfilled {
                order_hash,
                offerer: order_details.offerer,
                fulfiller,
                quantity,
                remaining_amount: new_remaining,
                royalty_receiver,
                royalty_amount,
            }));
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
        /// Validates an order at registration time.
        /// Rejects if end_time has already passed, or if start_time >= end_time
        /// (which would create a permanently unfulfillable order).
        /// start_time is not required to be in the future — the tx may land later
        /// than the block the offerer intended.
        fn _validate_registration(self: @ContractState, start_time: u64, end_time: u64) {
            if end_time != 0 {
                assert!(get_block_timestamp() < end_time, "Order expired");
                assert!(start_time < end_time, "Start time must precede end time");
            }
        }

        /// Validates that the current block is within the order's active window.
        fn _validate_active_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert!(now >= start_time, "Order not yet valid");
            if end_time != 0 {
                assert!(now < end_time, "Order expired");
            }
        }

        /// Reads the order and asserts it has never been registered (status == None).
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
            hash: felt252,
            signer: ContractAddress,
            signature: Array<felt252>,
        ) {
            let result = ISRC6Dispatcher { contract_address: signer }
                .is_valid_signature(hash, signature);
            assert!(
                result == starknet::VALIDATED || result == 1,
                "Invalid signature",
            );
        }

        /// Executes the three-step ERC-1155 trade for `quantity` units:
        ///   1. Transfer `quantity` tokens from seller to buyer.
        ///   2. Pay ERC-2981 royalty on `price_per_unit × quantity` (if supported).
        ///   3. Pay seller the remainder.
        fn _execute_transfers(
            ref self: ContractState,
            order: OrderDetails,
            fulfiller: ContractAddress,
            quantity: felt252,
        ) -> (ContractAddress, u256) {
            let offerer = order.offerer;
            let token_id = felt_to_u256(order.token_id);
            let amount = felt_to_u256(quantity);
            let price_per_unit = felt_to_u256(order.price_per_unit);
            let total_price: u256 = match price_per_unit.checked_mul(amount) {
                Option::Some(v) => v,
                Option::None => panic!("Price overflow"),
            };

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
                assert!(royalty_amount <= total_price, "Royalty exceeds sale price");
                let success = erc20.transfer_from(fulfiller, royalty_receiver, royalty_amount);
                assert!(success, "Royalty transfer failed");
            }

            // Step 3: Pay seller the remainder.
            let seller_amount = total_price - royalty_amount;
            if seller_amount > 0 {
                let success = erc20.transfer_from(fulfiller, offerer, seller_amount);
                assert!(success, "Transfer failed");
            }

            (royalty_receiver, royalty_amount)
        }

        /// Queries ERC-2981 royalty using low-level syscalls so that ERC-1155 contracts
        /// without SRC5 gracefully return (zero, 0) instead of reverting.
        ///
        /// Returns (zero_address, 0) when:
        ///   - The NFT contract does not implement SRC5 (supports_interface entrypoint absent).
        ///   - The contract does not advertise IERC2981 via SRC5.
        ///   - The royalty receiver is the zero address or royalty amount is zero.
        fn _get_royalty(
            self: @ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            sale_price: u256,
        ) -> (ContractAddress, u256) {
            let zero: ContractAddress = 0.try_into().unwrap();

            // Probe supports_interface via raw syscall — non-SRC5 contracts return false
            // instead of reverting the entire transaction.
            let supports_calldata: Array<felt252> = array![IERC2981_ID];
            let supports = match starknet::syscalls::call_contract_syscall(
                nft_contract,
                selector!("supports_interface"),
                supports_calldata.span(),
            ) {
                Result::Ok(ret) => ret.len() > 0 && *ret.at(0) != 0,
                Result::Err(_) => false,
            };

            if !supports {
                return (zero, 0);
            }

            // Call royalty_info(token_id: u256, sale_price: u256).
            // u256 serialises as two felts: low then high.
            let royalty_calldata: Array<felt252> = array![
                token_id.low.into(),
                token_id.high.into(),
                sale_price.low.into(),
                sale_price.high.into(),
            ];

            // Returns (ContractAddress, u256) = 3 felts: addr, low, high.
            match starknet::syscalls::call_contract_syscall(
                nft_contract,
                selector!("royalty_info"),
                royalty_calldata.span(),
            ) {
                Result::Ok(ret) => {
                    if ret.len() < 3 {
                        return (zero, 0);
                    }
                    let receiver: Option<ContractAddress> = (*ret.at(0)).try_into();
                    match receiver {
                        Option::None => (zero, 0),
                        Option::Some(addr) => {
                            if addr.is_zero() {
                                return (zero, 0);
                            }
                            let low: Option<u128> = (*ret.at(1)).try_into();
                            let high: Option<u128> = (*ret.at(2)).try_into();
                            match (low, high) {
                                (Option::Some(l), Option::Some(h)) => {
                                    let royalty = u256 { low: l, high: h };
                                    if royalty == 0 {
                                        (zero, 0)
                                    } else {
                                        (addr, royalty)
                                    }
                                },
                                _ => (zero, 0),
                            }
                        },
                    }
                },
                Result::Err(_) => (zero, 0),
            }
        }
    }
}
