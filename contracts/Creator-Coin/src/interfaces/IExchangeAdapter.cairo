use starknet::ContractAddress;

/// Off-chain-computed tick parameters for an Ekubo launch.
///
/// The dapp/SDK computes the initial price tick (from the desired
/// quote/coin ratio) and the full-range bounds (from Ekubo's MAX_TICK +
/// the pool's tick_spacing) using Ekubo's SDK, and passes them in. This keeps
/// the on-chain adapter free of log/tick math and of protocol constants.
/// Ticks are expressed as Ekubo `i129` split into (magnitude, sign) so this
/// interface stays AMM-agnostic (MockExchange ignores them).
#[derive(Drop, Serde, Copy)]
pub struct TickParams {
    pub initial_tick_mag: u128,
    pub initial_tick_sign: bool,
    pub lower_mag: u128,
    pub lower_sign: bool,
    pub upper_mag: u128,
    pub upper_sign: bool,
}

/// Result of provisioning a pool.
/// `pool_id` is an opaque identifier (the Ekubo adapter uses the Poseidon hash
/// of the PoolKey, since Ekubo pools are keyed by struct, not a felt).
/// `position_id` is the LP position NFT id (Ekubo's are u64, widened to u256).
#[derive(Drop, Serde)]
pub struct LaunchResult {
    pub pool_id: felt252,
    pub position_id: u256,
}

#[starknet::interface]
pub trait IExchangeAdapter<TState> {
    /// Creates (or initialises) the coin/quote pool at `ticks.initial_tick`, adds
    /// `coin_amount` + `quote_amount` as liquidity over `[lower, upper]`, and returns
    /// the LP position. The factory transfers the tokens to the adapter before calling
    /// this; the adapter ends holding the position NFT.
    fn add_liquidity(
        ref self: TState,
        coin: ContractAddress,
        quote: ContractAddress,
        coin_amount: u256,
        quote_amount: u256,
        ticks: TickParams,
    ) -> LaunchResult;
    /// Transfers the position NFT to `to` (the locker).
    fn transfer_position(ref self: TState, position_id: u256, to: ContractAddress);
    /// The ERC-721 contract that represents LP positions (so the locker can return it).
    fn position_nft_address(self: @TState) -> ContractAddress;
}
