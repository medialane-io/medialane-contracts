/// MockExchange — an in-memory IExchangeAdapter for unit tests.
///
/// It does not touch a real AMM; it returns deterministic ids so the factory's
/// launch guards and bookkeeping are testable without Ekubo. The real adapter is
/// `exchanges::ekubo_adapter`. Withdraw is not exercised through this mock, so its
/// `position_nft_address` is a placeholder (zero).
#[starknet::contract]
pub mod MockExchange {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use creator_coin::interfaces::IExchangeAdapter::{IExchangeAdapter, LaunchResult, TickParams};

    #[storage]
    struct Storage {
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
            ticks: TickParams,
        ) -> LaunchResult {
            let pid = self.next_position_id.read() + 1;
            self.next_position_id.write(pid);
            LaunchResult { pool_id: 0xC01, position_id: pid }
        }

        fn transfer_position(ref self: ContractState, position_id: u256, to: ContractAddress) {}

        fn position_nft_address(self: @ContractState) -> ContractAddress {
            0.try_into().unwrap()
        }
    }
}
