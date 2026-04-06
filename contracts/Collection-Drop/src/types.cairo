use starknet::ContractAddress;

/// Per-drop claim configuration. The organizer can update this at any time
/// to implement sequential phases (e.g. allowlist → public) by calling
/// `set_claim_conditions` between phases.
#[derive(Debug, Drop, Serde, Clone, starknet::Store)]
pub struct ClaimConditions {
    /// Unix timestamp when minting opens. 0 = open immediately.
    pub start_time: u64,
    /// Unix timestamp when minting closes. 0 = never closes.
    pub end_time: u64,
    /// Price per token in `payment_token` units. 0 = free mint.
    pub price: u256,
    /// ERC-20 token used for payment. Must be non-zero if price > 0.
    pub payment_token: ContractAddress,
    /// Max tokens a single wallet may mint across all phases. 0 = unlimited.
    pub max_quantity_per_wallet: u256,
}

/// Metadata stored in the factory for every deployed drop collection.
#[derive(Debug, Drop, Serde, starknet::Store)]
pub struct DropRecord {
    pub drop_id: u256,
    pub name: ByteArray,
    pub symbol: ByteArray,
    pub organizer: ContractAddress,
    pub collection_address: ContractAddress,
    pub max_supply: u256,
    pub created_at: u64,
}

/// Metadata stored for each registered organizer.
#[derive(Debug, Drop, Serde, starknet::Store)]
pub struct OrganizerRecord {
    pub name: ByteArray,
    pub active: bool,
    pub registered_at: u64,
}
