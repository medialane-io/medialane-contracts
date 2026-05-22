//! Immutable ERC-721 marketplace.
//!
//! Zero-argument constructor, no admin, no upgrade, no fee — a neutral
//! settlement primitive. Orders are SNIP-12 signed off-chain and registered
//! on-chain; settlement is atomic, fee-free, honoring ERC-2981 royalty when
//! the traded collection declares it.

use crate::types::{
    CancelRequest, FulfillmentRequest, Order, OrderDetails, OrderParameters,
};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMedialane721<TContractState> {
    fn register_order(ref self: TContractState, order: Order);
    fn fulfill_order(ref self: TContractState, fulfillment_request: FulfillmentRequest);
    fn cancel_order(ref self: TContractState, cancel_request: CancelRequest);
    fn get_order_details(self: @TContractState, order_hash: felt252) -> OrderDetails;
    fn get_order_hash(
        self: @TContractState, parameters: OrderParameters, signer: ContractAddress,
    ) -> felt252;
}

#[starknet::contract]
pub mod Medialane721 {
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress};
    use crate::types::{
        CancelRequest, FulfillmentRequest, Order, OrderDetails, OrderParameters, OrderStatus,
    };

    #[storage]
    struct Storage {
        /// The on-chain order book — keyed by SNIP-12 order hash.
        orders: Map<felt252, OrderDetails>,
        /// Unordered replay guard for consumed fulfillment + cancellation hashes (F1).
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
            'MedialaneMarketplace'
        }
        fn version() -> felt252 {
            '1'
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState) { // Intentionally zero-argument — no hardcoded addresses, no fee, no admin.
    }

    #[abi(embed_v0)]
    impl Medialane721Impl of super::IMedialane721<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let signature = order.signature;
            let offerer = params.offerer;

            let order_hash = params.get_message_hash(offerer);

            // Replay guard — an order hash can be registered exactly once.
            let existing = self.orders.read(order_hash);
            assert!(existing.order_status == OrderStatus::None, "Order already exists");

            // Verify the offerer's SNIP-12 signature via SRC-6.
            let valid = ISRC6Dispatcher { contract_address: offerer }
                .is_valid_signature(order_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid signature");

            let start_time: u64 = params.start_time.try_into().expect('start_time out of range');
            let end_time: u64 = params.end_time.try_into().expect('end_time out of range');

            let details = OrderDetails {
                offerer,
                offer: params.offer,
                consideration: params.consideration,
                start_time,
                end_time,
                order_status: OrderStatus::Created,
            };
            self.orders.write(order_hash, details);

            self.emit(Event::OrderCreated(OrderCreated { order_hash, offerer }));
        }

        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            panic!("fulfill_order not implemented");
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            panic!("cancel_order not implemented");
        }

        fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails {
            self.orders.read(order_hash)
        }

        fn get_order_hash(
            self: @ContractState, parameters: OrderParameters, signer: ContractAddress,
        ) -> felt252 {
            parameters.get_message_hash(signer)
        }
    }
}
