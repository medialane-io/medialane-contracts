use starknet::ContractAddress;

/// Result of provisioning a pool: the pool identity and the LP position token id.
#[derive(Drop, Serde)]
pub struct LaunchResult {
    pub pool_id: felt252,
    pub position_id: u256,
}

#[starknet::interface]
pub trait IExchangeAdapter<TState> {
    /// Creates (or initialises) the coin/quote pool, adds `coin_amount` + `quote_amount`
    /// as full-range liquidity, and returns the LP position. The factory transfers the
    /// tokens to the adapter before calling this; the adapter ends holding the position.
    fn add_liquidity(
        ref self: TState,
        coin: ContractAddress,
        quote: ContractAddress,
        coin_amount: u256,
        quote_amount: u256,
    ) -> LaunchResult;
    /// Transfers the position token to `to` (the locker).
    fn transfer_position(ref self: TState, position_id: u256, to: ContractAddress);
}
