use starknet::ContractAddress;

#[starknet::interface]
pub trait ILiquidityLock<TState> {
    /// Records a locked LP position. Called by the factory after it has
    /// transferred the position to this contract.
    fn lock(
        ref self: TState,
        coin_address: ContractAddress,
        beneficiary: ContractAddress,
        position_id: u256,
        unlock_time: u64,
    ) -> u64;
    /// Beneficiary withdraws after unlock_time. Reverts otherwise.
    fn withdraw(ref self: TState, lock_id: u64);
    fn beneficiary_of(self: @TState, lock_id: u64) -> ContractAddress;
    fn unlock_time_of(self: @TState, lock_id: u64) -> u64;
    fn is_withdrawn(self: @TState, lock_id: u64) -> bool;
}
