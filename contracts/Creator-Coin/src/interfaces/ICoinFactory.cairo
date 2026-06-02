use starknet::{ContractAddress, ClassHash};
use creator_coin::types::CoinRecord;
use creator_coin::interfaces::IExchangeAdapter::TickParams;

#[starknet::interface]
pub trait ICoinFactory<TState> {
    fn create_coin(
        ref self: TState, name: ByteArray, symbol: ByteArray, total_supply: u256,
    ) -> ContractAddress;
    fn launch_on_ekubo(
        ref self: TState,
        coin: ContractAddress,
        quote_token: ContractAddress,
        creator_allocation_bps: u16,
        seed_amount: u256,
        lock_duration: u64,
        ticks: TickParams,
    ) -> (felt252, u64);
    fn get_coin(self: @TState, coin_id: u256) -> CoinRecord;
    fn get_last_coin_id(self: @TState) -> u256;
    fn get_creator_coin_count(self: @TState, creator: ContractAddress) -> u32;
    fn get_creator_coin_ids(
        self: @TState, creator: ContractAddress, start: u32, count: u32,
    ) -> Array<u256>;
    fn get_creator_coin_class_hash(self: @TState) -> ClassHash;
}
