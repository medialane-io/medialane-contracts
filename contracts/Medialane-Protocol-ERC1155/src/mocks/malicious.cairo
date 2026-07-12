use starknet::ContractAddress;

/// A payment token whose `transfer_from` reenters the marketplace mid-settlement.
/// Used to prove the reentrancy guard blocks a malicious consideration token from
/// re-entering any lifecycle entrypoint (`fulfill_order` or `cancel_order`).
#[starknet::interface]
pub trait IMaliciousERC20<TContractState> {
    /// Arm a reentrant `fulfill_order(order_hash, quantity)` during settlement.
    fn set_attack(
        ref self: TContractState,
        marketplace: ContractAddress,
        order_hash: felt252,
        quantity: felt252,
    );
    /// Arm a reentrant `cancel_order` during settlement. The cancellation carries a
    /// dummy signature — the guard must fire before signature validation.
    fn set_cancel_attack(
        ref self: TContractState, marketplace: ContractAddress, order_hash: felt252,
    );
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
    use crate::core::interface::{IMedialane1155Dispatcher, IMedialane1155DispatcherTrait};
    use crate::core::types::{CancelRequest, OrderCancellation};
    use super::IMaliciousERC20;

    // Attack modes.
    const MODE_FULFILL: felt252 = 0;
    const MODE_CANCEL: felt252 = 1;

    #[storage]
    struct Storage {
        marketplace: ContractAddress,
        order_hash: felt252,
        quantity: felt252,
        mode: felt252,
    }

    #[abi(embed_v0)]
    impl Impl of IMaliciousERC20<ContractState> {
        fn set_attack(
            ref self: ContractState,
            marketplace: ContractAddress,
            order_hash: felt252,
            quantity: felt252,
        ) {
            self.marketplace.write(marketplace);
            self.order_hash.write(order_hash);
            self.quantity.write(quantity);
            self.mode.write(MODE_FULFILL);
        }

        fn set_cancel_attack(
            ref self: ContractState, marketplace: ContractAddress, order_hash: felt252,
        ) {
            self.marketplace.write(marketplace);
            self.order_hash.write(order_hash);
            self.mode.write(MODE_CANCEL);
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            // Attempt to reenter the marketplace while it is still settling.
            let market = IMedialane1155Dispatcher { contract_address: self.marketplace.read() };
            if self.mode.read() == MODE_CANCEL {
                let request = CancelRequest {
                    cancelation: OrderCancellation {
                        order_hash: self.order_hash.read(), offerer: 0.try_into().unwrap(),
                    },
                    signature: array![],
                };
                market.cancel_order(request);
            } else {
                market.fulfill_order(self.order_hash.read(), self.quantity.read());
            }
            true
        }
    }
}
