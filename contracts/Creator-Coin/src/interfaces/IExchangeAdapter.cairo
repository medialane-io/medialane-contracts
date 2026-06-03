use starknet::ContractAddress;

/// Off-chain-computed Ekubo tick params (initial price + single-sided range bounds),
/// split into (magnitude, sign) so the interface stays AMM-agnostic
/// (the MockExchange ignores them).
#[derive(Drop, Serde, Copy)]
pub struct TickParams {
    pub initial_tick_mag: u128,
    pub initial_tick_sign: bool,
    pub lower_mag: u128,
    pub lower_sign: bool,
    pub upper_mag: u128,
    pub upper_sign: bool,
}

/// Result of provisioning liquidity: the pool identity and the LP position NFT id.
#[derive(Drop, Serde)]
pub struct LaunchResult {
    pub pool_id: felt252,
    pub position_id: u256,
}

#[starknet::interface]
pub trait IExchangeAdapter<TState> {
    /// Deposits `coin_amount` of `coin` as **single-sided** liquidity in the
    /// coin/quote pool at the off-chain-computed `ticks`, and transfers the resulting
    /// LP position NFT to `recipient` (the creator). The factory transfers
    /// `coin_amount` to the adapter before calling. No quote is provided — quote
    /// enters the pool only as the public buys (unrug's proven model).
    fn add_liquidity(
        ref self: TState,
        coin: ContractAddress,
        quote: ContractAddress,
        coin_amount: u256,
        recipient: ContractAddress,
        ticks: TickParams,
    ) -> LaunchResult;
}
