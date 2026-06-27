use core::traits::TryInto;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    ContractClass, ContractClassTrait, CheatTarget, declare, start_prank, stop_prank, TxInfoMock,
    start_warp, stop_warp, get_class_hash
};
use starknet::ContractAddress;
use creator_coin::exchanges::{SupportedExchanges};
use creator_coin::factory::{IFactoryDispatcher, IFactoryDispatcherTrait, LaunchParameters};
use creator_coin::tests::addresses::{
    JEDI_ROUTER_ADDRESS, JEDI_FACTORY_ADDRESS, ETH_ADDRESS, EKUBO_CORE, EKUBO_POSITIONS,
    EKUBO_REGISTRY, TOKEN0_ADDRESS
};
use creator_coin::token::interface::{
    ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
};


// Constants
fn OWNER() -> ContractAddress {
    'owner'.try_into().unwrap()
}

fn RECIPIENT() -> ContractAddress {
    'recipient'.try_into().unwrap()
}

fn SPENDER() -> ContractAddress {
    'spender'.try_into().unwrap()
}

fn ALICE() -> ContractAddress {
    'alice'.try_into().unwrap()
}

fn BOB() -> ContractAddress {
    'bob'.try_into().unwrap()
}

fn NAME() -> felt252 {
    'name'.try_into().unwrap()
}

fn SYMBOL() -> felt252 {
    'symbol'.try_into().unwrap()
}

fn INITIAL_HOLDER_1() -> ContractAddress {
    'initial_holder_1'.try_into().unwrap()
}

fn INITIAL_HOLDER_2() -> ContractAddress {
    'initial_holder_2'.try_into().unwrap()
}

fn INITIAL_HOLDERS() -> Span<ContractAddress> {
    array![INITIAL_HOLDER_1(), INITIAL_HOLDER_2()].span()
}

// Hold 5% of the supply each - reaching 10% of the supply, the maximum allowed
fn INITIAL_HOLDERS_AMOUNTS() -> Span<u256> {
    array![1_050_000 * pow_256(10, 18), 1_050_000 * pow_256(10, 18)].span()
}

fn DEPLOYER() -> ContractAddress {
    'deployer'.try_into().unwrap()
}

fn SALT() -> felt252 {
    'salty'.try_into().unwrap()
}

fn DEFAULT_INITIAL_SUPPLY() -> u256 {
    21_000_000 * pow_256(10, 18)
}

fn ETH_INITIAL_SUPPLY() -> u256 {
    500_000_000 * pow_256(10, 18)
}

fn LOCK_MANAGER_ADDRESS() -> ContractAddress {
    'lock_manager'.try_into().unwrap()
}

fn UNLOCK_TIME() -> u64 {
    starknet::get_block_timestamp() + DEFAULT_MIN_LOCKTIME
}

const ETH_DECIMALS: u8 = 18;
const TRANSFER_RESTRICTION_DELAY: u64 = 1000;
const MAX_PERCENTAGE_BUY_LAUNCH: u16 = 200; // 2%


fn CREATOR_COIN_FACTORY_ADDRESS() -> ContractAddress {
    'creator_coin_factory_address'.try_into().unwrap()
}

const DEFAULT_MIN_LOCKTIME: u64 = 15_721_200; // 6 months
const DEFAULT_LOCK_AMOUNT: u256 = 100;

fn LOCK_POSITION_ADDRESS() -> ContractAddress {
    'lock_position_address'.try_into().unwrap()
}

// Deployments

// Deploys a simple instance of the memcoin to test ERC20 basic entrypoints.
fn deploy_standalone_creator_coin() -> (ICreatorCoinDispatcher, ContractAddress) {
    // Deploy the locker associated with the creator_coin.

    // Deploy the creator_coin with the default parameters.
    let contract = declare('CreatorCoin');
    let mut calldata = array![OWNER().into(), NAME().into(), SYMBOL().into(),];
    Serde::serialize(@DEFAULT_INITIAL_SUPPLY(), ref calldata);
    let contract_address = contract.deploy(@calldata).expect('failed to deploy creator_coin');
    let creator_coin = ICreatorCoinDispatcher { contract_address };

    // Set the transaction_hash to an arbitrary value - used to test the
    // multicall buy prevention feature.
    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(1234);
    snforge_std::start_spoof(CheatTarget::One(creator_coin.contract_address), tx_info);

    (creator_coin, contract_address)
}


// Exchange

// Jediswap
fn deploy_jedi_amm_factory() -> ContractAddress {
    let pair_class = declare('PairC1');

    let mut constructor_calldata = Default::default();

    Serde::serialize(@pair_class.class_hash, ref constructor_calldata);
    Serde::serialize(@DEPLOYER(), ref constructor_calldata);
    let factory_class = declare('FactoryC1');

    let factory_address = factory_class
        .deploy_at(@constructor_calldata, JEDI_FACTORY_ADDRESS())
        .unwrap();

    factory_address
}

fn deploy_jedi_router(factory_address: ContractAddress) -> ContractAddress {
    let amm_router_class = declare('RouterC1');

    let mut router_constructor_calldata = Default::default();
    Serde::serialize(@factory_address, ref router_constructor_calldata);

    let exchange_address = amm_router_class
        .deploy_at(@router_constructor_calldata, JEDI_ROUTER_ADDRESS())
        .unwrap();

    exchange_address
}

fn deploy_jedi_amm_factory_and_router() -> (ContractAddress, ContractAddress) {
    let amm_factory_address = deploy_jedi_amm_factory();
    let exchange_address = deploy_jedi_router(amm_factory_address);

    (amm_factory_address, exchange_address)
}


// CreatorCoinFactory
fn deploy_creator_coin_factory(router_address: ContractAddress) -> ContractAddress {
    let locker_address = deploy_locker();
    let creator_coin_class_hash = declare('CreatorCoin').class_hash;

    // Declare availables Exchanges for this factory
    let mut amms: Array<(SupportedExchanges, ContractAddress)> = array![
        (SupportedExchanges::Jediswap, router_address),
    ];

    let contract = declare('Factory');
    let mut calldata = array![];
    let migrated_tokens: Span<ContractAddress> = array![].span();
    Serde::serialize(@creator_coin_class_hash, ref calldata);
    Serde::serialize(@locker_address, ref calldata);
    Serde::serialize(@amms.into(), ref calldata);
    Serde::serialize(@migrated_tokens, ref calldata);
    contract.deploy_at(@calldata, CREATOR_COIN_FACTORY_ADDRESS()).expect('Factory deployment failed')
}

// Locker

fn deploy_locker() -> ContractAddress {
    let mut calldata = Default::default();
    let locker_contract = declare('LockManager');
    let lock_position_class_hash = declare('LockPosition').class_hash;
    Serde::serialize(@DEFAULT_MIN_LOCKTIME, ref calldata);
    Serde::serialize(@lock_position_class_hash, ref calldata);
    locker_contract.deploy_at(@calldata, LOCK_MANAGER_ADDRESS()).expect('Locker deployment failed')
}

// ETH Token

fn deploy_eth() -> (ERC20ABIDispatcher, ContractAddress) {
    deploy_eth_with_owner(OWNER())
}

fn deploy_eth_with_owner(owner: ContractAddress) -> (ERC20ABIDispatcher, ContractAddress) {
    let token = declare('ERC20Token');
    let mut calldata = Default::default();
    Serde::serialize(@ETH_INITIAL_SUPPLY(), ref calldata);
    Serde::serialize(@owner, ref calldata);

    let address = token.deploy_at(@calldata, ETH_ADDRESS()).unwrap();
    let dispatcher = ERC20ABIDispatcher { contract_address: address, };
    (dispatcher, address)
}

fn deploy_token_from_class_at_address_with_owner(
    owner: ContractAddress, address: ContractAddress, class_address: ContractAddress
) -> (ERC20ABIDispatcher, ContractAddress) {
    let token = ContractClass { class_hash: get_class_hash(class_address) };
    let mut calldata = Default::default();
    Serde::serialize(@DEFAULT_INITIAL_SUPPLY(), ref calldata);
    Serde::serialize(@owner, ref calldata);

    let address = token.deploy_at(@calldata, address).unwrap();
    let dispatcher = ERC20ABIDispatcher { contract_address: address, };
    (dispatcher, address)
}

// CreatorCoin

fn deploy_creator_coin_through_factory_with_owner(
    owner: ContractAddress
) -> (ICreatorCoinDispatcher, ContractAddress) {
    // Required contracts
    let (_, router_address) = deploy_jedi_amm_factory_and_router();
    let creator_coin_factory_address = deploy_creator_coin_factory(router_address);
    let creator_coin_factory = IFactoryDispatcher { contract_address: creator_coin_factory_address };
    let (eth, eth_address) = deploy_eth_with_owner(owner);

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

    // Upon deployment, we mock the transaction_hash of the current tx.
    // This is because for each tx, we check during transfers whether a transfer already
    // occurred in the same tx. Rather than adding these lines in each test, we make it a default.
    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(1234);
    snforge_std::start_spoof(CheatTarget::One(creator_coin_address), tx_info);

    (ICreatorCoinDispatcher { contract_address: creator_coin_address }, creator_coin_address)
}


fn deploy_creator_coin_through_factory() -> (ICreatorCoinDispatcher, ContractAddress) {
    deploy_creator_coin_through_factory_with_owner(OWNER())
}

// Sets the env block timestamp to 1 and launches the creator_coin - so that launched_at is 1
// In this context, the owner of the factory is the address of the snforge test
fn deploy_and_launch_creator_coin() -> (ICreatorCoinDispatcher, ContractAddress) {
    let owner = OWNER();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };
    let eth = ERC20ABIDispatcher { contract_address: ETH_ADDRESS() };

    // approve spending of eth by factory
    let eth_amount: u256 = 1 * pow_256(10, 18); // 1 ETHER
    start_prank(CheatTarget::One(eth.contract_address), owner);
    eth.approve(factory.contract_address, eth_amount);
    stop_prank(CheatTarget::One(eth.contract_address));

    start_prank(CheatTarget::One(factory.contract_address), owner);
    start_warp(CheatTarget::One(creator_coin_address), 1);
    let pool_address = factory
        .launch_on_jediswap(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: eth.contract_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            eth_amount,
            DEFAULT_MIN_LOCKTIME,
        );
    stop_prank(CheatTarget::One(factory.contract_address));
    stop_warp(CheatTarget::One(creator_coin_address));
    (creator_coin, creator_coin_address)
}


impl DefaultTxInfoMock of Default<TxInfoMock> {
    fn default() -> TxInfoMock {
        TxInfoMock {
            version: Option::None(()),
            account_contract_address: Option::None(()),
            max_fee: Option::None(()),
            signature: Option::None(()),
            transaction_hash: Option::None(()),
            chain_id: Option::None(()),
            nonce: Option::None(()),
            resource_bounds: Option::None(()),
            tip: Option::None(()),
            paymaster_data: Option::None(()),
            nonce_data_availability_mode: Option::None(()),
            fee_data_availability_mode: Option::None(()),
            account_deployment_data: Option::None(()),
        }
    }
}


// Math
fn pow_256(self: u256, mut exponent: u8) -> u256 {
    if self.is_zero() {
        return 0;
    }
    let mut result = 1;
    let mut base = self;

    loop {
        if exponent & 1 == 1 {
            result = result * base;
        }

        exponent = exponent / 2;
        if exponent == 0 {
            break result;
        }

        base = base * base;
    }
}
