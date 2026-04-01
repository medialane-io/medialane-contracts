use starknet::ContractAddress;
use crate::types::EventType;

/// Emitted when a provider (organization) is registered and granted ORGANIZER_ROLE.
#[derive(Drop, starknet::Event)]
pub struct ProviderRegistered {
    #[key]
    pub provider: ContractAddress,
    pub name: ByteArray,
    pub website: ByteArray,
    pub timestamp: u64,
}

/// Emitted when a provider's access is revoked.
#[derive(Drop, starknet::Event)]
pub struct ProviderRevoked {
    #[key]
    pub provider: ContractAddress,
    pub timestamp: u64,
}

/// Emitted by the factory when a new POP collection is deployed.
#[derive(Drop, starknet::Event)]
pub struct CollectionCreated {
    #[key]
    pub collection_id: u256,
    #[key]
    pub organizer: ContractAddress,
    pub collection_address: ContractAddress,
    pub event_type: EventType,
    pub name: ByteArray,
    pub timestamp: u64,
}

/// Emitted by a collection each time a student mints their POP.
#[derive(Drop, starknet::Event)]
pub struct POPMinted {
    #[key]
    pub collection_id: u256,
    #[key]
    pub recipient: ContractAddress,
    pub token_id: u256,
    pub timestamp: u64,
}

/// Emitted when a single address is added or removed from the allowlist.
#[derive(Drop, starknet::Event)]
pub struct AllowlistUpdated {
    #[key]
    pub user: ContractAddress,
    pub allowed: bool,
    pub timestamp: u64,
}

/// Emitted after a batch allowlist update (summary event for gas efficiency).
#[derive(Drop, starknet::Event)]
pub struct BatchAllowlistUpdated {
    pub count: u32,
    pub timestamp: u64,
}

/// Emitted when a collection is paused or unpaused.
#[derive(Drop, starknet::Event)]
pub struct CollectionPauseChanged {
    #[key]
    pub collection_id: u256,
    pub paused: bool,
    pub timestamp: u64,
}

/// Emitted when a per-token URI is set or updated.
/// Used for achievement tiers, bonus NFTs, or any token-level metadata override.
#[derive(Drop, starknet::Event)]
pub struct TokenURIUpdated {
    #[key]
    pub token_id: u256,
    pub uri: ByteArray,
    pub timestamp: u64,
}
