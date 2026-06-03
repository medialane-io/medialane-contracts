use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store, Clone)]
pub struct CoinRecord {
    pub coin_id: u256,
    pub coin_address: ContractAddress,
    pub creator: ContractAddress,
    pub quote_token: ContractAddress,
    pub total_supply: u256,
    pub creator_allocation_bps: u16,
    pub pool_id: felt252,
    pub created_at: u64,
}
