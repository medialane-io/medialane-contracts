pub mod core {
    pub mod errors;
    pub mod events;
    pub mod interface;
    pub mod medialane;
    pub mod types;
    pub mod utils;
}

pub mod mocks {
    pub mod account;
    pub mod erc20;
    pub mod erc721;
    pub mod erc721_royalty;
    pub mod malicious;
}
