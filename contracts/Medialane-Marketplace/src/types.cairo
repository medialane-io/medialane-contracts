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

use starknet::ContractAddress;

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
