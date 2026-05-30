use starknet::ContractAddress;
use crate::core::types::*;

#[starknet::interface]
pub trait IMedialane<TState> {
    /// Register a maker's signed order. Asserts the order targets this contract,
    /// matches the offerer's current counter, has a valid shape and signature.
    fn register_order(ref self: TState, order: Order);
    /// Fulfil an open order. The caller IS the fulfiller — no fulfiller signature
    /// is required (audit F3).
    fn fulfill_order(ref self: TState, order_hash: felt252);
    /// Cancel a single order (offerer-signed; relayer-submittable).
    fn cancel_order(ref self: TState, cancel_request: CancelRequest);
    /// Bulk-cancel: bump the caller's counter, invalidating all of their
    /// outstanding orders signed under the previous counter (audit F2).
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
}
