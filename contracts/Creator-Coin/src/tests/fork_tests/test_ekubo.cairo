use core::debug::PrintTrait;
use core::traits::TryInto;
use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::interfaces::router::{Depth, Delta, RouteNode, TokenAmount};
use ekubo::interfaces::router::{IRouterDispatcher, IRouterDispatcherTrait};
use ekubo::types::bounds::Bounds;
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    start_prank, stop_prank, start_spoof, stop_spoof, spy_events, SpyOn, EventSpy, EventAssertions,
    CheatTarget, TxInfoMock
};
use starknet::ContractAddress;
use creator_coin::exchanges::SupportedExchanges;
use creator_coin::exchanges::ekubo::launcher::{
    IEkuboLauncherDispatcher, IEkuboLauncherDispatcherTrait, EkuboLP
};
use creator_coin::exchanges::ekubo_adapter::EkuboPoolParameters;
use creator_coin::factory::{IFactoryDispatcher, IFactoryDispatcherTrait, Factory, LaunchParameters};
use creator_coin::locker::LockPosition;
use creator_coin::locker::interface::{ILockManagerDispatcher, ILockManagerDispatcherTrait};
use creator_coin::tests::addresses::{EKUBO_CORE};
use creator_coin::tests::fork_tests::utils::{
    deploy_creator_coin_through_factory_with_owner, sort_tokens, EKUBO_LAUNCHER_ADDRESS,
    EKUBO_ROUTER_ADDRESS, deploy_token0_with_owner, deploy_eth_with_owner
};
use creator_coin::tests::unit_tests::utils::{
    OWNER, DEFAULT_MIN_LOCKTIME, pow_256, LOCK_MANAGER_ADDRESS, CREATOR_COIN_FACTORY_ADDRESS, RECIPIENT,
    JEDI_ROUTER_ADDRESS, ALICE, DefaultTxInfoMock, TRANSFER_RESTRICTION_DELAY,
    MAX_PERCENTAGE_BUY_LAUNCH, NAME, SYMBOL, INITIAL_HOLDERS, INITIAL_HOLDERS_AMOUNTS,
    DEFAULT_INITIAL_SUPPLY, SALT, deploy_token_from_class_at_address_with_owner,
    deploy_jedi_amm_factory_and_router, deploy_creator_coin_factory
};
use creator_coin::token::interface::{
    ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
};
use creator_coin::token::creator_coin::{LiquidityType, LiquidityParameters};
use creator_coin::utils::math::PercentageMath;
use creator_coin::utils::sum;

//! Contains the integration tests for ekubo.
//! We test different situations: token0 is the quote, token1 is the quote, price below1, price above1.

//@ price: creator_coin per eth
fn launch_creator_coin_on_ekubo(
    quote_address: ContractAddress,
    fee: u128,
    tick_spacing: u128,
    starting_price: i129,
    bound: u128,
    quote_to_deposit: u256
) -> (ContractAddress, u64, EkuboLP) {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };

    start_prank(CheatTarget::One(quote_address), owner);
    ERC20ABIDispatcher { contract_address: quote_address }
        .transfer(factory.contract_address, quote_to_deposit);
    stop_prank(CheatTarget::One(quote_address));

    let (id, position) = factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters { fee, tick_spacing, starting_price, bound }
        );

    (creator_coin_address, id, position)
}

fn swap_tokens_on_ekubo(
    token_in_address: ContractAddress,
    amount_in: u256,
    is_token1: bool,
    price_above_1: bool,
    token_out_address: ContractAddress,
    owner: ContractAddress,
    pool_key: PoolKey
) {
    let token_in = ERC20ABIDispatcher { contract_address: token_in_address };
    let token_out = ERC20ABIDispatcher { contract_address: token_out_address };

    let max_sqrt_ratio_limit = 6277100250585753475930931601400621808602321654880405518632;
    let min_sqrt_ratio_limit = 18446748437148339061;

    let (sqrt_limit_swap1, sqrt_limit_swap2) = if is_token1 {
        (max_sqrt_ratio_limit, min_sqrt_ratio_limit)
    } else {
        (min_sqrt_ratio_limit, max_sqrt_ratio_limit)
    };

    // First swap:
    // We swap quote (token1) for CREATOR_COIN (token0)
    // The initial price of the pool is 0.01quote/CREATOR_COIN = 100CREATOR_COIN/quote.
    // so the received amounts should be around 100x the amount of quote sent
    // with a 5% margin of error for the price impact.
    // since the pool price is expressend in quote/CREATOR_COIN, the price should move upwards (more quote for 1 creator_coin)
    let router_address = EKUBO_ROUTER_ADDRESS();
    let ekubo_router = IRouterDispatcher { contract_address: router_address };
    let ekubo_clearer = IClearDispatcher { contract_address: router_address };
    let first_amount_in = amount_in;

    // We transfer tokens to the swapper contract, which performs the swap
    // This is required the way the swapper contract is coded.
    // It then sends back the funds to the caller
    start_prank(CheatTarget::One(token_in.contract_address), owner);
    token_in.transfer(router_address, first_amount_in);
    stop_prank(CheatTarget::One(token_in.contract_address));

    // If CREATOR_COIN/quote > 1 and we swap token1 for token0,
    // OR if CREATOR_COIN/quote < 1 and we swap token0 for token1,
    // we expect to receive 0.01x the amount of quote sent with a 5% margin of error
    let expected_output = if price_above_1 {
        PercentageMath::percent_mul(first_amount_in, 95)
    } else {
        PercentageMath::percent_mul(100 * first_amount_in, 9500)
    };

    let route_node = RouteNode {
        pool_key: pool_key, sqrt_ratio_limit: sqrt_limit_swap1, skip_ahead: 0
    };

    let token_amount = TokenAmount {
        token: token_in.contract_address,
        amount: i129 { mag: first_amount_in.low, sign: false // positive sign is exact input
         },
    };
    ekubo_router.swap(route_node, token_amount);
    ekubo_clearer.clear(IERC20Dispatcher { contract_address: token_out.contract_address });

    // Second swap:

    // We swap CREATOR_COIN (token0) for quote (token1)
    // the expected amount should be the initial amount,
    // minus the fees of the pool.
    let second_amount_in = token_out.balance_of(owner);
    let second_expected_output = PercentageMath::percent_mul(first_amount_in, 9940);
    let balance_token_in_before = token_in.balance_of(owner);

    start_prank(CheatTarget::One(token_out.contract_address), owner);
    token_out.transfer(router_address, second_amount_in);
    stop_prank(CheatTarget::One(token_out.contract_address));

    let route_node = RouteNode {
        pool_key: pool_key, sqrt_ratio_limit: sqrt_limit_swap2, skip_ahead: 0
    };

    let token_amount = TokenAmount {
        token: token_out.contract_address,
        amount: i129 { mag: second_amount_in.low, sign: false // exact input
         },
    };

    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(456);
    start_spoof(CheatTarget::One(token_out.contract_address), tx_info);

    ekubo_router.swap(route_node, token_amount);
    ekubo_clearer.clear(IERC20Dispatcher { contract_address: token_in.contract_address });

    let token_in_received = token_in.balance_of(owner) - balance_token_in_before;
    assert(token_in_received >= second_expected_output, 'swap output too low');
}

#[test]
#[fork("Mainnet")]
fn test_locked_liquidity_ekubo() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = 215_000
        * pow_256(10, 18); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    let (locker_address, locked_type) = factory.locked_liquidity(creator_coin_address).unwrap();
    assert(locker_address == EKUBO_LAUNCHER_ADDRESS(), 'wrong locker address');
    match locked_type {
        LiquidityType::JediERC20(_) => panic_with_felt252('wrong liquidity type'),
        LiquidityType::StarkDeFiERC20(_) => panic_with_felt252('wrong liquidity type'),
        LiquidityType::EkuboNFT(id) => ()
    }
}

#[test]
#[fork("Mainnet")]
fn test_launch_creator_coin() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = PercentageMath::percent_mul(
        2_100_000 * pow_256(10, 16), 10_120
    ); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let mut spy = spy_events(SpyOn::One(CREATOR_COIN_FACTORY_ADDRESS()));
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    ); // 0.3/0.6%
    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };

    let (token0, token1) = sort_tokens(quote_address, creator_coin_address);
    let pool_key = PoolKey {
        token0: position.pool_key.token0,
        token1: position.pool_key.token1,
        fee: position.pool_key.fee.try_into().unwrap(),
        tick_spacing: position.pool_key.tick_spacing.try_into().unwrap(),
        extension: position.pool_key.extension
    };

    let core = ICoreDispatcher { contract_address: EKUBO_CORE() };
    let liquidity = core.get_pool_liquidity(pool_key);
    let price = core.get_pool_price(pool_key);
    let reserve_creator_coin = creator_coin.balance_of(core.contract_address);
    let reserve_quote = ERC20ABIDispatcher { contract_address: quote_address }
        .balance_of(core.contract_address);

    assert(reserve_quote >= PercentageMath::percent_mul(quote_to_deposit, 9980), 'reserve too low');
    // No need to check +2% percent

    assert(reserve_quote >= PercentageMath::percent_mul(quote_to_deposit, 9980), 'reserve too low');
    // No need to check +2% percent

    // Verify that the reserve of creator_coin is within 0.1% of the (total supply minus the team allocation)
    // When providing liquidity, if the liquidity provided doesn't exactly match the repartition between
    // bounds, a very small amount is returned.
    let team_allocation = creator_coin.get_team_allocation();
    let expected_reserve_lower_bound = PercentageMath::percent_mul(
        creator_coin.totalSupply() - team_allocation, 9990,
    );
    assert(reserve_creator_coin > expected_reserve_lower_bound, 'reserves holds too few token');

    // Check LP position tracked
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    let lp_positions = ekubo_launcher.launched_tokens(owner);
    assert(lp_positions.len() == 1, 'should have 1 LP position');
    let lp_details = ekubo_launcher.liquidity_position_details(*lp_positions[0]);
    assert(lp_details.owner == owner, 'wrong owner');
    assert(lp_details.quote_address == quote_address, 'wrong quote');
    assert(lp_details.pool_key == pool_key, 'wrong pool key');
    assert(
        lp_details
            .bounds == Bounds { lower: starting_price, upper: i129 { sign: false, mag: 88719042 } },
        'wrong bounds '
    );

    let liquidity_parameters = creator_coin.launched_with_liquidity_parameters().unwrap();

    match liquidity_parameters {
        LiquidityParameters::Ekubo(ekubo_liquidity_parameters) => {
            assert(ekubo_liquidity_parameters.quote_address == quote_address, 'Bad quote address');
            assert(
                ekubo_liquidity_parameters.ekubo_pool_parameters.fee == position.pool_key.fee,
                'Bad ekubo fee'
            );
            assert(
                ekubo_liquidity_parameters
                    .ekubo_pool_parameters
                    .tick_spacing == position
                    .pool_key
                    .tick_spacing,
                'Bad ekubo tick spacing'
            );
            assert(
                ekubo_liquidity_parameters.ekubo_pool_parameters.starting_price == starting_price,
                'Bad ekubo starting tick'
            );
            assert(
                ekubo_liquidity_parameters.ekubo_pool_parameters.bound == 88719042,
                'Bad ekubo bound'
            );
        },
        LiquidityParameters::Jediswap(jediswap_liquidity_parameters) => panic_with_felt252(
            'wrong liquidity parameters type'
        ),
        LiquidityParameters::StarkDeFi(stark_defi_liquidity_parameters) => panic_with_felt252(
            'wrong liquidity parameters type'
        )
    }

    // Check events
    spy
        .assert_emitted(
            @array![
                (
                    CREATOR_COIN_FACTORY_ADDRESS(),
                    Factory::Event::CreatorCoinLaunched(
                        Factory::CreatorCoinLaunched {
                            creator_coin_address, quote_token: quote_address, exchange_name: 'Ekubo'
                        }
                    )
                )
            ]
        );
}

#[test]
#[fork("Mainnet")]
fn test_transfer_ekuboLP_position() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = PercentageMath::percent_mul(
        2_100_000 * pow_256(10, 16), 10_120
    ); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );

    // Execute the transfer of position
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    ekubo_launcher.transfer_position_ownership(id, ALICE());

    // Check that LP transfer to Alice is successful
    assert(
        ekubo_launcher.launched_tokens(ALICE()).len() == 1
            && ekubo_launcher.launched_tokens(owner).len() == 0,
        'transfer failed'
    );

    assert(
        ekubo_launcher.liquidity_position_details(id).owner == ALICE(),
        'launcher storage not updated'
    );
}

#[test]
#[fork("Mainnet")]
fn test_launch_creator_coin_token0_price_below_1() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = PercentageMath::percent_mul(
        2_100_000 * pow_256(10, 16), 10_120
    ); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    // accounting for the 0.6% tick spacing

    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    // Collect and check the fees right before doing the swaps and check the diff after
    let recipient = RECIPIENT();
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    ekubo_launcher.withdraw_fees(id, recipient);
    let pre_balance_quote = quote.balance_of(recipient);
    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };
    let quote = ERC20ABIDispatcher { contract_address: quote_address };

    let (token0, token1) = sort_tokens(quote_address, creator_coin_address);
    let pool_key = PoolKey {
        token0: position.pool_key.token0,
        token1: position.pool_key.token1,
        fee: position.pool_key.fee.try_into().unwrap(),
        tick_spacing: position.pool_key.tick_spacing.try_into().unwrap(),
        extension: position.pool_key.extension
    };

    // Check that swaps work correctly
    let amount_in = 4200 * pow_256(10, 18); // swapping ~ 2% of the total supply
    swap_tokens_on_ekubo(
        token_in_address: quote_address,
        :amount_in,
        is_token1: true,
        price_above_1: false,
        token_out_address: creator_coin_address,
        owner: owner,
        pool_key: pool_key
    );

    // Change tx hash to avoid multicall detection
    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(1);
    start_spoof(CheatTarget::One(creator_coin_address), tx_info);

    // Test that the owner of the LP can withdraw fees from the launcher
    ekubo_launcher.withdraw_fees(id, recipient);
    let balance_of_creator_coin = creator_coin.balance_of(recipient);
    let post_balance_quote = quote.balance_of(recipient);
    let balance_quote_diff = post_balance_quote - pre_balance_quote;
    assert(balance_of_creator_coin == 0, 'coin shouldnt collect fees');
    // should get ~ 0.2% of the fees on that swap, since there is still remaining liquidity of the initial position.
    assert(
        balance_quote_diff >= PercentageMath::percent_mul(amount_in, 20),
        'not enough fees not collected'
    );
}

#[test]
#[fork("Mainnet")]
fn test_launch_creator_coin_token1_price_below_1() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_token0_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = PercentageMath::percent_mul(
        2_100_000 * pow_256(10, 16), 10_120
    ); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );

    // Collect and check the fees right before doing the swaps and check the diff after
    let recipient = RECIPIENT();
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    ekubo_launcher.withdraw_fees(id, recipient);
    let pre_balance_quote = quote.balance_of(recipient);
    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };
    let quote = ERC20ABIDispatcher { contract_address: quote_address };
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };

    // Test that swaps work correctly

    let (token0_address, token1_address) = sort_tokens(quote_address, creator_coin_address);
    assert(token0_address == quote_address, 'token0 not quote');

    let pool_key = PoolKey {
        token0: position.pool_key.token0,
        token1: position.pool_key.token1,
        fee: position.pool_key.fee.try_into().unwrap(),
        tick_spacing: position.pool_key.tick_spacing.try_into().unwrap(),
        extension: position.pool_key.extension
    };

    let core = ICoreDispatcher { contract_address: EKUBO_CORE() };
    let liquidity = core.get_pool_liquidity(pool_key);
    let price = core.get_pool_price(pool_key);
    let reserve_creator_coin = creator_coin.balance_of(core.contract_address);
    let reserve_quote = ERC20ABIDispatcher { contract_address: quote_address }
        .balance_of(core.contract_address);

    assert(
        reserve_quote >= PercentageMath::percent_mul(quote_to_deposit, 9980), 'quote reserve low'
    );

    // Verify that the reserve of creator_coin is within 0.1% of the (total supply minus the team allocation)
    let team_allocation = creator_coin.get_team_allocation();
    let expected_reserve_lower_bound = PercentageMath::percent_mul(
        creator_coin.totalSupply() - team_allocation, 9990,
    );
    assert(reserve_creator_coin > expected_reserve_lower_bound, 'reserves holds too few token');

    let amount_in = 4200 * pow_256(10, 18); // swapping ~ 2% of the total supply
    swap_tokens_on_ekubo(
        token_in_address: quote_address,
        :amount_in,
        is_token1: false,
        price_above_1: false,
        token_out_address: creator_coin_address,
        owner: owner,
        pool_key: pool_key
    );

    // Change tx hash to avoid multicall detection
    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(1);
    start_spoof(CheatTarget::One(creator_coin_address), tx_info);

    // Test that the owner of the LP can withdraw fees from the launcher
    ekubo_launcher.withdraw_fees(id, recipient);
    let balance_of_creator_coin = creator_coin.balance_of(recipient);
    let post_balance_quote = quote.balance_of(recipient);
    let balance_quote_diff = post_balance_quote - pre_balance_quote;
    assert(balance_of_creator_coin == 0, 'coin shouldnt collect fees');
    // should get ~ 0.2% of the fees on that swap, since there is still remaining liquidity of the initial position.
    assert(
        balance_quote_diff >= PercentageMath::percent_mul(amount_in, 20),
        'not enough fees not collected'
    );
}

#[test]
#[fork("Mainnet")]
fn test_launch_creator_coin_token0_price_above_1() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: false, mag: 4600158 }; // 100quote/CREATOR_COIN
    let quote_to_deposit = 2_112_600
        * pow_256(10, 20); // (10%)*1.006 of the total supply at a price of 100quote/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );

    // Collect and check the fees right before doing the swaps and check the diff after
    let recipient = RECIPIENT();
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    ekubo_launcher.withdraw_fees(id, recipient);
    let pre_balance_quote = quote.balance_of(recipient);
    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };
    let quote = ERC20ABIDispatcher { contract_address: quote_address };
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };

    // Test that swaps work correctly

    let (token0, token1) = sort_tokens(quote.contract_address, creator_coin_address);

    let pool_key = PoolKey {
        token0: position.pool_key.token0,
        token1: position.pool_key.token1,
        fee: position.pool_key.fee.try_into().unwrap(),
        tick_spacing: position.pool_key.tick_spacing.try_into().unwrap(),
        extension: position.pool_key.extension
    };

    let core = ICoreDispatcher { contract_address: EKUBO_CORE() };
    let liquidity = core.get_pool_liquidity(pool_key);
    let price = core.get_pool_price(pool_key);
    let reserve_creator_coin = creator_coin.balance_of(core.contract_address);
    let reserve_quote = ERC20ABIDispatcher { contract_address: quote_address }
        .balance_of(core.contract_address);

    assert(
        reserve_quote >= PercentageMath::percent_mul(quote_to_deposit, 9900), 'quote reserve low'
    );
    // Changed percent range to %1 here, it was reverting lower.

    // Verify that the reserve of creator_coin is within 0.1% of the (total supply minus the team allocation)
    let team_allocation = creator_coin.get_team_allocation();
    let expected_reserve_lower_bound = PercentageMath::percent_mul(
        creator_coin.totalSupply() - team_allocation, 9990,
    );
    assert(reserve_creator_coin > expected_reserve_lower_bound, 'reserves holds too few token');

    // Test that swaps work correctly
    let amount_in = 42_000_000 * pow_256(10, 18); // swapping ~ 2% of the total supply
    swap_tokens_on_ekubo(
        token_in_address: quote_address,
        :amount_in,
        is_token1: true,
        price_above_1: true,
        token_out_address: creator_coin_address,
        owner: owner,
        pool_key: pool_key
    );

    // Change tx hash to avoid multicall detection, as the fee collection
    // sends creator_coins to the EkuboLauncher contract
    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(1);
    start_spoof(CheatTarget::One(creator_coin_address), tx_info);

    // Test that the owner of the LP can withdraw fees from the launcher
    ekubo_launcher.withdraw_fees(id, recipient);
    let balance_of_creator_coin = creator_coin.balance_of(recipient);
    let post_balance_quote = quote.balance_of(recipient);
    let balance_quote_diff = post_balance_quote - pre_balance_quote;
    assert(balance_of_creator_coin == 0, 'coin shouldnt collect fees');
    // should get ~ 0.2% of the fees on that swap, since there is still remaining liquidity of the initial position.
    assert(
        balance_quote_diff >= PercentageMath::percent_mul(amount_in, 20),
        'not enough fees not collected'
    );
}

#[test]
#[fork("Mainnet")]
fn test_launch_creator_coin_token1_price_above_1() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_token0_with_owner(owner);
    let starting_price = i129 { sign: false, mag: 4600158 }; // 100quote/CREATOR_COIN
    let quote_to_deposit = 2_112_600
        * pow_256(10, 20); // (10%)*1.006 of the total supply at a price of 100quote/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );

    // Collect and check the fees right before doing the swaps and check the diff after
    let recipient = RECIPIENT();
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    ekubo_launcher.withdraw_fees(id, recipient);
    let pre_balance_quote = quote.balance_of(recipient);
    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };
    let quote = ERC20ABIDispatcher { contract_address: quote_address };
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };

    // Test that swaps work correctly

    let (token0_address, token1_address) = sort_tokens(quote.contract_address, creator_coin_address);
    assert(token0_address == quote.contract_address, 'token0 not quote');

    let pool_key = PoolKey {
        token0: position.pool_key.token0,
        token1: position.pool_key.token1,
        fee: position.pool_key.fee.try_into().unwrap(),
        tick_spacing: position.pool_key.tick_spacing.try_into().unwrap(),
        extension: position.pool_key.extension
    };

    let core = ICoreDispatcher { contract_address: EKUBO_CORE() };
    let liquidity = core.get_pool_liquidity(pool_key);
    let price = core.get_pool_price(pool_key);
    let reserve_creator_coin = creator_coin.balance_of(core.contract_address);
    let reserve_token0 = ERC20ABIDispatcher { contract_address: quote_address }
        .balance_of(core.contract_address);

    assert(
        reserve_token0 >= PercentageMath::percent_mul(quote_to_deposit, 9900), 'quote reserve low'
    );
    // Changed percent range to %1 here, it was reverting lower.

    // Verify that the reserve of creator_coin is within 0.1% of the (total supply minus the team allocation)
    let team_allocation = creator_coin.get_team_allocation();
    let expected_reserve_lower_bound = PercentageMath::percent_mul(
        creator_coin.totalSupply() - team_allocation, 9990,
    );
    assert(reserve_creator_coin > expected_reserve_lower_bound, 'reserves holds too few token');

    // Check that swaps work correctly
    let amount_in = 42_000_000 * pow_256(10, 18); // swapping ~ 2% of the total supply
    swap_tokens_on_ekubo(
        token_in_address: quote_address,
        :amount_in,
        is_token1: false,
        price_above_1: true,
        token_out_address: creator_coin_address,
        owner: owner,
        pool_key: pool_key
    );

    // Change tx hash to avoid multicall detection
    let mut tx_info: TxInfoMock = Default::default();
    tx_info.transaction_hash = Option::Some(1);
    start_spoof(CheatTarget::One(creator_coin_address), tx_info);

    // Test that the owner of the LP can withdraw fees from the launcher
    ekubo_launcher.withdraw_fees(id, recipient);
    let balance_of_creator_coin = creator_coin.balance_of(recipient);
    let post_balance_quote = quote.balance_of(recipient);
    let balance_quote_diff = post_balance_quote - pre_balance_quote;
    assert(balance_of_creator_coin == 0, 'coin shouldnt collect fees');
    // should get ~ 0.2% of the fees on that swap, since there is still remaining liquidity of the initial position.
    assert(
        balance_quote_diff >= PercentageMath::percent_mul(amount_in, 20),
        'not enough fees not collected'
    );
}

#[test]
#[fork("Mainnet")]
fn test_launch_creator_coin_with_pool_1percent() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = PercentageMath::percent_mul(
        2_100_000 * pow_256(10, 16), 10_200 //2% extra quote
    ); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0x28f5c28f5c28f600000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );
    let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };

    let (token0, token1) = sort_tokens(quote_address, creator_coin_address);
    let pool_key = PoolKey {
        token0: position.pool_key.token0,
        token1: position.pool_key.token1,
        fee: position.pool_key.fee.try_into().unwrap(),
        tick_spacing: position.pool_key.tick_spacing.try_into().unwrap(),
        extension: position.pool_key.extension
    };
    let core = ICoreDispatcher { contract_address: EKUBO_CORE() };
    let liquidity = core.get_pool_liquidity(pool_key);
    let price = core.get_pool_price(pool_key);
    let reserve_creator_coin = creator_coin.balance_of(core.contract_address);
    let reserve_quote = ERC20ABIDispatcher { contract_address: quote_address }
        .balance_of(core.contract_address);
    assert(reserve_quote >= PercentageMath::percent_mul(quote_to_deposit, 9980), 'reserve too low');

    // Verify that the reserve of creator_coin is within 0.1% of the (total supply minus the team allocation)
    // because there can be slight imprecisions when swapping with ekubo
    let team_allocation = creator_coin.get_team_allocation();
    let expected_reserve_lower_bound = PercentageMath::percent_mul(
        creator_coin.totalSupply() - team_allocation, 9990,
    );
    assert(reserve_creator_coin > expected_reserve_lower_bound, 'reserves holds too few token');
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_not_owner_cant_withdraw_fees() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = 215_000
        * pow_256(10, 18); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };

    let recipient = RECIPIENT();
    let caller = 'not owner'.try_into().unwrap();
    start_prank(CheatTarget::One(ekubo_launcher.contract_address), caller);
    ekubo_launcher.withdraw_fees(id, recipient);
    stop_prank(CheatTarget::One(ekubo_launcher.contract_address));
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Starting tick cannot be 0',))]
fn test_cant_launch_with_0_starting_price() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 0 }; // 0.0ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address, 0xc49ba5e353f7d00000000000000000, 5982, starting_price, 88719042, 0
    );
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Already launched',))]
fn test_cant_launch_twice() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN
    let quote_to_deposit = 215_000
        * pow_256(10, 18); // 10% of the total supply at a price of 0.01ETH/CREATOR_COIN
    let (creator_coin_address, id, position) = launch_creator_coin_on_ekubo(
        quote_address,
        0xc49ba5e353f7d00000000000000000,
        5982,
        starting_price,
        88719042,
        quote_to_deposit
    );

    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    start_prank(CheatTarget::One(factory.contract_address), owner);
    // This will fail as the ownership of the creator_coin has been renounced.
    let (id, position) = factory
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
                fee: 0xc49ba5e353f7d00000000000000000,
                tick_spacing: 5982,
                starting_price,
                bound: 88719042
            }
        );
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Token not deployed by factory',))]
fn test_launch_not_creator_coin_ekubo() {
    let owner = snforge_std::test_address();
    let (quote, quote_address) = deploy_eth_with_owner(owner);
    let (_, fake_creator_coin_address) = deploy_token_from_class_at_address_with_owner(
        OWNER(), 'random'.try_into().unwrap(), quote_address
    );
    let starting_price = i129 { sign: true, mag: 4600158 }; // 0.01ETH/CREATOR_COIN

    let factory = IFactoryDispatcher {
        contract_address: deploy_creator_coin_factory(JEDI_ROUTER_ADDRESS())
    };
    let ekubo_launcher = IEkuboLauncherDispatcher { contract_address: EKUBO_LAUNCHER_ADDRESS() };
    start_prank(CheatTarget::One(factory.contract_address), owner);
    // This will fail as the ownership of the creator_coin has been renounced.
    let (id, position) = factory
        .launch_on_ekubo(
            LaunchParameters {
                creator_coin_address: fake_creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            EkuboPoolParameters {
                fee: 0xc49ba5e353f7d00000000000000000,
                tick_spacing: 5982,
                starting_price,
                bound: 88719042
            }
        );
}


#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Quote token is creator_coin',))]
fn test_launch_creator_coin_quote_creator_coin_ekubo() {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    // Create second creator_coin used as quote
    start_prank(CheatTarget::One(factory.contract_address), owner);
    let quote_address = factory
        .create_creator_coin(
            owner: owner,
            name: NAME(),
            symbol: SYMBOL(),
            initial_supply: DEFAULT_INITIAL_SUPPLY(),
            contract_address_salt: SALT() + 1,
        );
    stop_prank(CheatTarget::One(factory.contract_address));
    let quote = ERC20ABIDispatcher { contract_address: quote_address }; // actually a creator_coin

    // Try to launch again
    // approve spending of eth by factory
    let quote_amount: u256 = 1 * pow_256(10, 18); // 1 ETHER
    let factory_balance_quote = quote.balanceOf(factory.contract_address);
    start_prank(CheatTarget::One(quote.contract_address), owner);
    quote.approve(factory.contract_address, quote_amount);
    stop_prank(CheatTarget::One(quote.contract_address));

    start_prank(CheatTarget::One(factory.contract_address), owner);
    let pair_address = factory
        .launch_on_jediswap(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: quote.contract_address,
                initial_holders: INITIAL_HOLDERS(),
                initial_holders_amounts: INITIAL_HOLDERS_AMOUNTS(),
            },
            quote_amount,
            DEFAULT_MIN_LOCKTIME,
        );
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Holders len dont match amounts',))]
fn test_launch_creator_coin_ekubo_initial_holders_len_mismatch() {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    let (quote, quote_address) = deploy_token0_with_owner(owner);
    // approve spending of eth by factory
    let quote_amount: u256 = 1 * pow_256(10, 18); // 1 ETHER
    let factory_balance_quote = quote.balanceOf(factory.contract_address);
    start_prank(CheatTarget::One(quote.contract_address), owner);
    quote.approve(factory.contract_address, quote_amount);
    stop_prank(CheatTarget::One(quote.contract_address));

    start_prank(CheatTarget::One(factory.contract_address), owner);
    let pair_address = factory
        .launch_on_jediswap(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: quote.contract_address,
                initial_holders: array![
                    'initial_holder_1'.try_into().unwrap(), 'initial_holder_2'.try_into().unwrap()
                ]
                    .span(),
                initial_holders_amounts: array![50_u256, 20_u256, 10_u256].span(),
            },
            quote_amount,
            DEFAULT_MIN_LOCKTIME,
        );
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Max number of holders reached',))]
fn test_launch_creator_coin_ekubo_max_holders_reached() {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    let initial_holders: Array<ContractAddress> = array![
        'initial_holder_1'.try_into().unwrap(),
        'initial_holder_2'.try_into().unwrap(),
        'initial_holder_3'.try_into().unwrap(),
        'initial_holder_4'.try_into().unwrap(),
        'initial_holder_5'.try_into().unwrap(),
        'initial_holder_6'.try_into().unwrap(),
        'initial_holder_7'.try_into().unwrap(),
        'initial_holder_8'.try_into().unwrap(),
        'initial_holder_9'.try_into().unwrap(),
        'initial_holder_10'.try_into().unwrap(),
        'initial_holder_11'.try_into().unwrap()
    ];
    let initial_holders_amounts: Array<u256> = array![1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

    let (quote, quote_address) = deploy_token0_with_owner(owner);
    // approve spending of eth by factory
    let quote_amount: u256 = 1 * pow_256(10, 18); // 1 ETHER
    let factory_balance_quote = quote.balanceOf(factory.contract_address);
    start_prank(CheatTarget::One(quote.contract_address), owner);
    quote.approve(factory.contract_address, quote_amount);
    stop_prank(CheatTarget::One(quote.contract_address));

    start_prank(CheatTarget::One(factory.contract_address), owner);
    let pair_address = factory
        .launch_on_jediswap(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: quote.contract_address,
                initial_holders: initial_holders.span(),
                initial_holders_amounts: initial_holders_amounts.span(),
            },
            quote_amount,
            DEFAULT_MIN_LOCKTIME,
        );
}

#[test]
#[fork("Mainnet")]
#[should_panic(expected: ('Max team allocation reached',))]
fn test_launch_creator_coin_ekubo_too_much_team_alloc() {
    let owner = snforge_std::test_address();
    let (creator_coin, creator_coin_address) = deploy_creator_coin_through_factory_with_owner(owner);
    let factory = IFactoryDispatcher { contract_address: CREATOR_COIN_FACTORY_ADDRESS() };

    let alloc_holder_1 = 1_050_000 * pow_256(10, 18);
    let alloc_holder_2 = 1_050_001 * pow_256(10, 18);

    let (quote, quote_address) = deploy_token0_with_owner(owner);
    // approve spending of eth by factory
    let quote_amount: u256 = 1 * pow_256(10, 18); // 1 ETHER
    let factory_balance_quote = quote.balanceOf(factory.contract_address);
    start_prank(CheatTarget::One(quote.contract_address), owner);
    quote.approve(factory.contract_address, quote_amount);
    stop_prank(CheatTarget::One(quote.contract_address));

    start_prank(CheatTarget::One(factory.contract_address), owner);
    let pair_address = factory
        .launch_on_jediswap(
            LaunchParameters {
                creator_coin_address,
                transfer_restriction_delay: TRANSFER_RESTRICTION_DELAY,
                max_percentage_buy_launch: MAX_PERCENTAGE_BUY_LAUNCH,
                quote_address: quote.contract_address,
                initial_holders: array![
                    'initial_holder_1'.try_into().unwrap(), 'initial_holder_2'.try_into().unwrap()
                ]
                    .span(),
                initial_holders_amounts: array![alloc_holder_1, alloc_holder_2].span(),
            },
            quote_amount,
            DEFAULT_MIN_LOCKTIME,
        );
}
