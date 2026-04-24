use starknet::ContractAddress;

#[starknet::interface]
pub trait INFTComments<TContractState> {
    fn add_comment(
        ref self: TContractState,
        nft_contract: ContractAddress,
        token_id: u256,
        content: ByteArray,
    );
    fn comment_count(self: @TContractState) -> u64;
}

#[starknet::interface]
pub trait IUpgradeable<TContractState> {
    fn upgrade(ref self: TContractState, new_class_hash: starknet::ClassHash);
}

#[starknet::contract]
pub mod NFTComments {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, ClassHash};
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
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
        // Key: (nft_contract, token_id, caller) — per-token-per-wallet rate limit.
        last_comment_time: starknet::storage::Map<(ContractAddress, u256, ContractAddress), u64>,
        // Monotonically increasing; each comment gets a unique ID. Never decremented.
        total_comments: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CommentAdded: CommentAdded,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommentAdded {
        #[key] pub nft_contract: ContractAddress,
        #[key] pub token_id: u256,
        #[key] pub author: ContractAddress,
        #[key] pub comment_id: u64,
        pub content: ByteArray,
        pub timestamp: u64,
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
            // ── Checks ────────────────────────────────────────────────────────
            assert!(!nft_contract.is_zero(), "invalid nft contract");
            assert!(content.len() > 0, "comment cannot be empty");
            assert!(content.len() <= 1000, "comment too long");

            let caller = get_caller_address();
            let now = get_block_timestamp();
            let last_time = self.last_comment_time.read((nft_contract, token_id, caller));
            assert!(now >= last_time + 60_u64, "rate limited: wait 60 seconds between comments");

            // ── Effects ───────────────────────────────────────────────────────
            self.last_comment_time.write((nft_contract, token_id, caller), now);
            let comment_id = self.total_comments.read() + 1;
            self.total_comments.write(comment_id);

            // ── Interactions (none — fully permissionless, no external calls) ─
            self.emit(CommentAdded {
                nft_contract,
                token_id,
                author: caller,
                comment_id,
                content,
                timestamp: now,
            });
        }

        fn comment_count(self: @ContractState) -> u64 {
            self.total_comments.read()
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
