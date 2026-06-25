use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct OrderCreated {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
}

/// Enriched at fill so the indexer has the full economic outcome without a
/// follow-up `get_order_details` call.
#[derive(Drop, starknet::Event)]
pub struct OrderFulfilled {
    #[key]
    pub order_hash: felt252,
    #[key]
    pub offerer: ContractAddress,
    #[key]
    pub fulfiller: ContractAddress,
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

/// Emitted when an offerer bumps their bulk-cancel epoch, invalidating all of
/// their outstanding orders signed under the previous counter.
#[derive(Drop, starknet::Event)]
pub struct CounterIncremented {
    #[key]
    pub offerer: ContractAddress,
    pub new_counter: felt252,
}
