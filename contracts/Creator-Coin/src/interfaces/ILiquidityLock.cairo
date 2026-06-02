use starknet::ContractAddress;

#[starknet::interface]
pub trait ILiquidityLock<TState> {
    /// Records a locked LP position. Called by the factory after the adapter has
    /// transferred the position NFT (`nft_address`#`position_id`) to this contract.
    fn lock(
        ref self: TState,
        coin_address: ContractAddress,
        beneficiary: ContractAddress,
        nft_address: ContractAddress,
        position_id: u256,
        unlock_time: u64,
    ) -> u64;
    /// Beneficiary withdraws (transfers the position NFT out) after unlock_time. Reverts otherwise.
    fn withdraw(ref self: TState, lock_id: u64);
    fn beneficiary_of(self: @TState, lock_id: u64) -> ContractAddress;
    fn unlock_time_of(self: @TState, lock_id: u64) -> u64;
    fn nft_address_of(self: @TState, lock_id: u64) -> ContractAddress;
    fn position_id_of(self: @TState, lock_id: u64) -> u256;
    fn is_withdrawn(self: @TState, lock_id: u64) -> bool;
}
