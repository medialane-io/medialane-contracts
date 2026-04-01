use starknet::ContractAddress;
use starknet::ClassHash;
use crate::types::{CollectionRecord, ProviderRecord, EventType};

#[starknet::interface]
pub trait IPOPFactory<TContractState> {
    // ── Provider management (DEFAULT_ADMIN_ROLE only) ─────────────────────────

    /// Registers a provider and grants them ORGANIZER_ROLE so they can create collections.
    /// Any organization (bootcamp, conference, DAO, protocol) can be onboarded this way.
    fn register_provider(
        ref self: TContractState,
        provider: ContractAddress,
        name: ByteArray,
        website: ByteArray,
    );

    /// Revokes a provider's ORGANIZER_ROLE. Existing collections are unaffected.
    fn revoke_provider(ref self: TContractState, provider: ContractAddress);

    /// Returns the provider record for a given address.
    fn get_provider(self: @TContractState, provider: ContractAddress) -> ProviderRecord;

    /// Returns true if the address is an active registered provider.
    fn is_active_provider(self: @TContractState, provider: ContractAddress) -> bool;

    // ── Collection management (ORGANIZER_ROLE) ────────────────────────────────

    /// Deploys a new soulbound POP collection contract for an event/class/bootcamp.
    /// Caller must hold ORGANIZER_ROLE. Returns the address of the deployed collection.
    fn create_collection(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        event_type: EventType,
        claim_end_time: u64,
    ) -> ContractAddress;

    /// Returns the full record for a given collection ID.
    fn get_collection(self: @TContractState, collection_id: u256) -> CollectionRecord;

    /// Returns the deployed contract address for a collection ID.
    fn get_collection_address(self: @TContractState, collection_id: u256) -> ContractAddress;

    /// Returns the last assigned collection ID (total collections created).
    fn get_last_collection_id(self: @TContractState) -> u256;

    /// Returns how many collections a provider has created.
    fn get_provider_collection_count(self: @TContractState, provider: ContractAddress) -> u32;

    /// Returns a paginated slice of collection IDs for a given provider.
    /// start = 0-based index, count = number of IDs to return.
    fn get_provider_collection_ids(
        self: @TContractState, provider: ContractAddress, start: u32, count: u32,
    ) -> Array<u256>;

    /// Returns the current POPCollection class hash used for deployments.
    fn get_pop_collection_class_hash(self: @TContractState) -> ClassHash;

    /// Updates the POPCollection class hash (for upgrades to new collection logic).
    /// Only DEFAULT_ADMIN_ROLE.
    fn set_pop_collection_class_hash(ref self: TContractState, new_class_hash: ClassHash);
}
