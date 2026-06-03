use starknet::ContractAddress;

/// Test hook to drive the factory's cap assertion.
#[starknet::interface]
pub trait IMockExchangeConfig<TState> {
    /// Set how many coins the next buyback "delivers".
    fn set_coins_bought(ref self: TState, amount: u256);
}

/// MockExchange — an in-memory IExchangeAdapter for unit tests.
///
/// It does not touch a real AMM. It records the amounts it received and returns a
/// *settable* `coins_bought` (so a test can drive the factory's cap assertion),
/// forwarding the bought coins to `creator` out of the supply the factory sent it.
/// The real adapter is `exchanges::ekubo_adapter`.
#[starknet::contract]
pub mod MockExchange {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use creator_coin::interfaces::IExchangeAdapter::{IExchangeAdapter, LaunchResult, TickParams};

    #[storage]
    struct Storage {
        last_coin_supply: u256,
        last_quote_in: u256,
        coins_bought: u256,
        next_position_id: u256,
    }

    #[abi(embed_v0)]
    impl ConfigImpl of super::IMockExchangeConfig<ContractState> {
        fn set_coins_bought(ref self: ContractState, amount: u256) {
            self.coins_bought.write(amount);
        }
    }

    #[abi(embed_v0)]
    impl MockExchangeImpl of IExchangeAdapter<ContractState> {
        fn launch(
            ref self: ContractState,
            coin: ContractAddress,
            quote: ContractAddress,
            coin_supply: u256,
            quote_in: u256,
            creator: ContractAddress,
            ticks: TickParams,
        ) -> LaunchResult {
            self.last_coin_supply.write(coin_supply);
            self.last_quote_in.write(quote_in);
            let bought = self.coins_bought.read();
            // Deliver the "bought" coins to the creator out of the supply we hold.
            if bought > 0 {
                IERC20Dispatcher { contract_address: coin }.transfer(creator, bought);
            }
            let pid = self.next_position_id.read() + 1;
            self.next_position_id.write(pid);
            LaunchResult { pool_id: 0xC01, position_id: pid, coins_bought: bought }
        }

        fn position_nft_address(self: @ContractState) -> ContractAddress {
            0.try_into().unwrap()
        }
    }
}
