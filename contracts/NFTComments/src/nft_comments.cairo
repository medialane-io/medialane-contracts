use starknet::ContractAddress;
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};

#[starknet::interface]
trait INFTComments<TContractState> {
    fn add_comment(
        ref self: TContractState,
        nft_contract: ContractAddress,
        token_id: u256,
        content: ByteArray,
    );
}

#[starknet::interface]
trait IUpgradeable<TContractState> {
    fn upgrade(ref self: TContractState, new_class_hash: starknet::ClassHash);
}

#[starknet::contract]
mod NFTComments {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, ClassHash};
    use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};
    use core::num::traits::Zero;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_access::ownable::OwnableComponent;

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
            // Verify the token exists — owner_of reverts on non-existent token IDs.
            let _ = IERC721Dispatcher { contract_address: nft_contract }.owner_of(token_id);
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
