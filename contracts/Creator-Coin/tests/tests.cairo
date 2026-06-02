#[cfg(test)]
mod test {
    use creator_coin::interfaces::ICreatorCoin::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait,
    };
    use creator_coin::interfaces::ILiquidityLock::{
        ILiquidityLockDispatcher, ILiquidityLockDispatcherTrait,
    };
    use creator_coin::interfaces::ICoinFactory::{
        ICoinFactoryDispatcher, ICoinFactoryDispatcherTrait,
    };
    use creator_coin::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use creator_coin::mocks::erc721::{IMockERC721Dispatcher, IMockERC721DispatcherTrait};
    use creator_coin::interfaces::IExchangeAdapter::TickParams;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
        start_cheat_block_timestamp_global, stop_cheat_block_timestamp_global,
        start_cheat_caller_address_global, stop_cheat_caller_address_global,
    };
    use starknet::ContractAddress;

    // ── Test addresses ──────────────────────────────────────────────────────
    fn CREATOR() -> ContractAddress {
        0xC0FFEE.try_into().unwrap()
    }
    fn FAN() -> ContractAddress {
        0xFA11.try_into().unwrap()
    }
    fn COIN() -> ContractAddress {
        0xC01.try_into().unwrap()
    }
    fn ADMIN() -> ContractAddress {
        0xAD.try_into().unwrap()
    }

    fn default_ticks() -> TickParams {
        // The mock ignores ticks; real values are computed off-chain for Ekubo.
        TickParams {
            initial_tick_mag: 0,
            initial_tick_sign: false,
            lower_mag: 88368108,
            lower_sign: true,
            upper_mag: 88368108,
            upper_sign: false,
        }
    }

    // ── Deploy helpers ──────────────────────────────────────────────────────
    fn deploy_coin(
        recipient: ContractAddress, supply: u256, creator: ContractAddress,
    ) -> ContractAddress {
        let cls = declare("CreatorCoin").unwrap().contract_class();
        let mut cd: Array<felt252> = array![];
        let name: ByteArray = "Acme Coin";
        let symbol: ByteArray = "ACME";
        (name, symbol, supply, recipient, creator).serialize(ref cd);
        let (addr, _) = cls.deploy(@cd).unwrap();
        addr
    }

    // ── CreatorCoin (Task 2) ────────────────────────────────────────────────
    #[test]
    fn test_fixed_supply_minted_to_recipient() {
        let coin = deploy_coin(CREATOR(), 1_000_000_u256, CREATOR());
        let erc20 = IERC20Dispatcher { contract_address: coin };
        assert(erc20.total_supply() == 1_000_000, 'supply wrong');
        assert(erc20.balance_of(CREATOR()) == 1_000_000, 'recipient balance wrong');
    }

    #[test]
    fn test_creator_recorded() {
        let coin = deploy_coin(CREATOR(), 1_000_000_u256, CREATOR());
        let c = ICreatorCoinDispatcher { contract_address: coin };
        assert(c.creator() == CREATOR(), 'creator wrong');
    }

    #[test]
    fn test_transfer_works() {
        let coin = deploy_coin(CREATOR(), 1_000_000_u256, CREATOR());
        let erc20 = IERC20Dispatcher { contract_address: coin };
        cheat_caller_address(coin, CREATOR(), CheatSpan::TargetCalls(1));
        erc20.transfer(FAN(), 250_000_u256);
        assert(erc20.balance_of(FAN()) == 250_000, 'fan balance wrong');
        assert(erc20.balance_of(CREATOR()) == 750_000, 'creator balance wrong');
    }

    // ── LiquidityLock (Task 3) ──────────────────────────────────────────────
    fn deploy_lock() -> ILiquidityLockDispatcher {
        let cls = declare("LiquidityLock").unwrap().contract_class();
        let (addr, _) = cls.deploy(@array![]).unwrap();
        ILiquidityLockDispatcher { contract_address: addr }
    }

    fn deploy_nft(owner: ContractAddress) -> IMockERC721Dispatcher {
        let cls = declare("MockERC721").unwrap().contract_class();
        let (addr, _) = cls.deploy(@array![owner.into()]).unwrap();
        IMockERC721Dispatcher { contract_address: addr }
    }

    /// Lock owning position NFT #7, unlock_time = 1000, beneficiary = CREATOR.
    fn make_lock() -> (ILiquidityLockDispatcher, IMockERC721Dispatcher, u64) {
        let lock = deploy_lock();
        let nft = deploy_nft(ADMIN());
        // Mint position NFT #7 into the lock contract (owner-gated mint).
        cheat_caller_address(nft.contract_address, ADMIN(), CheatSpan::TargetCalls(1));
        nft.mint_token(lock.contract_address, 7_u256);
        let id = lock.lock(COIN(), CREATOR(), nft.contract_address, 7_u256, 1000_u64);
        (lock, nft, id)
    }

    #[test]
    fn test_lock_records_beneficiary_and_unlock() {
        let (lock, _nft, id) = make_lock();
        assert(lock.beneficiary_of(id) == CREATOR(), 'beneficiary wrong');
        assert(lock.unlock_time_of(id) == 1000, 'unlock wrong');
        assert(lock.position_id_of(id) == 7, 'position wrong');
        assert(!lock.is_withdrawn(id), 'should not be withdrawn');
    }

    #[test]
    #[should_panic(expected: ('Still locked',))]
    fn test_withdraw_before_unlock_reverts() {
        let (lock, _nft, id) = make_lock();
        start_cheat_block_timestamp_global(999_u64);
        cheat_caller_address(lock.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        lock.withdraw(id);
        stop_cheat_block_timestamp_global();
    }

    #[test]
    #[should_panic(expected: ('Not beneficiary',))]
    fn test_non_beneficiary_cannot_withdraw() {
        let (lock, _nft, id) = make_lock();
        start_cheat_block_timestamp_global(2000_u64);
        cheat_caller_address(lock.contract_address, FAN(), CheatSpan::TargetCalls(1));
        lock.withdraw(id);
        stop_cheat_block_timestamp_global();
    }

    #[test]
    fn test_withdraw_after_unlock_returns_nft() {
        let (lock, nft, id) = make_lock();
        start_cheat_block_timestamp_global(2000_u64);
        cheat_caller_address(lock.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        lock.withdraw(id);
        stop_cheat_block_timestamp_global();
        assert(lock.is_withdrawn(id), 'should be withdrawn');
        assert(nft.get_owner(7_u256) == CREATOR(), 'nft not returned');
    }

    // ── CoinFactory (Tasks 4 + 6) ───────────────────────────────────────────
    fn deploy_factory() -> ICoinFactoryDispatcher {
        let coin_cls = declare("CreatorCoin").unwrap().contract_class();
        let lock_cls = declare("LiquidityLock").unwrap().contract_class();
        let (lock_addr, _) = lock_cls.deploy(@array![]).unwrap();
        let ex_cls = declare("MockExchange").unwrap().contract_class();
        let (ex_addr, _) = ex_cls.deploy(@array![]).unwrap();
        let factory_cls = declare("CoinFactory").unwrap().contract_class();
        let mut cd: Array<felt252> = array![];
        // constructor(creator_coin_class_hash, liquidity_lock, exchange_adapter)
        ((*coin_cls.class_hash), lock_addr, ex_addr).serialize(ref cd);
        let (addr, _) = factory_cls.deploy(@cd).unwrap();
        ICoinFactoryDispatcher { contract_address: addr }
    }

    fn deploy_quote(owner: ContractAddress) -> IMockERC20Dispatcher {
        let cls = declare("MockERC20").unwrap().contract_class();
        let (addr, _) = cls.deploy(@array![owner.into()]).unwrap();
        IMockERC20Dispatcher { contract_address: addr }
    }

    #[test]
    fn test_create_coin_mints_full_supply_to_caller() {
        let factory = deploy_factory();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        let coin = factory.create_coin("Acme Coin", "ACME", 1_000_000_u256);
        let erc20 = IERC20Dispatcher { contract_address: coin };
        assert(erc20.total_supply() == 1_000_000, 'supply wrong');
        assert(erc20.balance_of(CREATOR()) == 1_000_000, 'creator balance wrong');
        assert(factory.get_last_coin_id() == 1, 'coin id wrong');
        assert(factory.get_creator_coin_count(CREATOR()) == 1, 'count wrong');
    }

    /// Creates a coin via the factory and approves the factory to pull pool coins + seed quote.
    fn launched_setup() -> (ICoinFactoryDispatcher, ContractAddress, ContractAddress) {
        let factory = deploy_factory();
        let quote = deploy_quote(CREATOR());
        start_cheat_caller_address_global(CREATOR());
        quote.mint_token(CREATOR(), 1000_u256);
        let coin = factory.create_coin("Acme Coin", "ACME", 1_000_000_u256);
        IERC20Dispatcher { contract_address: coin }.approve(factory.contract_address, 1_000_000_u256);
        IERC20Dispatcher { contract_address: quote.contract_address }
            .approve(factory.contract_address, 1000_u256);
        stop_cheat_caller_address_global();
        (factory, coin, quote.contract_address)
    }

    #[test]
    fn test_launch_happy_path_records_and_locks() {
        let (factory, coin, quote) = launched_setup();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        // 10% allocation, 100 seed, 180-day lock
        let (pool_id, lock_id) = factory
            .launch_on_ekubo(coin, quote, 1000_u16, 100_u256, 15_552_000_u64, default_ticks());

        assert(pool_id == 0xC01, 'pool id wrong');
        let rec = factory.get_coin(1);
        assert(rec.creator_allocation_bps == 1000, 'alloc wrong');
        assert(rec.lock_id == lock_id, 'lock id wrong');
        assert(rec.quote_token == quote, 'quote wrong');
        assert(rec.pool_id == 0xC01, 'rec pool wrong');
        // creator keeps 10% (100_000); 90% (900_000) went to the pool/adapter
        assert(
            IERC20Dispatcher { contract_address: coin }.balance_of(CREATOR()) == 100_000,
            'creator keep wrong',
        );
    }

    #[test]
    #[should_panic(expected: ('Allocation too high',))]
    fn test_launch_rejects_allocation_over_cap() {
        let (factory, coin, quote) = launched_setup();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        factory.launch_on_ekubo(coin, quote, 1001_u16, 100_u256, 15_552_000_u64, default_ticks());
    }

    #[test]
    #[should_panic(expected: ('Lock too short',))]
    fn test_launch_rejects_short_lock() {
        let (factory, coin, quote) = launched_setup();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        factory.launch_on_ekubo(coin, quote, 1000_u16, 100_u256, 100_u64, default_ticks());
    }

    #[test]
    #[should_panic(expected: ('Seed zero',))]
    fn test_launch_rejects_zero_seed() {
        let (factory, coin, quote) = launched_setup();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        factory.launch_on_ekubo(coin, quote, 1000_u16, 0_u256, 15_552_000_u64, default_ticks());
    }
}
