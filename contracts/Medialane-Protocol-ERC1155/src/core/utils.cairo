pub const ORDER_PARAMETERS_TYPE_HASH: felt252 = selector!(
    "\"OrderParameters\"(\"offerer\":\"ContractAddress\",\"offer\":\"OfferItem\",\"consideration\":\"ConsiderationItem\",\"start_time\":\"felt\",\"end_time\":\"felt\",\"salt\":\"felt\",\"nonce\":\"felt\")\"ConsiderationItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"start_amount\":\"felt\",\"end_amount\":\"felt\",\"recipient\":\"ContractAddress\")\"OfferItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"start_amount\":\"felt\",\"end_amount\":\"felt\")",
);

pub const FULFILLMENT_TYPE_HASH: felt252 = selector!(
    "\"OrderFulfillment\"(\"order_hash\":\"felt\",\"fulfiller\":\"ContractAddress\",\"quantity\":\"felt\",\"nonce\":\"felt\")",
);

pub const CANCELATION_TYPE_HASH: felt252 = selector!(
    "\"OrderCancellation\"(\"order_hash\":\"felt\",\"offerer\":\"ContractAddress\",\"nonce\":\"felt\")",
);

pub const OFFER_ITEM_TYPE_HASH: felt252 = selector!(
    "\"OfferItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"start_amount\":\"felt\",\"end_amount\":\"felt\")",
);

pub const CONSIDERATION_ITEM_TYPE_HASH: felt252 = selector!(
    "\"ConsiderationItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"identifier_or_criteria\":\"felt\",\"start_amount\":\"felt\",\"end_amount\":\"felt\",\"recipient\":\"ContractAddress\")",
);

pub const IERC2981_ID: felt252 = 0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b;

pub fn felt_to_u64(value: felt252) -> u64 {
    let result: Option<u64> = value.try_into();
    assert(result.is_some(), 'Timestamp out of range');
    result.unwrap()
}

pub fn felt_to_u256(value: felt252) -> u256 {
    value.into()
}
