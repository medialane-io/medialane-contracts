#[starknet::contract]
pub mod Medialane1155 {
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use core::num::traits::Zero;
    use crate::core::events::*;
    use crate::core::interface::IMedialane1155;
    use crate::core::types::*;

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
            panic!("not implemented");
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
}
