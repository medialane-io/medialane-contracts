#[cfg(test)]
mod test {
    use creator_coin::interfaces::ICreatorCoin::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait,
    };
    use creator_coin::interfaces::ICoinFactory::{
        ICoinFactoryDispatcher, ICoinFactoryDispatcherTrait,
    };
    use creator_coin::interfaces::IExchangeAdapter::TickParams;
    use creator_coin::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use creator_coin::mocks::MockExchange::{
        IMockExchangeConfigDispatcher, IMockExchangeConfigDispatcherTrait,
    };
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    };
    use starknet::ContractAddress;

    fn CREATOR() -> ContractAddress {
        0xC0FFEE.try_into().unwrap()
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

    // ── CoinFactory.launch ──────────────────────────────────────────────────
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

    fn deploy_quote(owner: ContractAddress) -> IMockERC20Dispatcher {
        let cls = declare("MockERC20").unwrap().contract_class();
        let (addr, _) = cls.deploy(@array![owner.into()]).unwrap();
        IMockERC20Dispatcher { contract_address: addr }
    }

    /// Mint `amount` quote to CREATOR and approve the factory to pull it.
    /// Uses targeted caller cheats so the factory's own internal token calls
    /// keep their real (factory) caller.
    fn fund_and_approve(
        quote: IMockERC20Dispatcher, factory: ContractAddress, amount: u256,
    ) {
        cheat_caller_address(quote.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        quote.mint_token(CREATOR(), amount);
        cheat_caller_address(quote.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        IERC20Dispatcher { contract_address: quote.contract_address }.approve(factory, amount);
    }

    #[test]
    fn test_launch_happy_path_buyback_to_creator() {
        let (factory, ex_addr) = deploy_factory();
        let quote = deploy_quote(CREATOR());
        // mock will deliver exactly 10% (100_000) on buyback
        IMockExchangeConfigDispatcher { contract_address: ex_addr }.set_coins_bought(100_000_u256);
        fund_and_approve(quote, factory.contract_address, 1000_u256);

        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        let (coin, pool_id) = factory
            .launch(
                "Acme Coin",
                "ACME",
                1_000_000_u256,
                quote.contract_address,
                1000_u16,
                100_u256,
                default_ticks(),
            );

        assert(pool_id == 0xC01, 'pool id wrong');
        let rec = factory.get_coin(1);
        assert(rec.creator == CREATOR(), 'creator wrong');
        assert(rec.total_supply == 1_000_000, 'supply wrong');
        // creator received the bought 10%
        assert(
            IERC20Dispatcher { contract_address: coin }.balance_of(CREATOR()) == 100_000,
            'creator buyback wrong',
        );
        assert(factory.get_creator_coin_count(CREATOR()) == 1, 'count wrong');
    }

    #[test]
    #[should_panic(expected: ('Allocation too high',))]
    fn test_launch_rejects_bps_over_cap() {
        let (factory, _ex) = deploy_factory();
        let quote = deploy_quote(CREATOR());
        fund_and_approve(quote, factory.contract_address, 1000_u256);
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        factory
            .launch(
                "Acme", "ACME", 1_000_000_u256, quote.contract_address, 1001_u16, 100_u256,
                default_ticks(),
            );
    }

    #[test]
    #[should_panic(expected: ('Buyback over cap',))]
    fn test_launch_rejects_buyback_exceeding_cap() {
        let (factory, ex_addr) = deploy_factory();
        let quote = deploy_quote(CREATOR());
        // mock delivers 150_000 (15%) but cap bps says 10% → must revert
        IMockExchangeConfigDispatcher { contract_address: ex_addr }.set_coins_bought(150_000_u256);
        fund_and_approve(quote, factory.contract_address, 1000_u256);
        cheat_caller_address(factory.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        factory
            .launch(
                "Acme", "ACME", 1_000_000_u256, quote.contract_address, 1000_u16, 100_u256,
                default_ticks(),
            );
    }
}
