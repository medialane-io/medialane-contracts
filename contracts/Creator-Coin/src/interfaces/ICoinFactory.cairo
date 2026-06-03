use starknet::{ContractAddress, ClassHash};
use creator_coin::types::CoinRecord;
use creator_coin::interfaces::IExchangeAdapter::TickParams;

#[starknet::interface]
pub trait ICoinFactory<TState> {
    /// Deploy a fixed-supply ERC-20 and launch it on Ekubo in one tx:
    /// full supply into the pool, a <=10% founder buyback paid in `quote_token`,
    /// bought coins + the LP position handed to the caller (the creator).
    /// `creator_allocation_bps` is the *cap* the buyback must not exceed.
    fn launch(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        total_supply: u256,
        quote_token: ContractAddress,
        creator_allocation_bps: u16,
        buyback_quote_amount: u256,
        ticks: TickParams,
    ) -> (ContractAddress, felt252);
    fn get_coin(self: @TState, coin_id: u256) -> CoinRecord;
    fn get_last_coin_id(self: @TState) -> u256;
    fn get_creator_coin_count(self: @TState, creator: ContractAddress) -> u32;
    fn get_creator_coin_ids(
        self: @TState, creator: ContractAddress, start: u32, count: u32,
    ) -> Array<u256>;
    fn get_creator_coin_class_hash(self: @TState) -> ClassHash;
}
