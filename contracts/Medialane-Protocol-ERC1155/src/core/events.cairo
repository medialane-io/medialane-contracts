use starknet::ContractAddress;

/// Emitted when an order is registered by the offerer.
#[derive(Drop, starknet::Event)]
pub struct OrderCreated {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
    pub nft_contract: ContractAddress,
    pub token_id: felt252,
    pub amount: felt252,
}

/// Emitted when an order is successfully fulfilled.
#[derive(Drop, starknet::Event)]
pub struct OrderFulfilled {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
    #[key]
    pub fulfiller: ContractAddress,
    pub royalty_receiver: ContractAddress,
    pub royalty_amount: u256,
}

/// Emitted when an order is cancelled by the offerer.
#[derive(Drop, starknet::Event)]
pub struct OrderCancelled {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
}
