/// MockExchange — an in-memory IExchangeAdapter for unit tests.
///
/// It does not touch a real AMM; it records the deposited amount and returns
/// deterministic ids so the factory's split + bookkeeping are testable without Ekubo.
/// The coins the factory sends it simply stay here (the test asserts the pool share
/// landed at the adapter). The real adapter is `exchanges::ekubo_adapter`.
#[starknet::contract]
pub mod MockExchange {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use creator_coin::interfaces::IExchangeAdapter::{IExchangeAdapter, LaunchResult, TickParams};

    #[storage]
    struct Storage {
        last_coin_amount: u256,
        next_position_id: u256,
    }

    #[abi(embed_v0)]
    impl MockExchangeImpl of IExchangeAdapter<ContractState> {
        fn add_liquidity(
            ref self: ContractState,
            coin: ContractAddress,
            quote: ContractAddress,
            coin_amount: u256,
            recipient: ContractAddress,
            ticks: TickParams,
        ) -> LaunchResult {
            self.last_coin_amount.write(coin_amount);
            let pid = self.next_position_id.read() + 1;
            self.next_position_id.write(pid);
            LaunchResult { pool_id: 0xC01, position_id: pid }
        }
    }
}
