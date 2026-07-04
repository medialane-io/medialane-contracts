use starknet::ContractAddress;
use crate::core::types::*;

#[starknet::interface]
pub trait IMedialane1155<TState> {
    fn register_order(ref self: TState, order: Order);
    /// Fulfil `quantity` units of an open order. Caller IS the fulfiller — no
    /// fulfiller signature. Partial fills allowed (1 <= quantity <= remaining).
    fn fulfill_order(ref self: TState, order_hash: felt252, quantity: felt252);
    fn cancel_order(ref self: TState, cancel_request: CancelRequest);
    fn increment_counter(ref self: TState);
    fn get_order_details(self: @TState, order_hash: felt252) -> OrderDetails;
    fn get_order_hash(
        self: @TState, parameters: OrderParameters, signer: ContractAddress,
    ) -> felt252;
    fn get_cancellation_hash(
        self: @TState, cancellation: OrderCancellation, signer: ContractAddress,
    ) -> felt252;
    fn get_counter(self: @TState, offerer: ContractAddress) -> felt252;
    fn get_native_token_address(self: @TState) -> ContractAddress;
    /// The on-chain release version of this immutable deployment.
    fn contract_version(self: @TState) -> felt252;
}
