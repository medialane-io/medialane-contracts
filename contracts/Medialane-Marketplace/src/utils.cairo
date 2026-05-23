//! Type-hash constants for the SNIP-12 message encoding.
//!
//! Each is `selector!` of the canonical SNIP-12 type string. Changing a
//! struct's fields, names, or order changes its hash and invalidates every
//! signature against the old shape — which is the intended behavior of an
//! immutable contract.

pub const OFFER_ITEM_TYPE_HASH: felt252 = selector!(
    "\"OfferItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"token_id\":\"felt\",\"amount\":\"felt\")",
);

pub const CONSIDERATION_ITEM_TYPE_HASH: felt252 = selector!(
    "\"ConsiderationItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"token_id\":\"felt\",\"amount\":\"felt\",\"recipient\":\"ContractAddress\")",
);

// OrderParameters references the two item structs; SNIP-12 requires their
// definitions appended in alphabetical order (ConsiderationItem, OfferItem).
pub const ORDER_PARAMETERS_TYPE_HASH: felt252 = selector!(
    "\"OrderParameters\"(\"offerer\":\"ContractAddress\",\"offer\":\"OfferItem\",\"consideration\":\"ConsiderationItem\",\"start_time\":\"felt\",\"end_time\":\"felt\",\"salt\":\"felt\")\"ConsiderationItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"token_id\":\"felt\",\"amount\":\"felt\",\"recipient\":\"ContractAddress\")\"OfferItem\"(\"item_type\":\"shortstring\",\"token\":\"ContractAddress\",\"token_id\":\"felt\",\"amount\":\"felt\")",
);

pub const FULFILLMENT_TYPE_HASH: felt252 = selector!(
    "\"OrderFulfillment\"(\"order_hash\":\"felt\",\"fulfiller\":\"ContractAddress\",\"salt\":\"felt\")",
);

pub const FULFILLMENT_1155_TYPE_HASH: felt252 = selector!(
    "\"OrderFulfillment1155\"(\"order_hash\":\"felt\",\"fulfiller\":\"ContractAddress\",\"quantity\":\"felt\",\"salt\":\"felt\")",
);

pub const CANCELLATION_TYPE_HASH: felt252 = selector!(
    "\"OrderCancellation\"(\"order_hash\":\"felt\",\"offerer\":\"ContractAddress\",\"salt\":\"felt\")",
);
