use starknet::ContractAddress;

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct CollectionCreated {
    #[key]
    pub collection_id: u256,
    #[key]
    pub organizer: ContractAddress,
    pub collection_address: ContractAddress,
    pub name: ByteArray,
    pub symbol: ByteArray,
    pub base_uri: ByteArray,
    pub claim_end_time: u64,
}

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct AllowlistRootSet {
    pub root: felt252,
}

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct TokenURISet {
    #[key]
    pub token_id: u256,
    pub uri: ByteArray,
}

/// ERC-5192.
#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct Locked {
    pub token_id: u256,
}
