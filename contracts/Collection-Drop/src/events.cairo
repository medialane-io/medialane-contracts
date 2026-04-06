use starknet::ContractAddress;

/// Emitted when an organizer is registered.
#[derive(Drop, starknet::Event)]
pub struct OrganizerRegistered {
    #[key]
    pub organizer: ContractAddress,
    pub name: ByteArray,
    pub timestamp: u64,
}

/// Emitted when an organizer's access is revoked.
#[derive(Drop, starknet::Event)]
pub struct OrganizerRevoked {
    #[key]
    pub organizer: ContractAddress,
    pub timestamp: u64,
}

/// Emitted by the factory when a new drop collection is deployed.
#[derive(Drop, starknet::Event)]
pub struct DropCreated {
    #[key]
    pub drop_id: u256,
    #[key]
    pub organizer: ContractAddress,
    pub collection_address: ContractAddress,
    pub name: ByteArray,
    pub max_supply: u256,
    pub timestamp: u64,
}

/// Emitted each time tokens are minted via `claim` or `admin_mint`.
#[derive(Drop, starknet::Event)]
pub struct TokensClaimed {
    #[key]
    pub drop_id: u256,
    #[key]
    pub claimer: ContractAddress,
    pub recipient: ContractAddress,
    pub quantity: u256,
    pub start_token_id: u256,
    pub price_per_token: u256,
    pub total_paid: u256,
    pub timestamp: u64,
}

/// Emitted when the organizer updates claim conditions (phase change).
#[derive(Drop, starknet::Event)]
pub struct ClaimConditionsUpdated {
    #[key]
    pub drop_id: u256,
    pub start_time: u64,
    pub end_time: u64,
    pub price: u256,
    pub max_quantity_per_wallet: u256,
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

/// Emitted after a batch allowlist update (summary event).
#[derive(Drop, starknet::Event)]
pub struct BatchAllowlistUpdated {
    pub count: u32,
    pub timestamp: u64,
}

/// Emitted when allowlist enforcement is toggled.
#[derive(Drop, starknet::Event)]
pub struct AllowlistEnabledChanged {
    #[key]
    pub drop_id: u256,
    pub enabled: bool,
    pub timestamp: u64,
}

/// Emitted when the drop is paused or unpaused.
#[derive(Drop, starknet::Event)]
pub struct DropPauseChanged {
    #[key]
    pub drop_id: u256,
    pub paused: bool,
    pub timestamp: u64,
}

/// Emitted when the organizer withdraws accumulated payments.
#[derive(Drop, starknet::Event)]
pub struct PaymentsWithdrawn {
    #[key]
    pub drop_id: u256,
    pub to: ContractAddress,
    pub amount: u256,
    pub token: ContractAddress,
    pub timestamp: u64,
}

/// Emitted when a per-token URI override is set.
#[derive(Drop, starknet::Event)]
pub struct TokenURIUpdated {
    #[key]
    pub token_id: u256,
    pub uri: ByteArray,
    pub timestamp: u64,
}
