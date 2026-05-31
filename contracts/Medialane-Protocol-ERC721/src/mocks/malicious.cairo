use starknet::ContractAddress;

/// A payment token whose `transfer_from` reenters the marketplace mid-settlement.
/// Used to prove the reentrancy guard blocks a malicious consideration token.
#[starknet::interface]
pub trait IMaliciousERC20<TContractState> {
    fn set_attack(ref self: TContractState, marketplace: ContractAddress, order_hash: felt252);
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    ) -> bool;
}

#[starknet::contract]
pub mod MaliciousERC20 {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::ContractAddress;
    use crate::core::interface::{IMedialaneDispatcher, IMedialaneDispatcherTrait};
    use super::IMaliciousERC20;

    #[storage]
    struct Storage {
        marketplace: ContractAddress,
        order_hash: felt252,
    }

    #[abi(embed_v0)]
    impl Impl of IMaliciousERC20<ContractState> {
        fn set_attack(
            ref self: ContractState, marketplace: ContractAddress, order_hash: felt252,
        ) {
            self.marketplace.write(marketplace);
            self.order_hash.write(order_hash);
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            IMedialaneDispatcher { contract_address: self.marketplace.read() }
                .fulfill_order(self.order_hash.read());
            true
        }
    }
}
