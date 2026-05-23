//! Immutable ERC-1155 marketplace.
//!
//! Same shape as `Medialane721` — zero-argument constructor, no admin, no
//! upgrade, no fee. Differs in that one `Created` order can be partially filled
//! across many fulfillments until `remaining_amount` hits 0, at which point the
//! status flips to `Filled`. The payment item's `amount` is **per-unit price**;
//! a fulfillment of `quantity` units transfers `unit_price * quantity` of the
//! payment currency.

use crate::types::{
    CancelRequest, FulfillmentRequest1155, Order, OrderDetails1155, OrderParameters,
};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMedialane1155<TContractState> {
    fn register_order(ref self: TContractState, order: Order);
    fn fulfill_order(
        ref self: TContractState, fulfillment_request: FulfillmentRequest1155,
    );
    fn cancel_order(ref self: TContractState, cancel_request: CancelRequest);
    fn get_order_details(self: @TContractState, order_hash: felt252) -> OrderDetails1155;
    fn get_order_hash(
        self: @TContractState, parameters: OrderParameters, signer: ContractAddress,
    ) -> felt252;
}

#[starknet::contract]
pub mod Medialane1155 {
    use core::num::traits::CheckedMul;
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::settlement::{get_royalty, seller_proceeds};
    use crate::types::{
        CancelRequest, FulfillmentRequest1155, ItemType, Order, OrderDetails1155,
        OrderParameters, OrderStatus,
    };

    #[storage]
    struct Storage {
        orders: Map<felt252, OrderDetails1155>,
        /// Unordered replay guard — consumed fulfillment + cancellation hashes.
        consumed_intents: Map<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OrderCreated: OrderCreated,
        OrderFulfilled: OrderFulfilled,
        OrderCancelled: OrderCancelled,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderCreated {
        #[key]
        pub order_hash: felt252,
        #[key]
        pub offerer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderFulfilled {
        #[key]
        pub order_hash: felt252,
        pub offerer: ContractAddress,
        pub fulfiller: ContractAddress,
        pub quantity: u256,
        pub remaining_amount: u256,
        pub sale_amount: u256,
        pub royalty_receiver: ContractAddress,
        pub royalty_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderCancelled {
        #[key]
        pub order_hash: felt252,
        pub offerer: ContractAddress,
    }

    pub impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'MedialaneMarketplace1155'
        }
        fn version() -> felt252 {
            '1'
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // Zero-argument — no hardcoded addresses, no fee, no admin.
    }

    #[abi(embed_v0)]
    impl Medialane1155Impl of super::IMedialane1155<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let signature = order.signature;
            let offerer = params.offerer;

            // F3 — shape validation. The 1155 marketplace supports:
            //   - Listing: offer = ERC-1155, consideration = ERC-20
            //   - Bid:     offer = ERC-20,   consideration = ERC-1155
            let ot: ItemType = params.offer.item_type
                .try_into()
                .expect('Invalid offer item type');
            let ct: ItemType = params.consideration.item_type
                .try_into()
                .expect('Invalid consideration type');
            let is_listing = ot == ItemType::ERC1155 && ct == ItemType::ERC20;
            let is_bid = ot == ItemType::ERC20 && ct == ItemType::ERC1155;
            assert(is_listing || is_bid, 'Unsupported order shape');

            let order_hash = params.get_message_hash(offerer);
            let existing = self.orders.read(order_hash);
            assert!(existing.order_status == OrderStatus::None, "Order already exists");

            let valid = ISRC6Dispatcher { contract_address: offerer }
                .is_valid_signature(order_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid signature");

            let start_time: u64 = params.start_time.try_into().expect('start_time out of range');
            let end_time: u64 = params.end_time.try_into().expect('end_time out of range');

            // The ERC-1155 leg's `amount` is the total number of units this order
            // moves. Partial fills consume from `remaining_amount`.
            let total_amount: u256 = if is_listing {
                params.offer.amount.into()
            } else {
                params.consideration.amount.into()
            };
            assert!(total_amount > 0, "Total amount must be > 0");

            let details = OrderDetails1155 {
                offerer,
                offer: params.offer,
                consideration: params.consideration,
                start_time,
                end_time,
                order_status: OrderStatus::Created,
                total_amount,
                remaining_amount: total_amount,
            };
            self.orders.write(order_hash, details);

            self.emit(Event::OrderCreated(OrderCreated { order_hash, offerer }));
        }

        fn fulfill_order(
            ref self: ContractState, fulfillment_request: FulfillmentRequest1155,
        ) {
            let fulfillment = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment.order_hash;
            let fulfiller = fulfillment.fulfiller;
            let quantity: u256 = fulfillment.quantity.into();

            assert!(get_caller_address() == fulfiller, "Caller is not the fulfiller");
            assert!(quantity > 0, "Quantity must be > 0");

            let mut details = self.orders.read(order_hash);
            assert!(details.order_status == OrderStatus::Created, "Order is not active");
            assert!(fulfiller != details.offerer, "Cannot fill own order");
            assert!(quantity <= details.remaining_amount, "Insufficient remaining units");

            let now = get_block_timestamp();
            assert!(now >= details.start_time, "Order not yet active");
            if details.end_time != 0 {
                assert!(now < details.end_time, "Order has expired");
            }

            let fulfillment_hash = fulfillment.get_message_hash(fulfiller);
            let valid = ISRC6Dispatcher { contract_address: fulfiller }
                .is_valid_signature(fulfillment_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid fulfillment signature");

            assert!(
                !self.consumed_intents.read(fulfillment_hash),
                "Fulfillment already consumed",
            );
            self.consumed_intents.write(fulfillment_hash, true);

            // Resolve direction. `unit_price` on the payment leg × quantity = sale_amount.
            let ot: ItemType = details.offer.item_type
                .try_into()
                .expect('Bad offer item type');
            let cons_type: ItemType = details.consideration.item_type
                .try_into()
                .expect('Bad consideration type');

            let (
                nft_token,
                nft_owner,
                nft_recipient,
                token_id,
                payment_token,
                payment_payer,
                payment_recipient,
                unit_price,
            ) =
                if ot == ItemType::ERC1155 && cons_type == ItemType::ERC20 {
                    // Listing: offerer holds the NFT, fulfiller pays.
                    let token_id: u256 = details.offer.token_id.into();
                    let unit_price: u256 = details.consideration.amount.into();
                    (
                        details.offer.token,
                        details.offerer,
                        fulfiller,
                        token_id,
                        details.consideration.token,
                        fulfiller,
                        details.consideration.recipient,
                        unit_price,
                    )
                } else if ot == ItemType::ERC20 && cons_type == ItemType::ERC1155 {
                    // Bid: offerer pays, fulfiller delivers the NFT to the
                    // consideration recipient (the buyer); fulfiller receives payment.
                    let token_id: u256 = details.consideration.token_id.into();
                    let unit_price: u256 = details.offer.amount.into();
                    (
                        details.consideration.token,
                        fulfiller,
                        details.consideration.recipient,
                        token_id,
                        details.offer.token,
                        details.offerer,
                        fulfiller,
                        unit_price,
                    )
                } else {
                    panic!("Unsupported order shape")
                };

            let sale_amount: u256 = match unit_price.checked_mul(quantity) {
                Option::Some(v) => v,
                Option::None => panic!("Price overflow"),
            };

            // Best-effort ERC-2981 — uncooperative collections fail open to (0, 0).
            let (royalty_receiver, royalty_amount) = get_royalty(
                nft_token, token_id, sale_amount,
            );
            let seller_amount = seller_proceeds(sale_amount, royalty_amount);

            // CEI — update state (remaining + status) BEFORE any external call.
            let new_remaining = details.remaining_amount - quantity;
            details.remaining_amount = new_remaining;
            if new_remaining == 0 {
                details.order_status = OrderStatus::Filled;
            }
            self.orders.write(order_hash, details);

            // F5 — pull the payment leg first, then move the NFT units.
            let payment = IERC20Dispatcher { contract_address: payment_token };
            if royalty_amount > 0 {
                let ok = payment.transfer_from(payment_payer, royalty_receiver, royalty_amount);
                assert!(ok, "Royalty transfer failed");
            }
            if seller_amount > 0 {
                let ok = payment.transfer_from(payment_payer, payment_recipient, seller_amount);
                assert!(ok, "Payment transfer failed");
            }

            IERC1155Dispatcher { contract_address: nft_token }
                .safe_transfer_from(nft_owner, nft_recipient, token_id, quantity, array![].span());

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
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancellation = cancel_request.cancellation;
            let signature = cancel_request.signature;
            let order_hash = cancellation.order_hash;
            let offerer = cancellation.offerer;

            let mut details = self.orders.read(order_hash);
            assert!(details.order_status == OrderStatus::Created, "Order is not active");
            assert!(offerer == details.offerer, "Not the order's offerer");

            let cancellation_hash = cancellation.get_message_hash(offerer);
            let valid = ISRC6Dispatcher { contract_address: offerer }
                .is_valid_signature(cancellation_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid cancellation signature");

            assert!(
                !self.consumed_intents.read(cancellation_hash),
                "Cancellation already consumed",
            );
            self.consumed_intents.write(cancellation_hash, true);

            details.order_status = OrderStatus::Cancelled;
            self.orders.write(order_hash, details);

            self.emit(Event::OrderCancelled(OrderCancelled { order_hash, offerer }));
        }

        fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails1155 {
            self.orders.read(order_hash)
        }

        fn get_order_hash(
            self: @ContractState, parameters: OrderParameters, signer: ContractAddress,
        ) -> felt252 {
            parameters.get_message_hash(signer)
        }
    }
}
