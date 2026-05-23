//! Test-only mock contracts. Compiled only under `#[cfg(test)]` — never shipped.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockERC20<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    ) -> bool;
}

#[starknet::interface]
pub trait IMockERC721<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
    );
}

#[starknet::interface]
pub trait IMockERC1155<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, id: u256, amount: u256);
    fn balance_of(self: @TContractState, account: ContractAddress, id: u256) -> u256;
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        id: u256,
        amount: u256,
        data: Span<felt252>,
    );
}

/// A collection that declares ERC-2981 and reports a flat 5% royalty.
#[starknet::contract]
pub mod MockRoyaltyCollection {
    use starknet::ContractAddress;
    use crate::constants::IERC2981_ID;

    #[storage]
    struct Storage {}

    #[abi(per_item)]
    #[generate_trait]
    pub impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            interface_id == IERC2981_ID
        }

        #[external(v0)]
        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let receiver: ContractAddress = 0x999.try_into().unwrap();
            (receiver, sale_price * 5 / 100)
        }
    }
}

/// An SRC-6 account that accepts every signature as valid. Used to drive the
/// marketplace's signature-verification path without real signing. The `_id`
/// constructor parameter is calldata-only — it makes each deploy address-unique.
#[starknet::contract]
pub mod MockAccount {
    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState, _id: felt252) {}

    #[abi(per_item)]
    #[generate_trait]
    pub impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            starknet::VALIDATED
        }
    }
}

/// A collection that does not declare ERC-2981 — `supports_interface` is false
/// for every id.
#[starknet::contract]
pub mod MockPlainCollection {
    #[storage]
    struct Storage {}

    #[abi(per_item)]
    #[generate_trait]
    pub impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            false
        }
    }
}

/// Minimal ERC-20 mock — moves balances without checking allowances.
#[starknet::contract]
pub mod MockERC20 {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
    }

    #[abi(embed_v0)]
    impl Impl of super::IMockERC20<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            let prev = self.balances.read(to);
            self.balances.write(to, prev + amount);
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let from_bal = self.balances.read(sender);
            assert!(from_bal >= amount, "MockERC20: insufficient balance");
            self.balances.write(sender, from_bal - amount);
            let to_bal = self.balances.read(recipient);
            self.balances.write(recipient, to_bal + amount);
            true
        }
    }
}

/// An ERC-721 mock that also declares ERC-2981 with a flat 5% royalty to a
/// fixed receiver — for exercising the marketplace's royalty path end-to-end.
#[starknet::contract]
pub mod MockRoyaltyNFT {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::ContractAddress;
    use crate::constants::IERC2981_ID;

    #[storage]
    struct Storage {
        owners: Map<u256, ContractAddress>,
    }

    #[abi(embed_v0)]
    impl Erc721 of super::IMockERC721<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self.owners.write(token_id, to);
        }
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.owners.read(token_id)
        }
        fn transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
        ) {
            let current = self.owners.read(token_id);
            assert!(current == from, "MockRoyaltyNFT: not the owner");
            self.owners.write(token_id, to);
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    pub impl Royalty of RoyaltyTrait {
        #[external(v0)]
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            interface_id == IERC2981_ID
        }
        #[external(v0)]
        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let receiver: ContractAddress = 0xcafe.try_into().unwrap();
            (receiver, sale_price * 5 / 100)
        }
    }
}

/// Minimal ERC-1155 mock — moves balances without checking approvals.
#[starknet::contract]
pub mod MockERC1155 {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        balances: Map<(ContractAddress, u256), u256>,
    }

    #[abi(embed_v0)]
    impl Impl of super::IMockERC1155<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, id: u256, amount: u256) {
            let prev = self.balances.read((to, id));
            self.balances.write((to, id), prev + amount);
        }

        fn balance_of(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            self.balances.read((account, id))
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Span<felt252>,
        ) {
            let from_bal = self.balances.read((from, id));
            assert!(from_bal >= amount, "MockERC1155: insufficient balance");
            self.balances.write((from, id), from_bal - amount);
            let to_bal = self.balances.read((to, id));
            self.balances.write((to, id), to_bal + amount);
        }
    }
}

/// Minimal ERC-721 mock — moves ownership without checking approvals.
#[starknet::contract]
pub mod MockERC721 {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        owners: Map<u256, ContractAddress>,
    }

    #[abi(embed_v0)]
    impl Impl of super::IMockERC721<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self.owners.write(token_id, to);
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.owners.read(token_id)
        }

        fn transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
        ) {
            let current = self.owners.read(token_id);
            assert!(current == from, "MockERC721: not the owner");
            self.owners.write(token_id, to);
        }
    }
}
