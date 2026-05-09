#[starknet::contract]
pub mod Medialane1155V2 {
    use core::num::traits::{CheckedMul, Zero};
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
    use crate::core::events::*;
    use crate::core::interface::IMedialane1155V2;
    use crate::core::types::*;
    use crate::core::utils::*;

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        orders: Map<felt252, OrderDetails>,
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

    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Medialane'
        }
        fn version() -> felt252 {
            2
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, native_token_address: ContractAddress) {
        assert!(!native_token_address.is_zero(), "Native token cannot be zero");
        self.native_token_address.write(native_token_address);
    }

    #[abi(embed_v0)]
    impl Medialane1155V2Impl of IMedialane1155V2<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let signature = order.signature;
            let offerer = params.offerer;

            assert!(!offerer.is_zero(), "Offerer cannot be zero");

            let offer_type: Option<ItemType> = params.offer.item_type.try_into();
            assert!(offer_type.is_some(), "Invalid item type");
            let consideration_type: Option<ItemType> = params.consideration.item_type.try_into();
            assert!(consideration_type.is_some(), "Invalid item type");

            assert!(params.offer.start_amount == params.offer.end_amount, "End amount must equal start");
            assert!(
                params.consideration.start_amount == params.consideration.end_amount,
                "End amount must equal start",
            );

            let order_hash = params.get_message_hash(offerer);
            self._assert_order_status_none(order_hash);

            let start_time = felt_to_u64(params.start_time);
            let end_time = felt_to_u64(params.end_time);
            self._validate_registration_window(start_time, end_time);
            let unwrapped_offer_type = offer_type.unwrap();
            let unwrapped_consideration_type = consideration_type.unwrap();
            self._validate_supported_shape(
                params.offer,
                unwrapped_offer_type,
                params.consideration,
                unwrapped_consideration_type,
            );
            let erc1155_amount = self._erc1155_amount(params.offer, unwrapped_offer_type, params.consideration);

            self._validate_hash_signature(order_hash, offerer, signature);
            self.nonces.use_checked_nonce(offerer, params.nonce);

            let order_details = OrderDetails {
                offerer,
                offer: params.offer,
                consideration: params.consideration,
                start_time,
                end_time,
                order_status: OrderStatus::Created,
                total_amount: erc1155_amount,
                remaining_amount: erc1155_amount,
            };

            self.orders.write(order_hash, order_details);
            self.emit(Event::OrderCreated(OrderCreated { order_hash, offerer }));
        }

        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            let fulfillment = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment.order_hash;

            let mut order_details = self._assert_order_status_created(order_hash);
            let fulfiller = fulfillment.fulfiller;
            let quantity = fulfillment.quantity;

            assert!(!fulfiller.is_zero(), "Fulfiller cannot be zero");
            assert!(get_caller_address() == fulfiller, "Caller not fulfiller");
            assert!(fulfiller != order_details.offerer, "Cannot fill own order");
            assert!(quantity != 0, "Quantity must be nonzero");

            let quantity_u256 = felt_to_u256(quantity);
            let remaining_u256 = felt_to_u256(order_details.remaining_amount);
            assert!(quantity_u256 <= remaining_u256, "Insufficient remaining units");

            let fulfillment_hash = fulfillment.get_message_hash(fulfiller);
            self._validate_hash_signature(fulfillment_hash, fulfiller, signature);
            self._validate_active_order(order_details.start_time, order_details.end_time);
            self.nonces.use_checked_nonce(fulfiller, fulfillment.nonce);

            let new_remaining_u256 = remaining_u256 - quantity_u256;
            let new_remaining: felt252 = new_remaining_u256.try_into().unwrap();
            order_details.remaining_amount = new_remaining;
            order_details.order_status = if new_remaining == 0 {
                OrderStatus::Filled
            } else {
                OrderStatus::Created
            };

            self.orders.write(order_hash, order_details);

            let (sale_amount, royalty_receiver, royalty_amount) = self
                ._execute_transfers(order_details, fulfiller, quantity);

            self.emit(Event::OrderFulfilled(OrderFulfilled {
                order_hash,
                offerer: order_details.offerer,
                fulfiller,
                quantity,
                remaining_amount: new_remaining,
                sale_amount,
                royalty_receiver,
                royalty_amount,
            }));
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancellation = cancel_request.cancelation;
            let signature = cancel_request.signature;
            let offerer = cancellation.offerer;
            let order_hash = cancellation.order_hash;

            let mut order_details = self._assert_order_status_created(order_hash);
            assert!(offerer == order_details.offerer, "Caller not offerer");

            let cancellation_hash = cancellation.get_message_hash(offerer);
            self._validate_hash_signature(cancellation_hash, offerer, signature);

            order_details.order_status = OrderStatus::Cancelled;
            self.nonces.use_checked_nonce(offerer, cancellation.nonce);
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

        fn get_native_token_address(self: @ContractState) -> ContractAddress {
            self.native_token_address.read()
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _validate_registration_window(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            if end_time != 0 {
                assert!(start_time < end_time, "Invalid time window");
                assert!(now < end_time, "Order expired");
            }
        }

        fn _validate_active_order(self: @ContractState, start_time: u64, end_time: u64) {
            let now = get_block_timestamp();
            assert!(now >= start_time, "Order not yet valid");
            if end_time != 0 {
                assert!(now < end_time, "Order expired");
            }
        }

        fn _validate_supported_shape(
            self: @ContractState,
            offer: OfferItem,
            offer_type: ItemType,
            consideration: ConsiderationItem,
            consideration_type: ItemType,
        ) {
            match offer_type {
                ItemType::ERC1155 => {
                    self._validate_erc1155_item(offer);
                    self._validate_payment_consideration(consideration, consideration_type);
                },
                ItemType::NATIVE => {
                    self._validate_payment_item(offer, offer_type);
                    self._validate_erc1155_consideration(consideration, consideration_type);
                },
                ItemType::ERC20 => {
                    self._validate_payment_item(offer, offer_type);
                    self._validate_erc1155_consideration(consideration, consideration_type);
                },
                _ => panic!("Unsupported offer item"),
            }
        }

        fn _validate_erc1155_item(self: @ContractState, item: OfferItem) {
            assert!(!item.token.is_zero(), "Token address cannot be zero");
            assert!(item.start_amount != 0, "Invalid amount");
        }

        fn _validate_erc1155_consideration(
            self: @ContractState,
            consideration: ConsiderationItem,
            consideration_type: ItemType,
        ) {
            match consideration_type {
                ItemType::ERC1155 => {},
                _ => panic!("Unsupported consideration item"),
            }
            assert!(!consideration.token.is_zero(), "Token address cannot be zero");
            assert!(consideration.start_amount != 0, "Invalid amount");
            assert!(!consideration.recipient.is_zero(), "Recipient cannot be zero");
        }

        fn _validate_payment_item(
            self: @ContractState,
            item: OfferItem,
            item_type: ItemType,
        ) {
            match item_type {
                ItemType::NATIVE => {
                    assert!(item.token.is_zero(), "Token address must be zero");
                    assert!(item.identifier_or_criteria == 0, "Invalid identifier");
                },
                ItemType::ERC20 => {
                    assert!(!item.token.is_zero(), "Token address cannot be zero");
                    assert!(item.identifier_or_criteria == 0, "Invalid identifier");
                },
                _ => panic!("Unsupported offer item"),
            }
            assert!(item.start_amount != 0, "Invalid amount");
        }

        fn _validate_payment_consideration(
            self: @ContractState,
            consideration: ConsiderationItem,
            consideration_type: ItemType,
        ) {
            match consideration_type {
                ItemType::NATIVE => {
                    assert!(consideration.token.is_zero(), "Token address must be zero");
                    assert!(consideration.identifier_or_criteria == 0, "Invalid identifier");
                },
                ItemType::ERC20 => {
                    assert!(!consideration.token.is_zero(), "Token address cannot be zero");
                    assert!(consideration.identifier_or_criteria == 0, "Invalid identifier");
                },
                _ => panic!("Unsupported consideration item"),
            }
            assert!(consideration.start_amount != 0, "Invalid amount");
            assert!(!consideration.recipient.is_zero(), "Recipient cannot be zero");
        }

        fn _erc1155_amount(
            self: @ContractState,
            offer: OfferItem,
            offer_type: ItemType,
            consideration: ConsiderationItem,
        ) -> felt252 {
            match offer_type {
                ItemType::ERC1155 => offer.start_amount,
                _ => consideration.start_amount,
            }
        }

        fn _payment_token(
            self: @ContractState,
            item_type: ItemType,
            token: ContractAddress,
        ) -> ContractAddress {
            match item_type {
                ItemType::NATIVE => self.native_token_address.read(),
                ItemType::ERC20 => token,
                _ => panic!("Unsupported payment item"),
            }
        }

        fn _payment_item_type(self: @ContractState, item_type: felt252) -> ItemType {
            let parsed: Option<ItemType> = item_type.try_into();
            assert!(parsed.is_some(), "Invalid item type");
            match parsed.unwrap() {
                ItemType::NATIVE => ItemType::NATIVE,
                ItemType::ERC20 => ItemType::ERC20,
                _ => panic!("Unsupported payment item"),
            }
        }

        fn _pay_with_royalty(
            self: @ContractState,
            payment_item_type: ItemType,
            payment_token: ContractAddress,
            payer: ContractAddress,
            seller_recipient: ContractAddress,
            nft_contract: ContractAddress,
            token_id: u256,
            sale_amount: u256,
        ) -> (ContractAddress, u256) {
            let erc20 = IERC20Dispatcher {
                contract_address: self._payment_token(payment_item_type, payment_token),
            };

            let (royalty_receiver, royalty_amount) = self
                ._get_royalty(nft_contract, token_id, sale_amount);

            if royalty_amount > 0 {
                assert!(royalty_amount <= sale_amount, "Royalty exceeds sale price");
                let success = erc20.transfer_from(payer, royalty_receiver, royalty_amount);
                assert!(success, "Royalty transfer failed");
            }

            let seller_amount = sale_amount - royalty_amount;
            if seller_amount > 0 {
                let success = erc20.transfer_from(payer, seller_recipient, seller_amount);
                assert!(success, "Transfer failed");
            }

            (royalty_receiver, royalty_amount)
        }

        fn _execute_listing_transfers(
            ref self: ContractState,
            order: OrderDetails,
            fulfiller: ContractAddress,
            quantity: felt252,
        ) -> (u256, ContractAddress, u256) {
            let offerer = order.offerer;
            let token_id = felt_to_u256(order.offer.identifier_or_criteria);
            let amount = felt_to_u256(quantity);
            let price_per_unit = felt_to_u256(order.consideration.start_amount);
            let sale_amount: u256 = match price_per_unit.checked_mul(amount) {
                Option::Some(v) => v,
                Option::None => panic!("Price overflow"),
            };

            IERC1155Dispatcher { contract_address: order.offer.token }
                .safe_transfer_from(offerer, fulfiller, token_id, amount, array![].span());

            let (royalty_receiver, royalty_amount) = self._pay_with_royalty(
                self._payment_item_type(order.consideration.item_type),
                order.consideration.token,
                fulfiller,
                order.consideration.recipient,
                order.offer.token,
                token_id,
                sale_amount,
            );

            (sale_amount, royalty_receiver, royalty_amount)
        }

        fn _execute_bid_transfers(
            ref self: ContractState,
            order: OrderDetails,
            fulfiller: ContractAddress,
            quantity: felt252,
        ) -> (u256, ContractAddress, u256) {
            let token_id = felt_to_u256(order.consideration.identifier_or_criteria);
            let amount = felt_to_u256(quantity);
            let price_per_unit = felt_to_u256(order.offer.start_amount);
            let sale_amount: u256 = match price_per_unit.checked_mul(amount) {
                Option::Some(v) => v,
                Option::None => panic!("Price overflow"),
            };

            let (royalty_receiver, royalty_amount) = self._pay_with_royalty(
                self._payment_item_type(order.offer.item_type),
                order.offer.token,
                order.offerer,
                fulfiller,
                order.consideration.token,
                token_id,
                sale_amount,
            );

            IERC1155Dispatcher { contract_address: order.consideration.token }
                .safe_transfer_from(fulfiller, order.consideration.recipient, token_id, amount, array![].span());

            (sale_amount, royalty_receiver, royalty_amount)
        }

        fn _assert_order_status_none(self: @ContractState, order_hash: felt252) {
            let order_details = self.orders.read(order_hash);
            match order_details.order_status {
                OrderStatus::None => {},
                OrderStatus::Created => panic!("Order already created"),
                OrderStatus::Filled => panic!("Order already filled"),
                OrderStatus::Cancelled => panic!("Order cancelled"),
            }
        }

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

        fn _validate_hash_signature(
            self: @ContractState,
            hash: felt252,
            signer: ContractAddress,
            signature: Array<felt252>,
        ) {
            let result = ISRC6Dispatcher { contract_address: signer }.is_valid_signature(hash, signature);
            assert!(result == starknet::VALIDATED || result == 1, "Invalid signature");
        }

        fn _execute_transfers(
            ref self: ContractState,
            order: OrderDetails,
            fulfiller: ContractAddress,
            quantity: felt252,
        ) -> (u256, ContractAddress, u256) {
            let offer_type: Option<ItemType> = order.offer.item_type.try_into();
            assert!(offer_type.is_some(), "Invalid item type");

            match offer_type.unwrap() {
                ItemType::ERC1155 => self._execute_listing_transfers(order, fulfiller, quantity),
                ItemType::ERC20 | ItemType::NATIVE => self._execute_bid_transfers(order, fulfiller, quantity),
                _ => panic!("Unsupported offer item"),
            }
        }

        fn _get_royalty(
            self: @ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            sale_price: u256,
        ) -> (ContractAddress, u256) {
            let zero: ContractAddress = 0.try_into().unwrap();

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

            let royalty_calldata: Array<felt252> = array![
                token_id.low.into(),
                token_id.high.into(),
                sale_price.low.into(),
                sale_price.high.into(),
            ];

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
