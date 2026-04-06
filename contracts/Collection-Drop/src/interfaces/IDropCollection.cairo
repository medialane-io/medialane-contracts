use starknet::ContractAddress;
use crate::types::ClaimConditions;

#[starknet::interface]
pub trait IDropCollection<TContractState> {
    // ── Minting ──────────────────────────────────────────────────────────────

    /// Public mint. Handles both free and paid claims uniformly.
    fn claim(ref self: TContractState, quantity: u256);

    /// Bypasses conditions and allowlist — for gifting or reserved allocations.
    fn admin_mint(
        ref self: TContractState, recipient: ContractAddress, quantity: u256, custom_uri: ByteArray,
    );

    // ── Claim conditions (phase management) ──────────────────────────────────

    fn set_claim_conditions(ref self: TContractState, conditions: ClaimConditions);
    fn get_claim_conditions(self: @TContractState) -> ClaimConditions;

    // ── Allowlist ────────────────────────────────────────────────────────────

    fn set_allowlist_enabled(ref self: TContractState, enabled: bool);
    fn is_allowlist_enabled(self: @TContractState) -> bool;
    fn add_to_allowlist(ref self: TContractState, address: ContractAddress);
    fn batch_add_to_allowlist(ref self: TContractState, addresses: Span<ContractAddress>);
    fn remove_from_allowlist(ref self: TContractState, address: ContractAddress);
    fn is_allowlisted(self: @TContractState, address: ContractAddress) -> bool;

    // ── Metadata ─────────────────────────────────────────────────────────────

    fn set_base_uri(ref self: TContractState, new_uri: ByteArray);
    fn set_token_uri(ref self: TContractState, token_id: u256, uri: ByteArray);

    // ── Admin ────────────────────────────────────────────────────────────────

    fn set_paused(ref self: TContractState, paused: bool);
    fn withdraw_payments(ref self: TContractState);

    // ── Views ────────────────────────────────────────────────────────────────

    fn get_drop_id(self: @TContractState) -> u256;
    fn get_max_supply(self: @TContractState) -> u256;
    fn total_minted(self: @TContractState) -> u256;
    fn remaining_supply(self: @TContractState) -> u256;
    fn minted_by_wallet(self: @TContractState, wallet: ContractAddress) -> u256;
    fn is_paused(self: @TContractState) -> bool;
}
