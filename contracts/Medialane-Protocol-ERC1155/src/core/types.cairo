use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin_utils::snip12::StructHash;
use starknet::ContractAddress;
use crate::core::utils::*;

#[derive(Debug, Drop, Copy, Serde, PartialEq, Hash, starknet::Store)]
pub enum ItemType {
    #[default]
    NATIVE,
    ERC20,
    ERC721,
    ERC1155,
}

impl Felt252TryIntoItemType of TryInto<felt252, ItemType> {
    fn try_into(self: felt252) -> Option<ItemType> {
        if self == 'NATIVE' {
            Option::Some(ItemType::NATIVE)
        } else if self == 'ERC20' {
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

#[derive(Debug, Drop, Copy, Serde, PartialEq, Hash, starknet::Store)]
pub struct OfferItem {
    pub item_type: felt252,
    pub token: ContractAddress,
    pub identifier_or_criteria: felt252,
    pub start_amount: felt252,
    pub end_amount: felt252,
}

impl OfferItemHashImpl of StructHash<OfferItem> {
    fn hash_struct(self: @OfferItem) -> felt252 {
        PoseidonTrait::new().update_with(OFFER_ITEM_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Debug, Drop, Copy, Serde, Hash, PartialEq, starknet::Store)]
pub struct ConsiderationItem {
    pub item_type: felt252,
    pub token: ContractAddress,
    pub identifier_or_criteria: felt252,
    pub start_amount: felt252,
    pub end_amount: felt252,
    pub recipient: ContractAddress,
}

impl ConsiderationItemHashImpl of StructHash<ConsiderationItem> {
    fn hash_struct(self: @ConsiderationItem) -> felt252 {
        PoseidonTrait::new().update_with(CONSIDERATION_ITEM_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Debug, Drop, Clone, Copy, Serde, Hash)]
pub struct OrderParameters {
    pub offerer: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub start_time: felt252,
    pub end_time: felt252,
    pub salt: felt252,
    pub nonce: felt252,
}

impl OrderParametersHashImpl of StructHash<OrderParameters> {
    fn hash_struct(self: @OrderParameters) -> felt252 {
        let mut hash_state = PoseidonTrait::new();
        hash_state = hash_state.update_with(ORDER_PARAMETERS_TYPE_HASH);
        hash_state = hash_state.update_with(*self.offerer);
        hash_state = hash_state.update_with(self.offer.hash_struct());
        hash_state = hash_state.update_with(self.consideration.hash_struct());
        hash_state = hash_state.update_with(*self.start_time);
        hash_state = hash_state.update_with(*self.end_time);
        hash_state = hash_state.update_with(*self.salt);
        hash_state = hash_state.update_with(*self.nonce);
        hash_state.finalize()
    }
}

#[derive(Debug, Copy, Drop, Serde, starknet::Store)]
pub struct OrderDetails {
    pub offerer: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub start_time: u64,
    pub end_time: u64,
    pub order_status: OrderStatus,
    pub total_amount: felt252,
    pub remaining_amount: felt252,
}

#[derive(Drop, Clone, Copy, Serde, Hash)]
pub struct OrderFulfillment {
    pub order_hash: felt252,
    pub fulfiller: ContractAddress,
    pub quantity: felt252,
    pub nonce: felt252,
}

impl OrderFulfillmentHashImpl of StructHash<OrderFulfillment> {
    fn hash_struct(self: @OrderFulfillment) -> felt252 {
        let mut hash_state = PoseidonTrait::new();
        hash_state = hash_state.update_with(FULFILLMENT_TYPE_HASH);
        hash_state = hash_state.update_with(*self.order_hash);
        hash_state = hash_state.update_with(*self.fulfiller);
        hash_state = hash_state.update_with(*self.quantity);
        hash_state = hash_state.update_with(*self.nonce);
        hash_state.finalize()
    }
}

#[derive(Debug, Drop, Clone, Copy, Serde, Hash)]
pub struct OrderCancellation {
    pub order_hash: felt252,
    pub offerer: ContractAddress,
    pub nonce: felt252,
}

impl OrderCancellationHashImpl of StructHash<OrderCancellation> {
    fn hash_struct(self: @OrderCancellation) -> felt252 {
        let mut hash_state = PoseidonTrait::new();
        hash_state = hash_state.update_with(CANCELATION_TYPE_HASH);
        hash_state = hash_state.update_with(*self.order_hash);
        hash_state = hash_state.update_with(*self.offerer);
        hash_state = hash_state.update_with(*self.nonce);
        hash_state.finalize()
    }
}

#[derive(Drop, Serde)]
pub struct Order {
    pub parameters: OrderParameters,
    pub signature: Array<felt252>,
}

#[derive(Drop, Serde)]
pub struct FulfillmentRequest {
    pub fulfillment: OrderFulfillment,
    pub signature: Array<felt252>,
}

#[derive(Drop, Serde)]
pub struct CancelRequest {
    pub cancelation: OrderCancellation,
    pub signature: Array<felt252>,
}

#[derive(Drop, Debug, Copy, Serde, starknet::Store, PartialEq)]
pub enum OrderStatus {
    #[default]
    None,
    Created,
    Filled,
    Cancelled,
}

