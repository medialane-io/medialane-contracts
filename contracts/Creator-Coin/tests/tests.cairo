#[cfg(test)]
mod test {
    use creator_coin::interfaces::ICreatorCoin::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait,
    };
    use creator_coin::interfaces::ICoinFactory::{
        ICoinFactoryDispatcher, ICoinFactoryDispatcherTrait,
    };
    use creator_coin::interfaces::IExchangeAdapter::TickParams;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    };
    use starknet::ContractAddress;

    fn CREATOR() -> ContractAddress {
        0xC0FFEE.try_into().unwrap()
    }

    /// Dummy quote/pair token. Never dispatched to in unit tests — the creator pays no
    /// quote (single-sided model), and the MockExchange ignores it.
    fn QUOTE() -> ContractAddress {
        0x57414b.try_into().unwrap()
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

    // ── CreatorCoin ─────────────────────────────────────────────────────────
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
        assert(
            ICreatorCoinDispatcher { contract_address: coin }.creator() == CREATOR(),
            'creator wrong',
        );
    }

    // ── CoinFactory.launch (split: creator keeps <=10%, rest to the pool) ─────
    fn deploy_factory() -> (ICoinFactoryDispatcher, ContractAddress) {
        let coin_cls = declare("CreatorCoin").unwrap().contract_class();
        let ex_cls = declare("MockExchange").unwrap().contract_class();
        let (ex_addr, _) = ex_cls.deploy(@array![]).unwrap();
        let factory_cls = declare("CoinFactory").unwrap().contract_class();
        let mut cd: Array<felt252> = array![];
        // constructor(creator_coin_class_hash, exchange_adapter)
        ((*coin_cls.class_hash), ex_addr).serialize(ref cd);
        let (addr, _) = factory_cls.deploy(@cd).unwrap();
        (ICoinFactoryDispatcher { contract_address: addr }, ex_addr)
    }

    #[test]
    fn test_launch_splits_allocation_and_pool() {
        let (factory, ex_addr) = deploy_factory();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        // 10% founder allocation
        let (coin, pool_id) = factory
            .launch("Acme Coin", "ACME", 1_000_000_u256, QUOTE(), 1000_u16, default_ticks());

        assert(pool_id == 0xC01, 'pool id wrong');
        let erc20 = IERC20Dispatcher { contract_address: coin };
        // creator keeps 10% directly
        assert(erc20.balance_of(CREATOR()) == 100_000, 'creator alloc wrong');
        // the other 90% went to the pool (held by the adapter in this mock)
        assert(erc20.balance_of(ex_addr) == 900_000, 'pool amount wrong');
        let rec = factory.get_coin(1);
        assert(rec.creator == CREATOR(), 'creator wrong');
        assert(rec.creator_allocation_bps == 1000, 'alloc bps wrong');
        assert(factory.get_creator_coin_count(CREATOR()) == 1, 'count wrong');
    }

    #[test]
    fn test_launch_zero_allocation_all_to_pool() {
        let (factory, ex_addr) = deploy_factory();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        let (coin, _) = factory
            .launch("Acme Coin", "ACME", 1_000_000_u256, QUOTE(), 0_u16, default_ticks());

        let erc20 = IERC20Dispatcher { contract_address: coin };
        assert(erc20.balance_of(CREATOR()) == 0, 'creator should hold 0');
        assert(erc20.balance_of(ex_addr) == 1_000_000, 'all to pool');
    }

    #[test]
    #[should_panic(expected: ('Allocation too high',))]
    fn test_launch_rejects_bps_over_cap() {
        let (factory, _ex) = deploy_factory();
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        factory.launch("Acme", "ACME", 1_000_000_u256, QUOTE(), 1001_u16, default_ticks());
    }
}
