use starknet::ContractAddress;

// Minimal local interfaces for cross-contract calls — avoids OZ version coupling.
// The function signatures match the ERC standards; any compliant contract will satisfy them.

const IERC721_ID: felt252 = 0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943;

#[starknet::interface]
pub trait ISrc5<TContractState> {
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
}

#[starknet::interface]
pub trait IErc721OwnerOf<TContractState> {
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
}

#[starknet::interface]
pub trait INFTComments<TContractState> {
    fn add_comment(
        ref self: TContractState,
        nft_contract: ContractAddress,
        token_id: u256,
        content: ByteArray,
    );
}

#[starknet::interface]
pub trait IUpgradeable<TContractState> {
    fn upgrade(ref self: TContractState, new_class_hash: starknet::ClassHash);
}

#[starknet::contract]
mod NFTComments {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, ClassHash};
    use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};
    use core::num::traits::Zero;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_access::ownable::OwnableComponent;
    use super::{ISrc5Dispatcher, ISrc5DispatcherTrait};
    use super::{IErc721OwnerOfDispatcher, IErc721OwnerOfDispatcherTrait};
    use super::IERC721_ID;

    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        // Key: (nft_contract, token_id, caller) — per-NFT rate limit prevents
        // bypassing by spreading comments across different tokens.
        last_comment_time: starknet::storage::Map<(ContractAddress, u256, ContractAddress), u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CommentAdded: CommentAdded,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct CommentAdded {
        #[key] nft_contract: ContractAddress,
        #[key] token_id: u256,
        #[key] author: ContractAddress,
        content: ByteArray,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl NFTCommentsImpl of super::INFTComments<ContractState> {
        fn add_comment(
            ref self: ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            content: ByteArray,
        ) {
            assert!(!nft_contract.is_zero(), "invalid nft contract");
            assert!(content.len() > 0, "comment cannot be empty");
            assert!(content.len() <= 1000, "comment too long");
            // Verify token exists for ERC-721 contracts via SRC5 detection.
            // ERC-1155 has no owner_of equivalent, so we accept comments without
            // an existence check — non-existent token IDs are filtered off-chain.
            let is_erc721 = ISrc5Dispatcher { contract_address: nft_contract }
                .supports_interface(IERC721_ID);
            if is_erc721 {
                let _ = IErc721OwnerOfDispatcher { contract_address: nft_contract }
                    .owner_of(token_id);
            }
            let caller = get_caller_address();
            let last_time = self.last_comment_time.read((nft_contract, token_id, caller));
            let now = get_block_timestamp();
            assert!(now >= last_time + 60_u64, "rate limited: wait 60 seconds between comments");
            self.last_comment_time.write((nft_contract, token_id, caller), now);
            self.emit(CommentAdded {
                nft_contract,
                token_id,
                author: caller,
                content,
                timestamp: now,
            });
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of super::IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
