use core::traits::TryInto;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    ContractClass, ContractClassTrait, CheatTarget, declare, start_prank, stop_prank, TxInfoMock,
    start_warp, stop_warp, get_class_hash
};
use starknet::ContractAddress;
use creator_coin::exchanges::{SupportedExchanges};
use creator_coin::factory::{IFactoryDispatcher, IFactoryDispatcherTrait, LaunchParameters};
use creator_coin::tests::addresses::{ETH_ADDRESS, EKUBO_CORE, EKUBO_POSITIONS, EKUBO_REGISTRY};
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

const ETH_DECIMALS: u8 = 18;
const TRANSFER_RESTRICTION_DELAY: u64 = 1000;
const MAX_PERCENTAGE_BUY_LAUNCH: u16 = 200; // 2%


fn CREATOR_COIN_FACTORY_ADDRESS() -> ContractAddress {
    'creator_coin_factory_address'.try_into().unwrap()
}

// Placeholder EkuboLauncher address registered in the factory for unit tests.
// The full Ekubo launch path is exercised in the fork tests; unit tests only
// reach launch validations that panic before the adapter is ever called.
fn EKUBO_LAUNCHER_ADDRESS() -> ContractAddress {
    'ekubo_launcher'.try_into().unwrap()
}

// Deployments

// Deploys a simple instance of the creator_coin to test ERC20 basic entrypoints.
fn deploy_standalone_creator_coin() -> (ICreatorCoinDispatcher, ContractAddress) {
    // Deploy the creator_coin with the default parameters.
    let contract = declare('CreatorCoin');
    let mut calldata = array![OWNER().into(), NAME().into(), SYMBOL().into(),];
    Serde::serialize(@DEFAULT_INITIAL_SUPPLY(), ref calldata);
    let contract_address = contract.deploy(@calldata).expect('failed to deploy creator_coin');
    let creator_coin = ICreatorCoinDispatcher { contract_address };

    (creator_coin, contract_address)
}


// CreatorCoinFactory
fn deploy_creator_coin_factory() -> ContractAddress {
    let creator_coin_class_hash = declare('CreatorCoin').class_hash;

    // Declare the available Exchanges for this factory (Ekubo only).
    let mut exchanges: Array<(SupportedExchanges, ContractAddress)> = array![
        (SupportedExchanges::Ekubo, EKUBO_LAUNCHER_ADDRESS()),
    ];

    let contract = declare('Factory');
    let mut calldata = array![];
    Serde::serialize(@creator_coin_class_hash, ref calldata);
    Serde::serialize(@exchanges.into(), ref calldata);
    contract.deploy_at(@calldata, CREATOR_COIN_FACTORY_ADDRESS()).expect('Factory deployment failed')
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
    let creator_coin_factory_address = deploy_creator_coin_factory();
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

    (ICreatorCoinDispatcher { contract_address: creator_coin_address }, creator_coin_address)
}


fn deploy_creator_coin_through_factory() -> (ICreatorCoinDispatcher, ContractAddress) {
    deploy_creator_coin_through_factory_with_owner(OWNER())
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
