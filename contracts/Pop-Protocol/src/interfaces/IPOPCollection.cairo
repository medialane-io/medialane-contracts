use starknet::ContractAddress;

#[starknet::interface]
pub trait IPOPCollection<TContractState> {
    // ── Allowlist management (ORGANIZER_ROLE) ────────────────────────────────

    /// Adds a single address to the allowlist.
    /// Only whitelisted addresses can call claim().
    fn add_to_allowlist(ref self: TContractState, address: ContractAddress);

    /// Adds up to MAX_BATCH_SIZE addresses in one transaction.
    /// Called by the backend after receiving the participant list from the provider.
    fn batch_add_to_allowlist(ref self: TContractState, addresses: Span<ContractAddress>);

    /// Removes an address from the allowlist.
    fn remove_from_allowlist(ref self: TContractState, address: ContractAddress);

    // ── Collection management (ORGANIZER_ROLE) ───────────────────────────────

    /// Updates the collection-level base URI (fallback for all tokens without a custom URI).
    fn set_base_uri(ref self: TContractState, new_uri: ByteArray);

    /// Sets or updates the URI for a specific token.
    /// Use this to issue achievement variants (e.g. max score, honour, distinction).
    fn set_token_uri(ref self: TContractState, token_id: u256, uri: ByteArray);

    /// Pauses or unpauses the collection (DEFAULT_ADMIN_ROLE — platform emergency only).
    fn set_paused(ref self: TContractState, paused: bool);

    /// Mints directly to a recipient, bypassing the allowlist.
    /// Accepts an optional custom URI for achievement-tier NFTs.
    /// Pass an empty ByteArray to use the collection base URI.
    fn admin_mint(ref self: TContractState, recipient: ContractAddress, custom_uri: ByteArray);

    // ── Student claim ─────────────────────────────────────────────────────────

    /// Caller must be on the allowlist and must not have claimed before.
    /// Mints one soulbound ERC-721 to the caller with the collection base URI.
    fn claim(ref self: TContractState);

    // ── View functions ────────────────────────────────────────────────────────

    /// Returns true if `address` is on the allowlist for this collection.
    fn is_eligible(self: @TContractState, address: ContractAddress) -> bool;

    /// Returns true if `address` has already minted from this collection.
    fn has_claimed(self: @TContractState, address: ContractAddress) -> bool;

    /// Returns the collection ID assigned by the factory.
    fn get_collection_id(self: @TContractState) -> u256;

    /// Returns the claim deadline timestamp. 0 means no deadline.
    fn get_claim_end_time(self: @TContractState) -> u64;

    /// Returns true if the collection is currently paused.
    fn is_paused(self: @TContractState) -> bool;

    /// Returns the total number of POPs minted from this collection.
    fn total_minted(self: @TContractState) -> u256;
}
