use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct PlanRecord {
    pub creator: ContractAddress,
    pub recipient: ContractAddress,
    pub payment_token: ContractAddress,
    pub price: u256,
    pub duration: u64,
    pub tier_id: felt252,
    pub metadata_uri: ByteArray,
    pub active: bool,
}

/// Canonical proof-program identifiers. Placeholder values in the reference
/// build; set to the real circuit program hashes once the circuits exist.
/// Hardcoded (never settable) to keep the contract ownerless.
pub const PAYMENT_PROGRAM: felt252 = 'PAYMENT_PROGRAM_V1_PLACEHOLDER';
pub const TIER_PROGRAM: felt252 = 'TIER_PROGRAM_V1_PLACEHOLDER';

pub fn bytearray_starts_with(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let n = needle.len();
    if haystack.len() < n {
        return false;
    }
    let mut i: u32 = 0;
    let mut matches = true;
    while i < n {
        if haystack.at(i).unwrap() != needle.at(i).unwrap() {
            matches = false;
            break;
        }
        i += 1;
    }
    matches
}
