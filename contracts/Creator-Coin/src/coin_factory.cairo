/// CoinFactory — permissionless, ownerless, non-custodial launcher for Creator Coins.
///
/// One atomic `launch`: deploy a fixed-supply ERC-20, deposit the full supply into an
/// Ekubo pool at the creator-set price, run a <=10% founder buyback paid in the chosen
/// quote token, and hand the bought coins AND the LP position to the creator. The
/// platform holds nothing afterward. No admin, no setters, no fee (00 §2/§12). The
/// <=10% cap is the only on-chain guarantee, enforced as a post-buyback assertion.
#[starknet::contract]
pub mod CoinFactory {
    use starknet::{ClassHash, ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::syscalls::deploy_syscall;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry,
    };
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use creator_coin::interfaces::ICoinFactory::ICoinFactory;
    use creator_coin::interfaces::IExchangeAdapter::{
        IExchangeAdapterDispatcher, IExchangeAdapterDispatcherTrait, TickParams,
    };
    use creator_coin::types::CoinRecord;
    use creator_coin::events::CoinLaunched;

    /// Founder buyback may take at most 10% of supply.
    const MAX_ALLOCATION_BPS: u16 = 1000;
    const BPS_DENOMINATOR: u256 = 10000;

    #[storage]
    struct Storage {
        creator_coin_class_hash: ClassHash,
        exchange_adapter: ContractAddress,
        last_coin_id: u256,
        coins: Map<u256, CoinRecord>,
        creator_coin_count: Map<ContractAddress, u32>,
        creator_coins: Map<(ContractAddress, u32), u256>,
        coin_id_of: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CoinLaunched: CoinLaunched,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        creator_coin_class_hash: ClassHash,
        exchange_adapter: ContractAddress,
    ) {
        self.creator_coin_class_hash.write(creator_coin_class_hash);
        self.exchange_adapter.write(exchange_adapter);
    }

    #[abi(embed_v0)]
    impl CoinFactoryImpl of ICoinFactory<ContractState> {
        fn launch(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            total_supply: u256,
            quote_token: ContractAddress,
            creator_allocation_bps: u16,
            buyback_quote_amount: u256,
            ticks: TickParams,
        ) -> (ContractAddress, felt252) {
            assert(name.len() > 0, 'Name empty');
            assert(total_supply > 0, 'Supply zero');
            assert(creator_allocation_bps <= MAX_ALLOCATION_BPS, 'Allocation too high');

            let creator = get_caller_address();
            let next_id = self.last_coin_id.read() + 1;

            // 1. Deploy the coin; full supply mints to the factory, creator recorded.
            let factory_addr = starknet::get_contract_address();
            let mut calldata: Array<felt252> = array![];
            (name.clone(), symbol.clone(), total_supply, factory_addr, creator)
                .serialize(ref calldata);
            let (coin_address, _) = deploy_syscall(
                self.creator_coin_class_hash.read(),
                next_id.try_into().unwrap(),
                calldata.span(),
                false,
            )
                .unwrap();

            // 2. Move the full supply + the creator's buyback quote to the adapter.
            let adapter_addr = self.exchange_adapter.read();
            IERC20Dispatcher { contract_address: coin_address }
                .transfer(adapter_addr, total_supply);
            if buyback_quote_amount > 0 {
                IERC20Dispatcher { contract_address: quote_token }
                    .transfer_from(creator, adapter_addr, buyback_quote_amount);
            }

            // 3. Adapter deposits the supply, runs the buyback, and hands the bought
            //    coins + the LP position to the creator.
            let adapter = IExchangeAdapterDispatcher { contract_address: adapter_addr };
            let result = adapter
                .launch(
                    coin_address, quote_token, total_supply, buyback_quote_amount, creator, ticks,
                );

            // 4. Enforce the cap on what the buyback actually delivered.
            let cap: u256 = total_supply * creator_allocation_bps.into() / BPS_DENOMINATOR;
            assert(result.coins_bought <= cap, 'Buyback over cap');

            // 5. Record + index + emit.
            self.last_coin_id.write(next_id);
            self.coin_id_of.entry(coin_address).write(next_id);
            self
                .coins
                .entry(next_id)
                .write(
                    CoinRecord {
                        coin_id: next_id,
                        coin_address,
                        creator,
                        quote_token,
                        total_supply,
                        creator_allocation_bps,
                        pool_id: result.pool_id,
                        created_at: get_block_timestamp(),
                    },
                );
            let idx = self.creator_coin_count.entry(creator).read();
            self.creator_coins.entry((creator, idx)).write(next_id);
            self.creator_coin_count.entry(creator).write(idx + 1);

            self
                .emit(
                    CoinLaunched {
                        coin_address,
                        creator,
                        coin_id: next_id,
                        quote_token,
                        total_supply,
                        creator_allocation_bps,
                        coins_bought: result.coins_bought,
                        pool_id: result.pool_id,
                        timestamp: get_block_timestamp(),
                    },
                );

            (coin_address, result.pool_id)
        }

        fn get_coin(self: @ContractState, coin_id: u256) -> CoinRecord {
            self.coins.entry(coin_id).read()
        }
        fn get_last_coin_id(self: @ContractState) -> u256 {
            self.last_coin_id.read()
        }
        fn get_creator_coin_count(self: @ContractState, creator: ContractAddress) -> u32 {
            self.creator_coin_count.entry(creator).read()
        }
        fn get_creator_coin_ids(
            self: @ContractState, creator: ContractAddress, start: u32, count: u32,
        ) -> Array<u256> {
            let total = self.creator_coin_count.entry(creator).read();
            let mut result: Array<u256> = array![];
            let end = start + count;
            let mut i = start;
            loop {
                if i >= end || i >= total {
                    break;
                }
                result.append(self.creator_coins.entry((creator, i)).read());
                i += 1;
            };
            result
        }
        fn get_creator_coin_class_hash(self: @ContractState) -> ClassHash {
            self.creator_coin_class_hash.read()
        }
    }
}
