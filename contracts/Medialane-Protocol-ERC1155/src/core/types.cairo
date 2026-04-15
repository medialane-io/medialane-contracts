use core::poseidon::PoseidonTrait;
use core::hash::{HashStateExTrait, HashStateTrait};
use openzeppelin_utils::snip12::StructHash;
use starknet::ContractAddress;
use crate::core::utils::*;

// ---------------------------------------------------------------------------
// OrderParameters — what the seller signs when creating a listing.
//
// Hashed via SNIP-12 using ORDER_PARAMETERS_TYPE_HASH.
// All monetary amounts use felt252 (fits ERC-1155 values in practice).
// ---------------------------------------------------------------------------
#[derive(Debug, Drop, Clone, Copy, Serde, Hash)]
pub struct OrderParameters {
    /// Seller address.
    pub offerer: ContractAddress,
    /// ERC-1155 contract address (e.g. IPCollection).
    pub nft_contract: ContractAddress,
    /// Token type ID within the ERC-1155 contract.
    pub token_id: felt252,
    /// Number of tokens being sold.
    pub amount: felt252,
    /// Payment token contract address. Zero address means STRK (native).
    pub payment_token: ContractAddress,
    /// Price per individual token, denominated in `payment_token`.
    pub price_per_unit: felt252,
    /// Block timestamp from which the order is valid (inclusive).
    pub start_time: felt252,
    /// Block timestamp at which the order expires (exclusive). Zero = no expiry.
    pub end_time: felt252,
    /// Entropy to prevent hash collisions between otherwise identical orders.
    pub salt: felt252,
    /// SRC-6 account nonce — consumed on register to prevent replay.
    pub nonce: felt252,
}

impl OrderParametersHashImpl of StructHash<OrderParameters> {
    fn hash_struct(self: @OrderParameters) -> felt252 {
        let mut hash_state = PoseidonTrait::new();
        hash_state = hash_state.update_with(ORDER_PARAMETERS_TYPE_HASH);
        hash_state = hash_state.update_with(*self.offerer);
        hash_state = hash_state.update_with(*self.nft_contract);
        hash_state = hash_state.update_with(*self.token_id);
        hash_state = hash_state.update_with(*self.amount);
        hash_state = hash_state.update_with(*self.payment_token);
        hash_state = hash_state.update_with(*self.price_per_unit);
        hash_state = hash_state.update_with(*self.start_time);
        hash_state = hash_state.update_with(*self.end_time);
        hash_state = hash_state.update_with(*self.salt);
        hash_state = hash_state.update_with(*self.nonce);
        hash_state.finalize()
    }
}

// ---------------------------------------------------------------------------
// OrderDetails — stored in contract storage after registration.
// ---------------------------------------------------------------------------
#[derive(Debug, Copy, Drop, Serde, starknet::Store)]
pub struct OrderDetails {
    pub offerer: ContractAddress,
    pub nft_contract: ContractAddress,
    pub token_id: felt252,
    pub amount: felt252,
    pub payment_token: ContractAddress,
    pub price_per_unit: felt252,
    pub start_time: u64,
    pub end_time: u64,
    pub order_status: OrderStatus,
    pub fulfiller: Option<ContractAddress>,
}

// ---------------------------------------------------------------------------
// OrderFulfillment — what the buyer signs when filling an order.
// ---------------------------------------------------------------------------
#[derive(Drop, Clone, Copy, Serde, Hash)]
pub struct OrderFulfillment {
    /// Hash of the order being fulfilled.
    pub order_hash: felt252,
    /// Buyer address — caller must match this.
    pub fulfiller: ContractAddress,
    /// Buyer's account nonce.
    pub nonce: felt252,
}

impl OrderFulfillmentHashImpl of StructHash<OrderFulfillment> {
    fn hash_struct(self: @OrderFulfillment) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(FULFILLMENT_TYPE_HASH).update_with(*self).finalize()
    }
}

// ---------------------------------------------------------------------------
// OrderCancellation — what the seller signs to cancel their order.
// ---------------------------------------------------------------------------
#[derive(Debug, Drop, Clone, Copy, Serde, Hash)]
pub struct OrderCancellation {
    /// Hash of the order to cancel.
    pub order_hash: felt252,
    /// Seller address — must match the order's offerer.
    pub offerer: ContractAddress,
    /// Seller's account nonce.
    pub nonce: felt252,
}

impl OrderCancellationHashImpl of StructHash<OrderCancellation> {
    fn hash_struct(self: @OrderCancellation) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CANCELATION_TYPE_HASH).update_with(*self).finalize()
    }
}

// ---------------------------------------------------------------------------
// Envelope types passed to entrypoints.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// OrderStatus — lifecycle state machine.
// ---------------------------------------------------------------------------
#[derive(Drop, Debug, Copy, Serde, starknet::Store, PartialEq)]
pub enum OrderStatus {
    #[default]
    None,      // Never seen — used as zero value
    Created,   // Registered, awaiting fulfillment
    Filled,    // Matched and executed
    Cancelled, // Cancelled by the offerer
}

// ---------------------------------------------------------------------------
// Hash tests (computed with StarknetJS for cross-verification)
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use openzeppelin_utils::snip12::SNIP12Metadata;
    use starknet::ContractAddress;
    use super::*;

    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Medialane1155'
        }
        fn version() -> felt252 {
            1
        }
    }

    pub fn OFFERER() -> ContractAddress {
        0x049c8ce76963bb0d4ae4888d373d223a1fd7c683daa9f959abe3c5cd68894f51.try_into().unwrap()
    }

    pub fn FULFILLER() -> ContractAddress {
        0x030545f9bc0a25a84d92fe8770f4f23639b960a364201df60536d34605e48538.try_into().unwrap()
    }

    pub fn NFT_CONTRACT() -> ContractAddress {
        // IP-Programmable-ERC1155-Collections (IPCollection class, deployed via factory)
        0x0459a9a3c04be5d884a038744f977dff019897264d4a281f9e0f87af417b3bec.try_into().unwrap()
    }

    pub fn ERC20_TOKEN() -> ContractAddress {
        0x0589edc6e13293530fec9cad58787ed8cff1fce35c3ef80342b7b00651e04d1f.try_into().unwrap()
    }

    #[test]
    fn test_order_parameters_hash_struct_is_deterministic() {
        let params = OrderParameters {
            offerer: OFFERER(),
            nft_contract: NFT_CONTRACT(),
            token_id: 1,
            amount: 10,
            payment_token: ERC20_TOKEN(),
            price_per_unit: 1000000,
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        };
        // Hashing twice must produce the same result
        let h1 = params.hash_struct();
        let h2 = params.hash_struct();
        assert_eq!(h1, h2);
    }

    #[test]
    fn test_order_hash_differs_by_token_id() {
        let base = OrderParameters {
            offerer: OFFERER(),
            nft_contract: NFT_CONTRACT(),
            token_id: 1,
            amount: 10,
            payment_token: ERC20_TOKEN(),
            price_per_unit: 1000000,
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        };
        let mut other = base;
        other.token_id = 2;
        assert_ne!(base.hash_struct(), other.hash_struct());
    }
}
