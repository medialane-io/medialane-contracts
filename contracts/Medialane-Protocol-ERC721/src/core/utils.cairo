// SNIP-12 type hashes, computed via selector!() over the canonical type strings
// (never hardcoded hex). Field names/order MUST match the structs in types.cairo
// and the off-chain SDK typed-data, or signatures will not validate.

pub const OFFER_ITEM_TYPE_HASH: felt252 = selector!(
    "\"OfferItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"amount\":\"felt\")",
);

pub const CONSIDERATION_ITEM_TYPE_HASH: felt252 = selector!(
    "\"ConsiderationItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"amount\":\"felt\",\"recipient\":\"ContractAddress\")",
);

pub const ORDER_PARAMETERS_TYPE_HASH: felt252 = selector!(
    "\"OrderParameters\"(\"offerer\":\"ContractAddress\",\"marketplace\":\"ContractAddress\",\"offer\":\"OfferItem\",\"consideration\":\"ConsiderationItem\",\"royalty_max_bps\":\"felt\",\"start_time\":\"felt\",\"end_time\":\"felt\",\"salt\":\"felt\",\"counter\":\"felt\")\"ConsiderationItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"amount\":\"felt\",\"recipient\":\"ContractAddress\")\"OfferItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"amount\":\"felt\")",
);

pub const CANCELATION_TYPE_HASH: felt252 = selector!(
    "\"OrderCancellation\"(\"order_hash\":\"felt\",\"offerer\":\"ContractAddress\")",
);

pub fn felt_to_u64(value: felt252) -> u64 {
    let result: Option<u64> = value.try_into();
    assert(result.is_some(), 'Timestamp out of range');
    result.unwrap()
}

pub fn felt_to_u256(value: felt252) -> u256 {
    value.into()
}
