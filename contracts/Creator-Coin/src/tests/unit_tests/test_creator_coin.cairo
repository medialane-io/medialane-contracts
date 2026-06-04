use openzeppelin::token::erc20::interface::{IERC20, ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::utils::serde::SerializedAppend;

use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, RevertedTransaction, CheatTarget,
    TxInfoMock, store, map_entry_address
};
use starknet::contract_address::ContractAddressZeroable;
use starknet::{ContractAddress, contract_address_const};
use creator_coin::exchanges::{SupportedExchanges};
use creator_coin::tests::unit_tests::utils::{
    OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, RECIPIENT, SPENDER, deploy_locker, INITIAL_HOLDERS,
    INITIAL_HOLDERS_AMOUNTS, TRANSFER_RESTRICTION_DELAY, DefaultTxInfoMock,
    deploy_creator_coin_through_factory
};
use creator_coin::token::interface::{
    ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
};

mod test_constructor {
    use CreatorCoin::{
        transfer_restriction_delayContractMemberStateTrait, team_allocationContractMemberStateTrait,
        ICreatorCoinAdditional, ICreatorCoinCamel, ICreatorCoinSnake
    };
    use core::debug::PrintTrait;
    use core::traits::TryInto;
    use openzeppelin::token::erc20::interface::IERC20;
    use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank, CheatTarget};
    use starknet::{ContractAddress, contract_address_const};
    use creator_coin::tests::unit_tests::utils::{
        deploy_jedi_amm_factory_and_router, deploy_creator_coin_factory, deploy_locker,
        deploy_eth_with_owner, OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, INITIAL_HOLDERS,
        INITIAL_HOLDER_1, INITIAL_HOLDER_2, INITIAL_HOLDERS_AMOUNTS, SALT, DefaultTxInfoMock,
        deploy_creator_coin_through_factory, ETH_ADDRESS, deploy_creator_coin_through_factory_with_owner,
        JEDI_ROUTER_ADDRESS, CREATOR_COIN_FACTORY_ADDRESS, ALICE, BOB, TRANSFER_RESTRICTION_DELAY, pow_256,
        LOCK_MANAGER_ADDRESS, JEDI_FACTORY_ADDRESS
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
            creator_coin.creator_coin_factory_address() == CREATOR_COIN_FACTORY_ADDRESS(), 'wrong factory address'
        );
    }
}

mod creator_coin_entrypoints {
    use core::clone::Clone;
    use core::zeroable::Zeroable;
    use debug::PrintTrait;
    use openzeppelin::token::erc20::interface::{
        IERC20, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
    };
    use snforge_std::{
        declare, ContractClassTrait, start_prank, stop_prank, CheatTarget, start_warp, stop_warp,
        TxInfoMock, store, map_entry_address
    };
    use starknet::{ContractAddress, contract_address_const};
    use creator_coin::exchanges::{SupportedExchanges};
    use creator_coin::factory::{IFactory, IFactoryDispatcher, IFactoryDispatcherTrait};
    use creator_coin::tests::unit_tests::utils::{
        deploy_jedi_amm_factory_and_router, deploy_creator_coin_factory, deploy_locker,
        deploy_eth_with_owner, OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, INITIAL_HOLDERS,
        INITIAL_HOLDER_1, INITIAL_HOLDER_2, INITIAL_HOLDERS_AMOUNTS, SALT, DefaultTxInfoMock,
        deploy_creator_coin_through_factory, ETH_ADDRESS, deploy_creator_coin_through_factory_with_owner,
        JEDI_ROUTER_ADDRESS, CREATOR_COIN_FACTORY_ADDRESS, ALICE, BOB, pow_256, LOCK_MANAGER_ADDRESS,
        deploy_and_launch_creator_coin, TRANSFER_RESTRICTION_DELAY, UNLOCK_TIME, DEFAULT_MIN_LOCKTIME
    };
    use creator_coin::token::interface::{
        ICreatorCoin, ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
    };
    use creator_coin::token::creator_coin::{LiquidityType, CreatorCoin};

    #[test]
    fn test_renounce_ownership_upon_creator_coin_launch() {
        let (creator_coin, creator_coin_address) = deploy_and_launch_creator_coin();

        assert(creator_coin.owner().is_zero(), 'Still an owner');
    }

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
            creator_coin.creator_coin_factory_address() == CREATOR_COIN_FACTORY_ADDRESS(), 'wrong factory address'
        );
    }

    #[test]
    fn test_transfer_max_percentage_not_pair_should_succeed() {
        let (creator_coin, creator_coin_address) = deploy_and_launch_creator_coin();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );

        // Transfer slightly more than 2% of 21M stokens from owner to ALICE().
        let amount = 420_001;
        start_prank(CheatTarget::One(creator_coin.contract_address), sender);
        let send_amount = creator_coin.transfer(ALICE(), amount);
    }

    #[test]
    fn test_transfer_from_max_percentage_not_pair_should_succeed() {
        let (creator_coin, creator_coin_address) = deploy_and_launch_creator_coin();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );
        let pre_sender_balance = creator_coin.balance_of(sender);

        let this_address = snforge_std::test_address();
        let amount = 420_001;

        start_prank(CheatTarget::One(creator_coin.contract_address), sender);
        creator_coin.approve(this_address, amount);
        stop_prank(CheatTarget::One(creator_coin.contract_address));

        creator_coin.transfer_from(sender, ALICE(), amount);
    }

    #[test]
    fn test_transfer_from_multi_call_not_pair_should_succeed() {
        let (creator_coin, creator_coin_address) = deploy_and_launch_creator_coin();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );

        let this_address = snforge_std::test_address();

        // Approvals required for transferFrom
        start_prank(CheatTarget::One(creator_coin_address), sender);
        creator_coin.approve(this_address, 2);
        stop_prank(CheatTarget::One(creator_coin_address));

        // Transfer token from owner twice, to ALICE() and to BOB() - should fail because
        // the tx_hash is the same for both calls
        creator_coin.transfer_from(sender, ALICE(), 1);
        creator_coin.transfer_from(sender, BOB(), 1);
    }

    #[test]
    fn test_multi_call_prevention_disallowed_after_delay() {
        let (creator_coin, creator_coin_address) = deploy_and_launch_creator_coin();

        let launch_timestamp = 1;

        // setting block timestamp >= launch_time + transfer_delay. Transfer should succeed
        // as multi calls to the same recipient are allowed after the delay
        start_warp(
            CheatTarget::One(creator_coin.contract_address),
            launch_timestamp + TRANSFER_RESTRICTION_DELAY
        );
        start_prank(CheatTarget::One(creator_coin.contract_address), INITIAL_HOLDER_1());
        let send_amount = creator_coin.transfer_from(INITIAL_HOLDER_1(), ALICE(), 0);
        let send_amount = creator_coin.transfer_from(INITIAL_HOLDER_1(), BOB(), 0);
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

        // Transfer 1 token from owner to ALICE().
        start_prank(CheatTarget::One(creator_coin_address), sender);
        let send_amount = creator_coin.transfer(ALICE(), 20);
        assert(creator_coin.balanceOf(ALICE()) == 20, 'Invalid balance');
    }
}
