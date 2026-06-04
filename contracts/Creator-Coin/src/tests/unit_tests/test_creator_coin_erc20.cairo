use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::utils::serde::SerializedAppend;

use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, RevertedTransaction, CheatTarget,
    TxInfoMock, store, map_entry_address
};
use starknet::{ContractAddress, contract_address_const};
use creator_coin::exchanges::{SupportedExchanges};
use creator_coin::tests::unit_tests::utils::{
    OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, RECIPIENT, SPENDER, deploy_locker, INITIAL_HOLDERS,
    INITIAL_HOLDERS_AMOUNTS, TRANSFER_RESTRICTION_DELAY, DefaultTxInfoMock,
    deploy_standalone_creator_coin
};
use creator_coin::token::interface::{
    ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
};


mod erc20_metadata {
    use core::debug::PrintTrait;
    use openzeppelin::token::erc20::interface::IERC20;
    use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank, CheatTarget};
    use starknet::{ContractAddress, contract_address_const};
    use super::{
        deploy_standalone_creator_coin, OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, RECIPIENT, SPENDER,
        deploy_locker
    };
    use creator_coin::token::interface::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
    };

    #[test]
    fn test_name() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        assert(creator_coin.name() == NAME(), 'Invalid name');
    }

    #[test]
    fn test_decimals() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        assert(creator_coin.decimals() == 18, 'Invalid decimals');
    }

    #[test]
    fn test_symbol() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        assert(creator_coin.symbol() == SYMBOL(), 'Invalid symbol');
    }
}

mod erc20_entrypoints {
    use core::array::SpanTrait;
    use core::debug::PrintTrait;
    use core::traits::Into;
    use snforge_std::{
        declare, ContractClassTrait, start_prank, stop_prank, start_warp, CheatTarget, TxInfoMock,
        store, map_entry_address
    };
    use starknet::{ContractAddress, contract_address_const};
    use super::{
        deploy_standalone_creator_coin, OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, RECIPIENT, SPENDER,
        deploy_locker, INITIAL_HOLDERS, DefaultTxInfoMock, INITIAL_HOLDERS_AMOUNTS
    };
    use creator_coin::token::interface::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
    };

    // Test ERC20 snake entrypoints

    #[test]
    fn test_total_supply() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        assert_eq!(creator_coin.total_supply(), DEFAULT_INITIAL_SUPPLY())
    }

    #[test]
    fn test_balance_of() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![123].span()),
            array![2_100_000].span()
        );

        // Check initial contract balance and initial holders balances.
        assert_eq!(creator_coin.balance_of(snforge_std::test_address()), DEFAULT_INITIAL_SUPPLY());
        assert_eq!(creator_coin.balance_of(contract_address_const::<123>()), 2_100_000)
    }

    #[test]
    fn test_approve_allowance() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();

        // Check initial allowance. Should be equal to 0.
        let allowance = creator_coin.allowance(OWNER(), SPENDER());
        assert(allowance == 0, 'Invalid allowance before');

        // Approve initial supply tokens.
        start_prank(CheatTarget::One(creator_coin.contract_address), OWNER());
        creator_coin.approve(SPENDER(), DEFAULT_INITIAL_SUPPLY());

        // Check allowance. Should be equal to initial supply.
        let allowance = creator_coin.allowance(OWNER(), SPENDER());
        assert(allowance == DEFAULT_INITIAL_SUPPLY(), 'Invalid allowance after');
    }

    #[test]
    fn test_transfer() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );

        // Transfer 20 tokens to recipient.
        let pre_sender_balance = creator_coin.balance_of(sender);
        start_prank(CheatTarget::One(creator_coin.contract_address), sender);
        creator_coin.transfer(RECIPIENT(), 20);

        // Check balance. Should be equal to initial balance - 20.
        let post_sender_balance = creator_coin.balance_of(sender);
        assert(post_sender_balance == pre_sender_balance - 20, 'Invalid sender balance update');

        // Check recipient balance. Should be equal to 20.
        let recipient_balance = creator_coin.balance_of(RECIPIENT());
        assert(recipient_balance == 20, 'Invalid balance recipient');
    }

    #[test]
    fn test_transfer_from() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );
        let pre_sender_balance = creator_coin.balance_of(sender);

        // Approve initial supply tokens.
        start_prank(CheatTarget::One(creator_coin.contract_address), sender);
        creator_coin.approve(SPENDER(), DEFAULT_INITIAL_SUPPLY());

        // Transfer 20 tokens to recipient.
        start_prank(CheatTarget::One(creator_coin.contract_address), SPENDER());
        creator_coin.transfer_from(sender, RECIPIENT(), 20);

        // Check balance. Should be equal to initial balance - 20.
        let post_sender_balance = creator_coin.balance_of(sender);
        assert(post_sender_balance == pre_sender_balance - 20, 'Invalid sender balance update');

        // Check recipient balance. Should be equal to 20.
        let recipient_balance = creator_coin.balanceOf(RECIPIENT());
        assert(recipient_balance == 20, 'Invalid balance recipient');

        // Check allowance. Should be equal to initial supply - transfered amount.
        let allowance = creator_coin.allowance(sender, SPENDER());
        assert(allowance == (DEFAULT_INITIAL_SUPPLY() - 20), 'Invalid allowance');
    }

    // Test ERC20 Camel entrypoints

    #[test]
    fn test_totalSupply() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        assert_eq!(creator_coin.totalSupply(), DEFAULT_INITIAL_SUPPLY())
    }

    #[test]
    fn test_balanceOf() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![123].span()),
            array![2_100_000].span()
        );

        // Check initial contract balance
        assert_eq!(creator_coin.balanceOf(snforge_std::test_address()), DEFAULT_INITIAL_SUPPLY());
        assert_eq!(creator_coin.balanceOf(contract_address_const::<123>()), 2_100_000)
    }

    #[test]
    fn test_transferFrom() {
        let (creator_coin, creator_coin_address) = deploy_standalone_creator_coin();
        let sender = contract_address_const::<'sender'>();
        store(
            creator_coin_address,
            map_entry_address(selector!("ERC20_balances"), array![sender.into()].span()),
            array![2_100_000].span()
        );
        let pre_sender_balance = creator_coin.balance_of(sender);

        // Approve initial supply tokens.
        start_prank(CheatTarget::One(creator_coin.contract_address), sender);
        creator_coin.approve(SPENDER(), DEFAULT_INITIAL_SUPPLY());

        // Transfer 20 tokens to recipient.
        start_prank(CheatTarget::One(creator_coin.contract_address), SPENDER());
        creator_coin.transferFrom(sender, RECIPIENT(), 20);

        // Check balance. Should be equal to initial balance - 20.
        let post_sender_balance = creator_coin.balance_of(sender);
        assert(post_sender_balance == pre_sender_balance - 20, 'Invalid sender balance update');

        // Check recipient balance. Should be equal to 20.
        let recipient_balance = creator_coin.balanceOf(RECIPIENT());
        assert(recipient_balance == 20, 'Invalid balance recipient');

        // Check allowance. Should be equal to initial supply - transfered amount.
        let allowance = creator_coin.allowance(sender, SPENDER());
        assert(allowance == (DEFAULT_INITIAL_SUPPLY() - 20), 'Invalid allowance');
    }
}
