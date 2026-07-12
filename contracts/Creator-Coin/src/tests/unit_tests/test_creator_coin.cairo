// Post-launch transfer-restriction behavior is exercised in the fork tests,
// where a real Ekubo launch can be performed against a Starknet mainnet fork.
// These unit tests cover the contract state that does not require a live launch.

mod test_constructor {
    use CreatorCoin::ICreatorCoinAdditional;
    use snforge_std::{start_prank, stop_prank, CheatTarget};
    use creator_coin::tests::unit_tests::utils::{
        OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, CREATOR_COIN_FACTORY_ADDRESS
    };
    use creator_coin::token::CreatorCoin;
    use creator_coin::token::interface::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
    };


    #[test]
    fn test_constructor_happy_path() {
        let mut creator_coin = CreatorCoin::contract_state_for_testing();

        // Deployer must be the creator_coin factory
        start_prank(CheatTarget::One(snforge_std::test_address()), CREATOR_COIN_FACTORY_ADDRESS());
        CreatorCoin::constructor(
            ref creator_coin, OWNER(), NAME(), SYMBOL(), DEFAULT_INITIAL_SUPPLY(),
        );

        // External entrypoints
        assert(
            creator_coin.creator_coin_factory_address() == CREATOR_COIN_FACTORY_ADDRESS(),
            'wrong factory address'
        );
    }
}

mod creator_coin_entrypoints {
    use openzeppelin::token::erc20::interface::{
        IERC20, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
    };
    use snforge_std::{start_prank, stop_prank, CheatTarget, store, map_entry_address};
    use starknet::{ContractAddress, contract_address_const};
    use creator_coin::tests::unit_tests::utils::{
        deploy_creator_coin_through_factory, CREATOR_COIN_FACTORY_ADDRESS, ALICE
    };
    use creator_coin::token::interface::{
        ICreatorCoin, ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
    };

    #[test]
    fn test_get_team_allocation() {
        let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory();
        store(creator_coin_address, selector!("team_allocation"), array![2_100_000].span());

        let team_allocation = creator_coin.get_team_allocation();
        // Team alloc is set to 10% in test utils
        assert_eq!(team_allocation, 2_100_000);
    }

    #[test]
    fn test_creator_coin_factory_address() {
        let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory();

        assert(
            creator_coin.creator_coin_factory_address() == CREATOR_COIN_FACTORY_ADDRESS(),
            'wrong factory address'
        );
    }

    #[test]
    fn test_classic_max_percentage() {
        let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );

        // The coin is not launched, so transfers are unrestricted.
        start_prank(CheatTarget::One(creator_coin_address), sender);
        let send_amount = creator_coin.transfer(ALICE(), 20);
        assert(creator_coin.balanceOf(ALICE()) == 20, 'Invalid balance');
    }
}
