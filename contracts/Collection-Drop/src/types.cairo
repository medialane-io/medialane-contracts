use starknet::ContractAddress;

/// A drop's sale terms, fixed at creation.
#[derive(Drop, Copy, Serde, PartialEq, Debug, starknet::Store)]
pub struct SaleTerms {
    /// Unix seconds when claims open; 0 = open from creation.
    pub start_time: u64,
    /// Unix seconds after which claims close; 0 = never closes.
    pub end_time: u64,
    /// Price per token in `payment_token` units; 0 = free.
    pub price: u256,
    /// ERC-20 used for payment; zero when the drop is free.
    pub payment_token: ContractAddress,
    /// Tokens a wallet may claim in total; 0 = unlimited.
    pub max_per_wallet: u256,
}
