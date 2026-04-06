use starknet::{ClassHash, ContractAddress};
use crate::types::{ClaimConditions, DropRecord, OrganizerRecord};

#[starknet::interface]
pub trait IDropFactory<TContractState> {
    // ── Organizer management ─────────────────────────────────────────────────
    fn register_organizer(
        ref self: TContractState, organizer: ContractAddress, name: ByteArray,
    );
    fn revoke_organizer(ref self: TContractState, organizer: ContractAddress);
    fn get_organizer(self: @TContractState, organizer: ContractAddress) -> OrganizerRecord;
    fn is_active_organizer(self: @TContractState, organizer: ContractAddress) -> bool;

    // ── Drop management ──────────────────────────────────────────────────────
    fn create_drop(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        max_supply: u256,
        initial_conditions: ClaimConditions,
    ) -> ContractAddress;

    fn get_drop(self: @TContractState, drop_id: u256) -> DropRecord;
    fn get_drop_address(self: @TContractState, drop_id: u256) -> ContractAddress;
    fn get_last_drop_id(self: @TContractState) -> u256;
    fn get_organizer_drop_count(self: @TContractState, organizer: ContractAddress) -> u32;
    fn get_organizer_drop_ids(
        self: @TContractState, organizer: ContractAddress, start: u32, count: u32,
    ) -> Array<u256>;

    // ── Admin ────────────────────────────────────────────────────────────────
    fn get_drop_collection_class_hash(self: @TContractState) -> ClassHash;
    fn set_drop_collection_class_hash(ref self: TContractState, new_class_hash: ClassHash);
}
