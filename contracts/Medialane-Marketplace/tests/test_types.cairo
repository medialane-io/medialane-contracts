use medialane_marketplace::types::{
    ItemType, OfferItem, ConsiderationItem, OrderParameters, OrderFulfillment, OrderCancellation,
};
use openzeppelin_utils::snip12::StructHash;
use starknet::ContractAddress;

fn offerer() -> ContractAddress { 0x1111.try_into().unwrap() }
fn fulfiller() -> ContractAddress { 0x2222.try_into().unwrap() }
fn nft_contract() -> ContractAddress { 0x3333.try_into().unwrap() }
fn currency() -> ContractAddress { 0x4444.try_into().unwrap() }

fn sample_offer() -> OfferItem {
    OfferItem { item_type: 'ERC721', token: nft_contract(), token_id: 7, amount: 1 }
}

fn sample_consideration() -> ConsiderationItem {
    ConsiderationItem {
        item_type: 'ERC20',
        token: currency(),
        token_id: 0,
        amount: 1_000_000,
        recipient: offerer(),
    }
}

fn sample_order(salt: felt252) -> OrderParameters {
    OrderParameters {
        offerer: offerer(),
        offer: sample_offer(),
        consideration: sample_consideration(),
        start_time: 1000,
        end_time: 2000,
        salt,
    }
}

#[test]
fn item_type_round_trips_through_felt() {
    let f: felt252 = ItemType::ERC721.into();
    let back: Option<ItemType> = f.try_into();
    assert!(back == Option::Some(ItemType::ERC721), "ERC721 should round-trip");

    let unknown: Option<ItemType> = 'NOPE'.try_into();
    assert!(unknown == Option::None, "unknown shortstring is rejected");
}

#[test]
fn order_hash_is_deterministic() {
    assert!(
        sample_order(123).hash_struct() == sample_order(123).hash_struct(),
        "same order should hash the same",
    );
}

#[test]
fn order_hash_changes_with_salt() {
    assert!(
        sample_order(1).hash_struct() != sample_order(2).hash_struct(),
        "different salt should change the hash",
    );
}

#[test]
fn order_hash_changes_with_offer_amount() {
    let a = sample_order(1);
    let b_offer = OfferItem { amount: 9_999, ..sample_offer() };
    let b = OrderParameters { offer: b_offer, ..sample_order(1) };
    assert!(a.hash_struct() != b.hash_struct(), "different amount should change the hash");
}

#[test]
fn fulfillment_hash_changes_with_salt() {
    let a = OrderFulfillment { order_hash: 0xabc, fulfiller: fulfiller(), salt: 1 };
    let b = OrderFulfillment { order_hash: 0xabc, fulfiller: fulfiller(), salt: 2 };
    assert!(a.hash_struct() != b.hash_struct(), "salt should change the fulfillment hash");
}

#[test]
fn cancellation_hash_includes_offerer() {
    let a = OrderCancellation { order_hash: 0xabc, offerer: offerer(), salt: 1 };
    let b = OrderCancellation { order_hash: 0xabc, offerer: fulfiller(), salt: 1 };
    assert!(a.hash_struct() != b.hash_struct(), "different offerer should change the hash");
}
