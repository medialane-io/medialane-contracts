use starknet::ContractAddress;

#[starknet::interface]
pub trait ICreatorCoin<TState> {
    fn creator(self: @TState) -> ContractAddress;
}
