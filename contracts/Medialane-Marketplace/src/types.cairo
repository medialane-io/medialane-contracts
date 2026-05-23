//! Order types for the Medialane marketplace.
//!
//! An order is the generic 1+1 `(offer, consideration)` shape from the platform
//! architecture (`01 §V`, `06 §II`) — a subset of Seaport. It covers fixed-price
//! NFT sales, single-NFT bids, and ERC-20↔ERC-721 swaps.
//!
//! Orders are SNIP-12 signed off-chain and registered on-chain. There is no
//! `nonce`: replay protection is the order-hash status map plus an unordered
//! consumed-fulfillment-hash map, and per-order uniqueness is `salt`. Dropping
//! the sequential nonce is review finding F1.

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin_utils::snip12::StructHash;
use starknet::ContractAddress;
use crate::utils::{
    CANCELLATION_TYPE_HASH, CONSIDERATION_ITEM_TYPE_HASH, FULFILLMENT_1155_TYPE_HASH,
    FULFILLMENT_TYPE_HASH, OFFER_ITEM_TYPE_HASH, ORDER_PARAMETERS_TYPE_HASH,
};

/// The asset standard an order leg moves. No `NATIVE` variant — on Starknet
/// STRK and ETH are ordinary ERC-20s, named by contract address in the order.
#[derive(Drop, Copy, Serde, PartialEq)]
pub enum ItemType {
    ERC20,
    ERC721,
    ERC1155,
}

/// The offered side of an order.
///
/// `item_type` is carried as a SNIP-12 shortstring felt (`'ERC20'` | `'ERC721'`
/// | `'ERC1155'`) — see `ItemType` for the typed form used in contract logic.
#[derive(Drop, Copy, Serde, PartialEq, Hash, starknet::Store)]
pub struct OfferItem {
    pub item_type: felt252,
    pub token: ContractAddress,
    /// Token id for ERC-721/ERC-1155; `0` for ERC-20.
    pub token_id: felt252,
    /// ERC-20 token amount, `1` for ERC-721, or unit quantity for ERC-1155.
    pub amount: felt252,
}

/// The demanded side of an order — an offered item plus the address that
/// receives it when the order is fulfilled.
#[derive(Drop, Copy, Serde, PartialEq, Hash, starknet::Store)]
pub struct ConsiderationItem {
    pub item_type: felt252,
    pub token: ContractAddress,
    pub token_id: felt252,
    pub amount: felt252,
    pub recipient: ContractAddress,
}

/// The signed order. Hashed via SNIP-12 to produce the canonical `order_hash`.
#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderParameters {
    pub offerer: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub start_time: felt252,
    pub end_time: felt252,
    /// Per-order uniqueness — two otherwise-identical orders differ by salt.
    pub salt: felt252,
}

/// A signed intent to fulfill a registered order. `salt` makes each fulfillment
/// intent unique, so the contract records consumed fulfillment hashes for
/// unordered replay protection — no sequential nonce (F1).
#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderFulfillment {
    pub order_hash: felt252,
    pub fulfiller: ContractAddress,
    pub salt: felt252,
}

/// A signed intent to cancel a registered order.
#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderCancellation {
    pub order_hash: felt252,
    pub offerer: ContractAddress,
    pub salt: felt252,
}

/// Lifecycle status of a registered order hash.
#[derive(Drop, Copy, Serde, PartialEq, Default, starknet::Store)]
pub enum OrderStatus {
    /// Never registered.
    #[default]
    None,
    /// Registered and live.
    Created,
    /// Matched and settled.
    Filled,
    /// Cancelled by the offerer.
    Cancelled,
}

/// Calldata wrapper: an order's parameters plus the offerer's SNIP-12 signature.
#[derive(Drop, Serde)]
pub struct Order {
    pub parameters: OrderParameters,
    pub signature: Array<felt252>,
}

/// Calldata wrapper for the `fulfill_order` entrypoint.
#[derive(Drop, Serde)]
pub struct FulfillmentRequest {
    pub fulfillment: OrderFulfillment,
    pub signature: Array<felt252>,
}

/// Calldata wrapper for the `cancel_order` entrypoint.
#[derive(Drop, Serde)]
pub struct CancelRequest {
    pub cancellation: OrderCancellation,
    pub signature: Array<felt252>,
}

/// ERC-1155 fulfillment intent — carries `quantity` so each partial fill is a
/// distinct signed intent and consumed-hash replay (F1) actually does work.
#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderFulfillment1155 {
    pub order_hash: felt252,
    pub fulfiller: ContractAddress,
    pub quantity: felt252,
    pub salt: felt252,
}

#[derive(Drop, Serde)]
pub struct FulfillmentRequest1155 {
    pub fulfillment: OrderFulfillment1155,
    pub signature: Array<felt252>,
}

/// The on-chain record written when an order is registered.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct OrderDetails {
    pub offerer: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub start_time: u64,
    pub end_time: u64,
    pub order_status: OrderStatus,
}

/// On-chain record for an ERC-1155 marketplace order. Carries `total_amount`
/// and `remaining_amount` so the same `Created` order can be partially filled
/// across many fulfillments until it's fully consumed → `Filled`.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct OrderDetails1155 {
    pub offerer: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub start_time: u64,
    pub end_time: u64,
    pub order_status: OrderStatus,
    pub total_amount: u256,
    pub remaining_amount: u256,
}

// ─── ItemType ↔ SNIP-12 shortstring conversions ──────────────────────────────

pub impl ItemTypeIntoFelt252 of Into<ItemType, felt252> {
    fn into(self: ItemType) -> felt252 {
        match self {
            ItemType::ERC20 => 'ERC20',
            ItemType::ERC721 => 'ERC721',
            ItemType::ERC1155 => 'ERC1155',
        }
    }
}

pub impl Felt252TryIntoItemType of TryInto<felt252, ItemType> {
    fn try_into(self: felt252) -> Option<ItemType> {
        if self == 'ERC20' {
            Option::Some(ItemType::ERC20)
        } else if self == 'ERC721' {
            Option::Some(ItemType::ERC721)
        } else if self == 'ERC1155' {
            Option::Some(ItemType::ERC1155)
        } else {
            Option::None
        }
    }
}

// ─── SNIP-12 StructHash implementations ──────────────────────────────────────

pub impl OfferItemHashImpl of StructHash<OfferItem> {
    fn hash_struct(self: @OfferItem) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(OFFER_ITEM_TYPE_HASH).update_with(*self).finalize()
    }
}

pub impl ConsiderationItemHashImpl of StructHash<ConsiderationItem> {
    fn hash_struct(self: @ConsiderationItem) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CONSIDERATION_ITEM_TYPE_HASH).update_with(*self).finalize()
    }
}

pub impl OrderParametersHashImpl of StructHash<OrderParameters> {
    fn hash_struct(self: @OrderParameters) -> felt252 {
        let mut hash_state = PoseidonTrait::new();
        hash_state = hash_state.update_with(ORDER_PARAMETERS_TYPE_HASH);
        hash_state = hash_state.update_with(*self.offerer);
        hash_state = hash_state.update_with(self.offer.hash_struct());
        hash_state = hash_state.update_with(self.consideration.hash_struct());
        hash_state = hash_state.update_with(*self.start_time);
        hash_state = hash_state.update_with(*self.end_time);
        hash_state = hash_state.update_with(*self.salt);
        hash_state.finalize()
    }
}

pub impl OrderFulfillmentHashImpl of StructHash<OrderFulfillment> {
    fn hash_struct(self: @OrderFulfillment) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(FULFILLMENT_TYPE_HASH).update_with(*self).finalize()
    }
}

pub impl OrderCancellationHashImpl of StructHash<OrderCancellation> {
    fn hash_struct(self: @OrderCancellation) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CANCELLATION_TYPE_HASH).update_with(*self).finalize()
    }
}

pub impl OrderFulfillment1155HashImpl of StructHash<OrderFulfillment1155> {
    fn hash_struct(self: @OrderFulfillment1155) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(FULFILLMENT_1155_TYPE_HASH).update_with(*self).finalize()
    }
}
