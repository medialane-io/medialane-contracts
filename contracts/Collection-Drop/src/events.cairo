use starknet::ContractAddress;
use crate::types::SaleTerms;

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct DropCreated {
    #[key]
    pub drop_id: u256,
    #[key]
    pub organizer: ContractAddress,
    pub collection_address: ContractAddress,
    pub name: ByteArray,
    pub symbol: ByteArray,
    pub base_uri: ByteArray,
    pub max_supply: u256,
    pub terms: SaleTerms,
    pub allowlist_root: felt252,
}

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct Claimed {
    #[key]
    pub claimer: ContractAddress,
    pub quantity: u256,
    pub first_token_id: u256,
    pub total_paid: u256,
}

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct Issued {
    #[key]
    pub recipient: ContractAddress,
    pub quantity: u256,
    pub first_token_id: u256,
}

#[derive(Drop, PartialEq, Debug, starknet::Event)]
pub struct AllowlistRootSet {
    pub root: felt252,
}
