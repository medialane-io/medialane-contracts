// SPDX-License-Identifier: GPL-3.0

use core::hash::HashStateExTrait;
use core::hash::HashStateTrait;
use core::pedersen::PedersenTrait;
use media_wallet::signer::signer_signature::{Signer, starknet_signer_from_pubkey};
use media_wallet::utils::serialization::serialize;
use starknet::ClassHash;
use starknet::ContractAddress;

// Starknet contract address prefix constant
const CONTRACT_ADDRESS_PREFIX: felt252 = 'STARKNET_CONTRACT_ADDRESS';
// 2**251 - 256
const L2_ADDRESS_UPPER_BOUND: felt252 = 0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00;

#[starknet::interface]
pub trait IMediaWalletFactory<TContractState> {
    fn deploy_wallet(ref self: TContractState, owner_pubkey: felt252, salt: felt252) -> ContractAddress;
    fn compute_address(self: @TContractState, owner_pubkey: felt252, salt: felt252) -> ContractAddress;
    fn wallet_class_hash(self: @TContractState) -> ClassHash;
}

#[starknet::contract]
pub mod MediaWalletFactory {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
    use super::{build_constructor_calldata, compute_wallet_address};

    #[storage]
    struct Storage {
        wallet_class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        WalletDeployed: WalletDeployed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WalletDeployed {
        #[key]
        pub address: ContractAddress,
        pub owner_pubkey: felt252,
        pub salt: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, wallet_class_hash: ClassHash) {
        self.wallet_class_hash.write(wallet_class_hash);
    }

    #[abi(embed_v0)]
    impl MediaWalletFactoryImpl of super::IMediaWalletFactory<ContractState> {
        fn deploy_wallet(ref self: ContractState, owner_pubkey: felt252, salt: felt252) -> ContractAddress {
            let class_hash = self.wallet_class_hash.read();
            let calldata = build_constructor_calldata(owner_pubkey);
            let (address, _) = deploy_syscall(class_hash, salt, calldata, true).unwrap_syscall();
            self.emit(WalletDeployed { address, owner_pubkey, salt });
            address
        }

        fn compute_address(self: @ContractState, owner_pubkey: felt252, salt: felt252) -> ContractAddress {
            let class_hash = self.wallet_class_hash.read();
            let calldata = build_constructor_calldata(owner_pubkey);
            compute_wallet_address(salt, class_hash, calldata)
        }

        fn wallet_class_hash(self: @ContractState) -> ClassHash {
            self.wallet_class_hash.read()
        }
    }
}

fn build_constructor_calldata(owner_pubkey: felt252) -> Span<felt252> {
    let owner: Signer = starknet_signer_from_pubkey(owner_pubkey);
    let guardian: Option<Signer> = Option::None;
    serialize(@(owner, guardian)).span()
}

fn compute_wallet_address(
    salt: felt252, class_hash: ClassHash, constructor_calldata: Span<felt252>,
) -> ContractAddress {
    // Starknet address derivation: deploy_from_zero=true → deployer = 0
    // See https://docs.starknet.io/architecture-and-concepts/smart-contracts/contract-address/
    let constructor_calldata_hash = compute_hash_on_elements(constructor_calldata);

    let address_inputs = array![
        CONTRACT_ADDRESS_PREFIX,
        0, // deployer_address = 0 (deploy_from_zero: true)
        salt,
        class_hash.into(),
        constructor_calldata_hash,
    ];
    let raw_address = compute_hash_on_elements(address_inputs.span());

    let u256_addr: u256 = raw_address.into() % L2_ADDRESS_UPPER_BOUND.into();
    let felt_addr: felt252 = u256_addr.try_into().unwrap();
    felt_addr.try_into().unwrap()
}

fn compute_hash_on_elements(data: Span<felt252>) -> felt252 {
    let mut state = PedersenTrait::new(0);
    for elem in data {
        state = state.update_with(*elem);
    };
    state.update_with(data.len()).finalize()
}
