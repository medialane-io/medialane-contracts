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
    pub lock_expiry: u64,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct LiquidityLocked {
    #[key]
    pub lock_id: u64,
    #[key]
    pub coin_address: ContractAddress,
    pub beneficiary: ContractAddress,
    pub position_id: u256,
    pub unlock_time: u64,
}

#[derive(Drop, starknet::Event)]
pub struct LiquidityWithdrawn {
    #[key]
    pub lock_id: u64,
    pub beneficiary: ContractAddress,
    pub timestamp: u64,
}
