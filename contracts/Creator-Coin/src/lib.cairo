pub mod creator_coin;
pub mod coin_factory;
pub mod liquidity_lock;
pub mod types;
pub mod events;
pub mod interfaces {
    pub mod ICreatorCoin;
    pub mod ICoinFactory;
    pub mod ILiquidityLock;
    pub mod IExchangeAdapter;
}
pub mod exchanges {
    pub mod ekubo_adapter;
}
pub mod mocks {
    pub mod erc20;
    pub mod erc721;
    pub mod MockExchange;
}
