/// CoinFactory — permissionless factory for Creator Coins.
///
/// Anyone can `create_coin` (a fixed-supply ERC-20 minted to them) and then
/// `launch_on_ekubo` to seed a locked-LP AMM pool. The factory is immutable and
/// ownerless (no admin, no setters, no fee — 00 §2/§12): the class hash, locker,
/// and exchange adapter are wired once at deploy. Anti-rug guarantees (capped
/// creator allocation, minimum lock) are enforced on-chain here.
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
    use creator_coin::interfaces::ILiquidityLock::{
        ILiquidityLockDispatcher, ILiquidityLockDispatcherTrait,
    };
    use creator_coin::types::CoinRecord;
    use creator_coin::events::CoinLaunched;

    /// Creator/team may keep at most 10% of supply; the rest seeds the pool.
    const MAX_ALLOCATION_BPS: u16 = 1000;
    /// Liquidity is locked for at least 180 days.
    const MIN_LOCK_DURATION: u64 = 15_552_000;
    const BPS_DENOMINATOR: u256 = 10000;

    #[storage]
    struct Storage {
        creator_coin_class_hash: ClassHash,
        liquidity_lock: ContractAddress,
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
        liquidity_lock: ContractAddress,
        exchange_adapter: ContractAddress,
    ) {
        self.creator_coin_class_hash.write(creator_coin_class_hash);
        self.liquidity_lock.write(liquidity_lock);
        self.exchange_adapter.write(exchange_adapter);
    }

    #[abi(embed_v0)]
    impl CoinFactoryImpl of ICoinFactory<ContractState> {
        fn create_coin(
            ref self: ContractState, name: ByteArray, symbol: ByteArray, total_supply: u256,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name empty');
            assert(total_supply > 0, 'Supply zero');
            let creator = get_caller_address();
            let next_id = self.last_coin_id.read() + 1;

            let mut calldata: Array<felt252> = array![];
            (name.clone(), symbol.clone(), total_supply, creator, creator).serialize(ref calldata);
            let (coin_address, _) = deploy_syscall(
                self.creator_coin_class_hash.read(),
                next_id.try_into().unwrap(),
                calldata.span(),
                false,
            )
                .unwrap();

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
                        quote_token: 0.try_into().unwrap(),
                        total_supply,
                        creator_allocation_bps: 0,
                        pool_id: 0,
                        lock_id: 0,
                        lock_expiry: 0,
                        created_at: get_block_timestamp(),
                    },
                );
            let idx = self.creator_coin_count.entry(creator).read();
            self.creator_coins.entry((creator, idx)).write(next_id);
            self.creator_coin_count.entry(creator).write(idx + 1);
            coin_address
        }

        fn launch_on_ekubo(
            ref self: ContractState,
            coin: ContractAddress,
            quote_token: ContractAddress,
            creator_allocation_bps: u16,
            seed_amount: u256,
            lock_duration: u64,
            ticks: TickParams,
        ) -> (felt252, u64) {
            // ── Guards (anti-rug; 00 §1) ────────────────────────────────────
            assert(creator_allocation_bps <= MAX_ALLOCATION_BPS, 'Allocation too high');
            assert(lock_duration >= MIN_LOCK_DURATION, 'Lock too short');
            assert(seed_amount > 0, 'Seed zero');

            let creator = get_caller_address();
            let coin_id = self.coin_id_of.entry(coin).read();
            assert(coin_id != 0, 'Unknown coin');
            let mut rec = self.coins.entry(coin_id).read();
            assert(rec.creator == creator, 'Not coin creator');
            assert(rec.pool_id == 0, 'Already launched');

            // ── Supply split: creator keeps allocation, pool gets the rest ──
            let creator_allocation: u256 = rec.total_supply
                * creator_allocation_bps.into()
                / BPS_DENOMINATOR;
            let pool_allocation: u256 = rec.total_supply - creator_allocation;
            assert(pool_allocation + creator_allocation == rec.total_supply, 'Supply invariant');

            let adapter_addr = self.exchange_adapter.read();
            // Pull pool coins + seed quote from creator into the adapter.
            IERC20Dispatcher { contract_address: coin }
                .transfer_from(creator, adapter_addr, pool_allocation);
            IERC20Dispatcher { contract_address: quote_token }
                .transfer_from(creator, adapter_addr, seed_amount);

            // Provision liquidity; adapter returns the LP position.
            let adapter = IExchangeAdapterDispatcher { contract_address: adapter_addr };
            let result = adapter
                .add_liquidity(coin, quote_token, pool_allocation, seed_amount, ticks);

            // Move the LP position into the locker and record the lock.
            let lock_addr = self.liquidity_lock.read();
            adapter.transfer_position(result.position_id, lock_addr);
            let nft_address = adapter.position_nft_address();
            let unlock_time = get_block_timestamp() + lock_duration;
            let lock_id = ILiquidityLockDispatcher { contract_address: lock_addr }
                .lock(coin, creator, nft_address, result.position_id, unlock_time);

            // Update record + emit.
            rec.quote_token = quote_token;
            rec.creator_allocation_bps = creator_allocation_bps;
            rec.pool_id = result.pool_id;
            rec.lock_id = lock_id;
            rec.lock_expiry = unlock_time;
            self.coins.entry(coin_id).write(rec.clone());

            self
                .emit(
                    CoinLaunched {
                        coin_address: coin,
                        creator,
                        coin_id,
                        quote_token,
                        total_supply: rec.total_supply,
                        creator_allocation_bps,
                        pool_id: result.pool_id,
                        lock_expiry: unlock_time,
                        timestamp: get_block_timestamp(),
                    },
                );

            (result.pool_id, lock_id)
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
