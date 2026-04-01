use starknet::ContractAddress;

/// Metadata stored for each registered provider (organization).
/// Any provider granted ORGANIZER_ROLE can deploy their own collections.
#[derive(Debug, Drop, Serde, starknet::Store)]
pub struct ProviderRecord {
    pub name: ByteArray,       // human-readable organization name
    pub website: ByteArray,    // organization website or social link
    pub active: bool,
    pub registered_at: u64,
}

/// Discriminates the kind of credential being issued.
#[derive(Debug, Drop, Serde, starknet::Store, PartialEq, Clone, Copy)]
pub enum EventType {
    #[default]
    Class,    // Multi-session course
    Event,    // Hackathon / workshop / conference
    Quest,    // Task / challenge / quest
    Bootcamp, // Intensive training programme
}

/// Metadata record stored in the factory for every deployed collection.
#[derive(Debug, Drop, Serde, starknet::Store)]
pub struct CollectionRecord {
    pub collection_id: u256,
    pub name: ByteArray,
    pub symbol: ByteArray,
    pub event_type: EventType,
    pub organizer: ContractAddress,
    pub collection_address: ContractAddress,
    pub created_at: u64,
}
