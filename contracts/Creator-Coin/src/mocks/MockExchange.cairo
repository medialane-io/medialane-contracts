/// MockExchange — an in-memory IExchangeAdapter for unit tests.
///
/// It does not touch a real AMM; it records the amounts the factory sent and
/// returns deterministic pool/position ids, so the factory's launch guards and
/// bookkeeping are testable without Ekubo. The real adapter is `exchanges::ekubo_adapter`.
#[starknet::contract]
pub mod MockExchange {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use creator_coin::interfaces::IExchangeAdapter::{IExchangeAdapter, LaunchResult};

    #[storage]
    struct Storage {
        last_coin_amount: u256,
        last_quote_amount: u256,
        next_position_id: u256,
    }

    #[abi(embed_v0)]
    impl MockExchangeImpl of IExchangeAdapter<ContractState> {
        fn add_liquidity(
            ref self: ContractState,
            coin: ContractAddress,
            quote: ContractAddress,
            coin_amount: u256,
            quote_amount: u256,
        ) -> LaunchResult {
            self.last_coin_amount.write(coin_amount);
            self.last_quote_amount.write(quote_amount);
            let pid = self.next_position_id.read() + 1;
            self.next_position_id.write(pid);
            LaunchResult { pool_id: 0xC01, position_id: pid }
        }

        fn transfer_position(ref self: ContractState, position_id: u256, to: ContractAddress) {
            // no-op in the mock
        }
    }
}
