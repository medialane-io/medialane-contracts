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
    /// The on-chain release version of this immutable deployment.
    fn contract_version(self: @TContractState) -> felt252;
}

#[starknet::contract]
pub mod NFTComments {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use core::num::traits::Zero;

    /// On-chain release version for this immutable deployment.
    const CONTRACT_VERSION: felt252 = '0.1.0';
    /// Minimum seconds a wallet must wait between comments on the same token.
    const COMMENT_COOLDOWN_SECONDS: u64 = 60;

    #[storage]
    struct Storage {
        // Key: (nft_contract, token_id, caller) — per-token-per-wallet rate limit.
        last_comment_time: starknet::storage::Map<(ContractAddress, u256, ContractAddress), u64>,
        // Global comment counter. Each comment receives a unique monotonic ID.
        total_comments: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CommentAdded: CommentAdded,
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
            assert!(
                now >= last_time + COMMENT_COOLDOWN_SECONDS,
                "rate limited: wait 60 seconds between comments",
            );

            // ── Effects ───────────────────────────────────────────────────────
            self.last_comment_time.write((nft_contract, token_id, caller), now);
            let comment_id = self.total_comments.read() + 1;
            self.total_comments.write(comment_id);

            // ── Interactions (none — no external calls, fully permissionless) ─
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

        fn contract_version(self: @ContractState) -> felt252 {
            CONTRACT_VERSION
        }
    }
}
