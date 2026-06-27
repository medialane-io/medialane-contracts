use core::traits::TryInto;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, start_spoof, CheatTarget, TxInfoMock,
    get_class_hash, ContractClass
};
use starknet::ContractAddress;
use creator_coin::exchanges::SupportedExchanges;
use creator_coin::factory::interface::{IFactoryDispatcher, IFactoryDispatcherTrait};
use creator_coin::tests::addresses::{
    EKUBO_CORE, EKUBO_POSITIONS, EKUBO_REGISTRY, ETH_ADDRESS, EKUBO_ROUTER, TOKEN0_ADDRESS
};
use creator_coin::tests::unit_tests::utils::{
    deploy_eth_with_owner, NAME, SYMBOL, DEFAULT_INITIAL_SUPPLY, INITIAL_HOLDERS,
    INITIAL_HOLDERS_AMOUNTS, SALT, DefaultTxInfoMock, OWNER, CREATOR_COIN_FACTORY_ADDRESS,
    ETH_INITIAL_SUPPLY
};
use creator_coin::token::interface::{
    ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
};

fn EKUBO_LAUNCHER_ADDRESS() -> ContractAddress {
    'ekubo_launchpad'.try_into().unwrap()
}

fn EKUBO_ROUTER_ADDRESS() -> ContractAddress {
    0x01b6f560def289b32e2a7b0920909615531a4d9d5636ca509045843559dc23d5.try_into().unwrap()
}

// quote token ensured to be token0

fn deploy_token0_with_owner(owner: ContractAddress) -> (ERC20ABIDispatcher, ContractAddress) {
    let token = declare('ERC20Token');
    let mut calldata = Default::default();
    Serde::serialize(@ETH_INITIAL_SUPPLY(), ref calldata);
    Serde::serialize(@owner, ref calldata);

    let address = token.deploy_at(@calldata, TOKEN0_ADDRESS()).unwrap();
    let dispatcher = ERC20ABIDispatcher { contract_address: address, };
    (dispatcher, address)
}


fn deploy_token0() -> (ERC20ABIDispatcher, ContractAddress) {
    deploy_token0_with_owner(OWNER())
}


fn deploy_ekubo_launcher() -> ContractAddress {
    let launcher = declare('EkuboLauncher');
    let mut calldata = Default::default();
    Serde::serialize(@EKUBO_CORE(), ref calldata);
    Serde::serialize(@EKUBO_REGISTRY(), ref calldata);
    Serde::serialize(@EKUBO_POSITIONS(), ref calldata);
    Serde::serialize(@EKUBO_ROUTER(), ref calldata);

    launcher
        .deploy_at(@calldata, EKUBO_LAUNCHER_ADDRESS())
        .expect('EkuboLauncher deployment failed')
}

// CreatorCoinFactory
fn deploy_creator_coin_factory(
    exchanges: Span<(SupportedExchanges, ContractAddress)>
) -> ContractAddress {
    let creator_coin_class_hash = declare('CreatorCoin').class_hash;

    let contract = declare('Factory');
    let mut calldata = array![];
    Serde::serialize(@creator_coin_class_hash, ref calldata);
    Serde::serialize(@exchanges.into(), ref calldata);
    contract.deploy_at(@calldata, CREATOR_COIN_FACTORY_ADDRESS()).expect('Factory deployment failed')
}

/// Deploys the factory and the creator_coin.
/// Sends 50% of the ETH supply to the creator_coin.
/// The effective price upon launch will be 1 ETH = 2 CREATOR_COIN
/// Given that the entire supply of CREATOR_COIN is LPed
fn deploy_creator_coin_through_factory_with_owner(
    owner: ContractAddress
) -> (ICreatorCoinDispatcher, ContractAddress) {
    let ekubo_launchpad = deploy_ekubo_launcher();
    let supported_exchanges = array![(SupportedExchanges::Ekubo, ekubo_launchpad),].span();
    let creator_coin_factory_address = deploy_creator_coin_factory(supported_exchanges);
    let creator_coin_factory = IFactoryDispatcher { contract_address: creator_coin_factory_address };

    start_prank(CheatTarget::One(creator_coin_factory.contract_address), owner);
    let creator_coin_address = creator_coin_factory
        .create_creator_coin(
            owner: owner,
            name: NAME(),
            symbol: SYMBOL(),
            initial_supply: DEFAULT_INITIAL_SUPPLY(),
            contract_address_salt: SALT(),
        );
    stop_prank(CheatTarget::One(creator_coin_factory.contract_address));

    let mut tx_info: TxInfoMock = Default::default();
    tx_info.account_contract_address = Option::Some(snforge_std::test_address());
    start_spoof(CheatTarget::One(creator_coin_address), tx_info);

    (ICreatorCoinDispatcher { contract_address: creator_coin_address }, creator_coin_address)
}

fn sort_tokens(
    tokenA: ContractAddress, tokenB: ContractAddress
) -> (ContractAddress, ContractAddress) {
    let tokenA: felt252 = tokenA.into();
    let tokenB: felt252 = tokenB.into();
    let tokenA: u256 = tokenA.into();
    let tokenB: u256 = tokenB.into();
    if tokenA < tokenB {
        let token0: felt252 = tokenA.try_into().unwrap();
        let token1: felt252 = tokenB.try_into().unwrap();
        (token0.try_into().unwrap(), token1.try_into().unwrap())
    } else {
        let token0: felt252 = tokenB.try_into().unwrap();
        let token1: felt252 = tokenA.try_into().unwrap();
        (token0.try_into().unwrap(), token1.try_into().unwrap())
    }
}
