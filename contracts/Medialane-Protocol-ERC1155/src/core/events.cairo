use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct OrderCreated {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct OrderFulfilled {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
    #[key]
    pub fulfiller: ContractAddress,
    pub quantity: felt252,
    pub remaining_amount: felt252,
    pub sale_amount: u256,
    pub royalty_receiver: ContractAddress,
    pub royalty_amount: u256,
}

#[derive(Drop, starknet::Event)]
pub struct OrderCancelled {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct CounterIncremented {
    #[key]
    pub offerer: ContractAddress,
    pub new_counter: felt252,
}
