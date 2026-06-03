use starknet::ContractAddress;

/// Off-chain-computed Ekubo tick params (initial price + full-range bounds),
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

/// Result of a launch: pool identity, the LP position NFT id, and how many
/// coins the buyback actually delivered to the creator.
#[derive(Drop, Serde)]
pub struct LaunchResult {
    pub pool_id: felt252,
    pub position_id: u256,
    pub coins_bought: u256,
}

#[starknet::interface]
pub trait IExchangeAdapter<TState> {
    /// The factory transfers `coin_supply` of `coin` and `quote_in` of `quote`
    /// to the adapter before calling. The adapter then, atomically:
    ///   1. initialises the pool at `ticks.initial_tick`,
    ///   2. deposits the full `coin_supply` as liquidity over `[lower, upper]`,
    ///   3. swaps `quote_in` of `quote` for `coin` (the founder buyback) and
    ///      transfers the bought coins to `creator`,
    ///   4. transfers the LP position NFT to `creator`.
    /// Returns the pool id, the position id, and `coins_bought`.
    fn launch(
        ref self: TState,
        coin: ContractAddress,
        quote: ContractAddress,
        coin_supply: u256,
        quote_in: u256,
        creator: ContractAddress,
        ticks: TickParams,
    ) -> LaunchResult;

    /// The ERC-721 contract that represents LP positions.
    fn position_nft_address(self: @TState) -> ContractAddress;
}
