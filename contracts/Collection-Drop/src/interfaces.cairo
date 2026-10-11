use starknet::{ClassHash, ContractAddress};
use crate::types::SaleTerms;

#[starknet::interface]
pub trait IDropFactory<TState> {
    /// Deploys a drop whose organizer is the caller.
    fn create_drop(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        max_supply: u256,
        terms: SaleTerms,
        allowlist_root: felt252,
    ) -> ContractAddress;
    fn get_drop_address(self: @TState, drop_id: u256) -> ContractAddress;
    fn get_last_drop_id(self: @TState) -> u256;
    fn get_collection_class_hash(self: @TState) -> ClassHash;
    fn version(self: @TState) -> felt252;
}

#[starknet::interface]
pub trait IDropCollection<TState> {
    /// Mints `quantity` to the caller and pays `price * quantity` from the caller to the
    /// organizer. `proof` is ignored when the allowlist root is 0.
    fn claim(ref self: TState, quantity: u256, proof: Span<felt252>);
    /// Organizer only. Free mint within the supply cap.
    fn issue(ref self: TState, recipient: ContractAddress, quantity: u256);
    /// Organizer only. A root of 0 opens the drop to everyone.
    fn set_allowlist_root(ref self: TState, root: felt252);
    fn organizer(self: @TState) -> ContractAddress;
    fn terms(self: @TState) -> SaleTerms;
    fn allowlist_root(self: @TState) -> felt252;
    fn max_supply(self: @TState) -> u256;
    fn total_minted(self: @TState) -> u256;
    fn claimed_by(self: @TState, wallet: ContractAddress) -> u256;
    fn version(self: @TState) -> felt252;
}
