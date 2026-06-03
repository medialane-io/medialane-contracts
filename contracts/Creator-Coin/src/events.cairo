use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct CoinLaunched {
    #[key]
    pub coin_address: ContractAddress,
    #[key]
    pub creator: ContractAddress,
    pub coin_id: u256,
    pub quote_token: ContractAddress,
    pub total_supply: u256,
    pub creator_allocation_bps: u16,
    pub pool_id: felt252,
    pub timestamp: u64,
}
