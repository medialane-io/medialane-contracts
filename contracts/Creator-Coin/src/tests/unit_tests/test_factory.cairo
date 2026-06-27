use core::option::OptionTrait;
use core::traits::TryInto;
use ekubo::types::i129::i129;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, CheatTarget, start_warp, stop_warp,
    start_roll, stop_roll, get_class_hash, ContractClass
};
use starknet::{ContractAddress, contract_address_const};
use creator_coin::exchanges::ekubo_adapter::EkuboPoolParameters;
use creator_coin::exchanges::{SupportedExchanges};
use creator_coin::factory::{IFactory, IFactoryDispatcher, IFactoryDispatcherTrait, LaunchParameters};
use creator_coin::tests::addresses::{ETH_ADDRESS};
use creator_coin::tests::unit_tests::utils::{
    deploy_creator_coin_factory, deploy_eth, OWNER, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY,
    INITIAL_HOLDERS, INITIAL_HOLDERS_AMOUNTS, SALT, deploy_creator_coin_through_factory,
    CREATOR_COIN_FACTORY_ADDRESS, EKUBO_LAUNCHER_ADDRESS, deploy_token_from_class_at_address_with_owner,
    deploy_creator_coin_through_factory_with_owner, pow_256, TRANSFER_RESTRICTION_DELAY,
    MAX_PERCENTAGE_BUY_LAUNCH
};
use creator_coin::token::interface::{
    ICreatorCoin, ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
};


#[test]
fn test_locked_liquidity_not_locked() {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    assert(factory.locked_liquidity(creator_coin_address).is_none(), 'liquidty not locked yet');
}

// The full Ekubo launch (and its locked-liquidity / transfer-restriction behavior)
// is covered in the fork tests, which run against a Starknet mainnet fork.

#[test]
fn test_exchange_address() {
    let creator_coin_factory_address = deploy_creator_coin_factory();
    let creator_coin_factory = IFactoryDispatcher { contract_address: creator_coin_factory_address };

    let exchange_address = creator_coin_factory.exchange_address(SupportedExchanges::Ekubo);
    assert(exchange_address == EKUBO_LAUNCHER_ADDRESS(), 'wrong ekubo launcher address');
}

#[test]
fn test_is_creator_coin() {
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory();
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    assert(factory.is_creator_coin(address: creator_coin_address), 'should be creator_coin');
    assert(
        !factory.is_creator_coin(address: 'random address'.try_into().unwrap()),
        'should not be creator_coin'
    );
}


#[test]
fn test_create_creator_coin() {
    let creator_coin_factory_address = deploy_creator_coin_factory();
    let creator_coin_factory = IFactoryDispatcher { contract_address: creator_coin_factory_address };

    start_prank(CheatTarget::One(creator_coin_factory.contract_address), OWNER());
    let creator_coin_address = creator_coin_factory
        .create_creator_coin(
            owner: OWNER(),
            name: NAME(),
            symbol: SYMBOL(),
            initial_supply: DEFAULT_INITIAL_SUPPLY(),
            contract_address_salt: SALT(),
        );
    stop_prank(CheatTarget::One(creator_coin_factory.contract_address));

    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };

    assert(creator_coin.name() == NAME(), 'wrong creator_coin name');
    assert(creator_coin.symbol() == SYMBOL(), 'wrong creator_coin symbol');
    assert_eq!(creator_coin.balanceOf(creator_coin_factory_address), DEFAULT_INITIAL_SUPPLY(),);
}

#[test]
#[should_panic(expected: ('Token not deployed by factory',))]
fn test_launch_not_creator_coin() {
    let factory = IFactoryDispatcher { contract_address: deploy_creator_coin_factory() };
    let (eth, eth_address) = deploy_eth();

    // `eth` was not deployed by the factory, so it is not a creator_coin.
    factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address: eth_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: ETH_ADDRESS(),
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0x51eb851eb851ec00000000000000000,
                tick_spacing: 5982,
                starting_price: i129 { sign: false, mag: 1 },
                bound: 88712960
            }
        );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_launch_creator_coin_not_owner() {
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory();
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: ETH_ADDRESS(),
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0x51eb851eb851ec00000000000000000,
                tick_spacing: 5982,
                starting_price: i129 { sign: false, mag: 1 },
                bound: 88712960
            }
        );
}

#[test]
#[should_panic(expected: ('Quote token is creator_coin',))]
fn test_launch_creator_coin_quote_creator_coin() {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    // Create a second creator_coin used as quote - quote tokens cannot be creator_coins.
    start_prank(CheatTarget::One(factory.contract_address), owner);
    let quote_address = factory
        .create_creator_coin(
            owner: owner,
            name: NAME(),
            symbol: SYMBOL(),
            initial_supply: DEFAULT_INITIAL_SUPPLY(),
            contract_address_salt: SALT() + 1,
        );

    factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0x51eb851eb851ec00000000000000000,
                tick_spacing: 5982,
                starting_price: i129 { sign: false, mag: 1 },
                bound: 88712960
            }
        );
    stop_prank(CheatTarget::One(factory.contract_address));
}

#[test]
#[should_panic(expected: ('Fee too high',))]
fn test_launch_creator_coin_ekubo_fee_high() {
    let owner = starknet::get_contract_address();
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let eth = ERC20ABIDispatcher { contract_address: ETH_ADDRESS() };

    factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: eth.contract_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0x5604189374bc6c00000000000000000,
                tick_spacing: 5982,
                starting_price: i129 { sign: false, mag: 0 },
                bound: 0
            } // Fee : 2.1
        );
}

#[test]
#[should_panic(expected: ('Tick spacing high',))]
fn test_launch_creator_coin_ekubo_tick_spacing_too_high() {
    let owner = starknet::get_contract_address();
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let eth = ERC20ABIDispatcher { contract_address: ETH_ADDRESS() };

    factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: eth.contract_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0x51eb851eb851ec00000000000000000,
                tick_spacing: 19850,
                starting_price: i129 { sign: false, mag: 0 },
                bound: 0
            }
        );
}

#[test]
#[should_panic(expected: ('Tick spacing low',))]
fn test_launch_creator_coin_ekubo_tick_spacing_too_low() {
    let owner = starknet::get_contract_address();
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let eth = ERC20ABIDispatcher { contract_address: ETH_ADDRESS() };

    factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: eth.contract_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0x51eb851eb851ec00000000000000000,
                tick_spacing: 5900,
                starting_price: i129 { sign: false, mag: 0 },
                bound: 0
            }
        );
}
