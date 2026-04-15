// SNIP-12 type hash for OrderParameters.
//
// Type string (human-readable):
//   "OrderParameters"(
//     "offerer":"ContractAddress",
//     "nft_contract":"ContractAddress",
//     "token_id":"felt",
//     "amount":"felt",
//     "payment_token":"ContractAddress",
//     "price_per_unit":"felt",
//     "start_time":"felt",
//     "end_time":"felt",
//     "salt":"felt",
//     "nonce":"felt"
//   )
pub const ORDER_PARAMETERS_TYPE_HASH: felt252 = selector!(
    "\"OrderParameters\"(\"offerer\":\"ContractAddress\",\"nft_contract\":\"ContractAddress\",\"token_id\":\"felt\",\"amount\":\"felt\",\"payment_token\":\"ContractAddress\",\"price_per_unit\":\"felt\",\"start_time\":\"felt\",\"end_time\":\"felt\",\"salt\":\"felt\",\"nonce\":\"felt\")"
);

// "OrderFulfillment"("order_hash":"felt","fulfiller":"ContractAddress","nonce":"felt")
pub const FULFILLMENT_TYPE_HASH: felt252 = selector!(
    "\"OrderFulfillment\"(\"order_hash\":\"felt\",\"fulfiller\":\"ContractAddress\",\"nonce\":\"felt\")"
);

// "OrderCancellation"("order_hash":"felt","offerer":"ContractAddress","nonce":"felt")
pub const CANCELATION_TYPE_HASH: felt252 = selector!(
    "\"OrderCancellation\"(\"order_hash\":\"felt\",\"offerer\":\"ContractAddress\",\"nonce\":\"felt\")"
);

/// ERC-2981 interface ID (from OZ Cairo v0.20.0)
pub const IERC2981_ID: felt252 = 0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b;

pub fn felt_to_u64(value: felt252) -> u64 {
    let result: Option<u64> = value.try_into();
    assert(result.is_some(), 'Timestamp out of range');
    result.unwrap()
}

pub fn felt_to_u256(value: felt252) -> u256 {
    value.into()
}
