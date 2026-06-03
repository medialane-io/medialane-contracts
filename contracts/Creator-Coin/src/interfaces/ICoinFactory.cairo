use starknet::{ContractAddress, ClassHash};
use creator_coin::types::CoinRecord;
use creator_coin::interfaces::IExchangeAdapter::TickParams;

#[starknet::interface]
pub trait ICoinFactory<TState> {
    /// Deploy a fixed-supply ERC-20 and launch it on Ekubo in one tx (unrug's model):
    /// the creator keeps a capped founder allocation (<=10%, transferred directly),
    /// the remaining supply is deposited as single-sided liquidity, and the LP
    /// position NFT goes to the creator. No swap, no quote paid by the creator.
    fn launch(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        total_supply: u256,
        quote_token: ContractAddress,
        creator_allocation_bps: u16,
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
