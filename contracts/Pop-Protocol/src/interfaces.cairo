use starknet::{ClassHash, ContractAddress};

/// ERC-5192 (minimal soulbound) interface id.
pub const IERC5192_ID: felt252 = 0xb45a3c0e;

#[starknet::interface]
pub trait IERC5192<TState> {
    fn locked(self: @TState, token_id: u256) -> bool;
}

#[starknet::interface]
pub trait IPOPFactory<TState> {
    /// Deploys a collection whose organizer is the caller.
    fn create_collection(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        claim_end_time: u64,
    ) -> ContractAddress;
    fn get_collection_address(self: @TState, collection_id: u256) -> ContractAddress;
    fn get_last_collection_id(self: @TState) -> u256;
    fn get_collection_class_hash(self: @TState) -> ClassHash;
    fn version(self: @TState) -> felt252;
}

#[starknet::interface]
pub trait IPOPCollection<TState> {
    /// Organizer only. A root of 0 closes self-serve claims.
    fn set_allowlist_root(ref self: TState, root: felt252);
    /// Mints to the caller if `proof` shows the caller is in the allowlist.
    fn claim(ref self: TState, proof: Span<felt252>);
    /// Organizer only. Mints to `recipient`; an empty `token_uri` uses the collection URI.
    fn issue(ref self: TState, recipient: ContractAddress, token_uri: ByteArray);
    fn organizer(self: @TState) -> ContractAddress;
    fn allowlist_root(self: @TState) -> felt252;
    fn claim_end_time(self: @TState) -> u64;
    fn has_claimed(self: @TState, address: ContractAddress) -> bool;
    fn total_issued(self: @TState) -> u256;
    fn version(self: @TState) -> felt252;
}
