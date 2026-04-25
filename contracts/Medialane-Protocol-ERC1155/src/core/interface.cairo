use starknet::ContractAddress;
use crate::core::types::*;

#[starknet::interface]
pub trait IMedialane1155<TState> {
    fn register_order(ref self: TState, order: Order);
    fn fulfill_order(ref self: TState, fulfillment_request: FulfillmentRequest);
    fn cancel_order(ref self: TState, cancel_request: CancelRequest);

    /// Returns the stored details for an order hash.
    fn get_order_details(self: @TState, order_hash: felt252) -> OrderDetails;

    /// Computes the SNIP-12 hash for a set of order parameters.
    /// Useful for off-chain hash verification and frontend tooling.
    fn get_order_hash(
        self: @TState, parameters: OrderParameters, signer: ContractAddress,
    ) -> felt252;

    /// Returns the address of the native payment token (STRK).
    fn get_native_token(self: @TState) -> ContractAddress;
}
