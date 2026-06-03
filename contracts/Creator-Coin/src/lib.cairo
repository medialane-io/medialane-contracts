pub mod creator_coin;
pub mod coin_factory;
pub mod types;
pub mod events;
pub mod interfaces {
    pub mod ICreatorCoin;
    pub mod ICoinFactory;
    pub mod IExchangeAdapter;
}
// exchanges::ekubo_adapter is rewritten to the new launch interface in Task 5
// (real Ekubo deposit + buyback). Temporarily excluded so the MockExchange-tested
// launch logic compiles and runs first.
// pub mod exchanges {
//     pub mod ekubo_adapter;
// }
pub mod mocks {
    pub mod erc20;
    pub mod erc721;
    pub mod MockExchange;
}
