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
    pub price_per_unit: felt252,
    pub payment_token: ContractAddress,
}

/// Emitted when an order is (partially or fully) fulfilled.
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
    pub royalty_receiver: ContractAddress,
    // u256 serialises as two felt252 words (low, high) in the event encoding.
    // Indexers must read this field as a 2-word value, unlike the felt252 fields above.
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
