use starknet::ContractAddress;
use crate::core::types::*;

#[starknet::interface]
pub trait IMedialane1155<TState> {
    /// Registers a new ERC-1155 sell order.
    ///
    /// The offerer signs `OrderParameters` off-chain via SNIP-12 and submits it here.
    /// The order is stored as `Created`; the offerer's ERC-1155 approval must be in place
    /// before `fulfill_order` is called.
    fn register_order(ref self: TState, order: Order);

    /// Fulfills a registered order.
    ///
    /// The fulfiller (buyer) signs `OrderFulfillment` off-chain. On success:
    ///   1. ERC-1155 tokens are transferred from offerer → fulfiller.
    ///   2. ERC-2981 royalty (if any) is paid from fulfiller → royalty_receiver.
    ///   3. Remaining payment is transferred from fulfiller → offerer.
    ///
    /// The fulfiller must have approved this contract to spend `total_price` of the
    /// payment token (or STRK if `payment_token` is zero).
    fn fulfill_order(ref self: TState, fulfillment_request: FulfillmentRequest);

    /// Cancels a registered order.
    ///
    /// Only the original offerer can cancel. The offerer signs `OrderCancellation` off-chain.
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
