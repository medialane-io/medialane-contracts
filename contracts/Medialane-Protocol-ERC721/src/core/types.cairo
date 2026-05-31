use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin_utils::snip12::StructHash;
use starknet::ContractAddress;
use crate::core::utils::*;

/// Supported item kinds. The ERC721 venue trades an ERC721 against a payment
/// (NATIVE STRK or an ERC20). ERC1155 is intentionally NOT supported here — it
/// has its own venue. (Audit S3/F6.)
#[derive(Debug, Drop, Copy, Serde, PartialEq, Hash, starknet::Store)]
pub enum ItemType {
    #[default]
    NATIVE, // STRK
    ERC20,
    ERC721,
}

impl ItemTypeIntoFelt252 of Into<ItemType, felt252> {
    fn into(self: ItemType) -> felt252 {
        match self {
            ItemType::NATIVE => 'NATIVE',
            ItemType::ERC20 => 'ERC20',
            ItemType::ERC721 => 'ERC721',
        }
    }
}

impl Felt252TryIntoItemType of TryInto<felt252, ItemType> {
    fn try_into(self: felt252) -> Option<ItemType> {
        if self == 'NATIVE' {
            Option::Some(ItemType::NATIVE)
        } else if self == 'ERC20' {
            Option::Some(ItemType::ERC20)
        } else if self == 'ERC721' {
            Option::Some(ItemType::ERC721)
        } else {
            Option::None
        }
    }
}

/// A single fixed-price item. `amount` is the quantity (1 for ERC721, the wei
/// amount for NATIVE/ERC20). There is no separate end_amount — fixed price only
/// (audit F4: Dutch interpolation lives in the future auction venue).
///
/// `identifier_or_criteria` carries the ERC721 `token_id`. Because the order is
/// SNIP-12 signed, it is a `felt252`: token IDs must fit in a felt (< 2^252).
/// Collections using IDs at/above 2^252 cannot be traded on this venue.
#[derive(Debug, Drop, Copy, Serde, PartialEq, Hash, starknet::Store)]
pub struct OfferItem {
    pub item_type: felt252,
    pub token: ContractAddress,
    pub identifier_or_criteria: felt252,
    pub amount: felt252,
}

impl OfferItemHashImpl of StructHash<OfferItem> {
    fn hash_struct(self: @OfferItem) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(OFFER_ITEM_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Debug, Drop, Copy, Serde, Hash, PartialEq, starknet::Store)]
pub struct ConsiderationItem {
    pub item_type: felt252,
    pub token: ContractAddress,
    pub identifier_or_criteria: felt252,
    pub amount: felt252,
    pub recipient: ContractAddress,
}

impl ConsiderationItemHashImpl of StructHash<ConsiderationItem> {
    fn hash_struct(self: @ConsiderationItem) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CONSIDERATION_ITEM_TYPE_HASH).update_with(*self).finalize()
    }
}

/// The signed order.
/// - `marketplace`: binds the order to one deployed contract (audit S1). Asserted
///   `== get_contract_address()` at registration, so a signature for deployment N
///   cannot be replayed on deployment N+1.
/// - `royalty_max_bps`: seller-signed cap on the EIP-2981 royalty paid at fill
///   (audit F1/F8). The economic split is committed at signing.
/// - `counter`: the offerer's bulk-cancel epoch (audit F2). An order is only valid
///   while `counter == get_counter(offerer)`; incrementing it invalidates all the
///   offerer's outstanding orders at once. Replaces the sequential nonce.
/// - `salt`: per-order uniqueness so two economically-identical orders hash
///   distinctly. Client must randomize it.
#[derive(Debug, Drop, Clone, Copy, Serde, Hash)]
pub struct OrderParameters {
    pub offerer: ContractAddress,
    pub marketplace: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub royalty_max_bps: felt252,
    pub start_time: felt252,
    pub end_time: felt252,
    pub salt: felt252,
    pub counter: felt252,
}

impl OrderParametersHashImpl of StructHash<OrderParameters> {
    fn hash_struct(self: @OrderParameters) -> felt252 {
        let mut hash_state = PoseidonTrait::new();
        hash_state = hash_state.update_with(ORDER_PARAMETERS_TYPE_HASH);
        hash_state = hash_state.update_with(*self.offerer);
        hash_state = hash_state.update_with(*self.marketplace);
        hash_state = hash_state.update_with(self.offer.hash_struct());
        hash_state = hash_state.update_with(self.consideration.hash_struct());
        hash_state = hash_state.update_with(*self.royalty_max_bps);
        hash_state = hash_state.update_with(*self.start_time);
        hash_state = hash_state.update_with(*self.end_time);
        hash_state = hash_state.update_with(*self.salt);
        hash_state = hash_state.update_with(*self.counter);
        hash_state.finalize()
    }
}

#[derive(Debug, Drop, Clone, Copy, Serde, Hash)]
pub struct OrderCancellation {
    pub order_hash: felt252,
    pub offerer: ContractAddress,
}

impl OrderCancellationHashImpl of StructHash<OrderCancellation> {
    fn hash_struct(self: @OrderCancellation) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CANCELATION_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Drop, Serde)]
pub struct Order {
    pub parameters: OrderParameters,
    pub signature: Array<felt252>,
}

#[derive(Drop, Serde)]
pub struct CancelRequest {
    pub cancelation: OrderCancellation,
    pub signature: Array<felt252>,
}

/// Stored order record. No `fulfiller` field (audit C5) and no nonce.
#[derive(Debug, Copy, Drop, Serde, starknet::Store)]
pub struct OrderDetails {
    pub offerer: ContractAddress,
    pub offer: OfferItem,
    pub consideration: ConsiderationItem,
    pub royalty_max_bps: felt252,
    pub start_time: u64,
    pub end_time: u64,
    pub order_status: OrderStatus,
}

#[derive(Drop, Debug, Copy, Serde, starknet::Store, PartialEq)]
pub enum OrderStatus {
    #[default]
    None,
    Created,
    Filled,
    Cancelled,
}

#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use super::*;

    fn addr(v: felt252) -> ContractAddress {
        v.try_into().unwrap()
    }

    fn sample_order(marketplace: felt252) -> OrderParameters {
        OrderParameters {
            offerer: addr(0x111),
            marketplace: addr(marketplace),
            offer: OfferItem {
                item_type: 'ERC721', token: addr(0x721), identifier_or_criteria: 7, amount: 1,
            },
            consideration: ConsiderationItem {
                item_type: 'ERC20',
                token: addr(0x20),
                identifier_or_criteria: 0,
                amount: 1000000,
                recipient: addr(0x111),
            },
            royalty_max_bps: 1000,
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 42,
            counter: 0,
        }
    }

    #[test]
    fn test_order_hash_is_deterministic() {
        let a = sample_order(0xaaa);
        assert!(a.hash_struct() == a.hash_struct(), "hash must be deterministic");
    }

    #[test]
    fn test_order_hash_binds_marketplace() {
        // Two orders identical except for the marketplace (deployment) they target.
        // The hash MUST differ, or a signature is replayable across deployments (S1).
        let on_deploy_a = sample_order(0xaaa);
        let on_deploy_b = sample_order(0xbbb);
        assert!(
            on_deploy_a.hash_struct() != on_deploy_b.hash_struct(),
            "order hash must bind the marketplace address",
        );
    }
}
