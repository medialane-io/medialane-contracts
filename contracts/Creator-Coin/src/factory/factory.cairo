use openzeppelin::token::erc20::interface::{IERC20, ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use starknet::ContractAddress;

#[starknet::contract]
mod Factory {
    use core::box::BoxTrait;
    use core::starknet::event::EventEmitter;
    use core::zeroable::Zeroable;
    use ekubo::types::i129::i129;
    use openzeppelin::token::erc20::interface::{
        IERC20, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
    };
    use poseidon::poseidon_hash_span;
    use starknet::SyscallResultTrait;
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address, contract_address_const
    };
    use creator_coin::errors;
    use creator_coin::exchanges::ekubo::launcher::{
        IEkuboLauncherDispatcher, IEkuboLauncherDispatcherTrait
    };
    use creator_coin::exchanges::{
        SupportedExchanges, ekubo_adapter, ekubo_adapter::EkuboPoolParameters,
        ekubo::launcher::EkuboLP
    };
    use creator_coin::factory::{IFactory, LaunchParameters};
    use creator_coin::token::interface::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait
    };
    use creator_coin::token::creator_coin::{
        CreatorCoin::LiquidityType, CreatorCoin::LiquidityParameters, EkuboLiquidityParameters
    };
    use creator_coin::utils::math::PercentageMath;

    /// The maximum percentage of the total supply that can be allocated to the team.
    /// This is to prevent the team from having too much control over the supply.
    const MAX_SUPPLY_PERCENTAGE_TEAM_ALLOCATION: u16 = 1_000; // 10%

    /// The maximum number of holders one can specify when launching.
    /// This is to prevent the contract from being is_launched with a large number of holders.
    /// Once reached, transfers are disabled until the creator_coin is is_launched.
    const MAX_HOLDERS_LAUNCH: u8 = 10;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreatorCoinCreated: CreatorCoinCreated,
        CreatorCoinLaunched: CreatorCoinLaunched,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatorCoinCreated {
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        creator_coin_address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct CreatorCoinLaunched {
        creator_coin_address: ContractAddress,
        quote_token: ContractAddress,
        exchange_name: felt252,
    }


    #[storage]
    struct Storage {
        creator_coin_class_hash: ClassHash,
        exchange_configs: LegacyMap<SupportedExchanges, ContractAddress>,
        deployed_creator_coins: LegacyMap<ContractAddress, bool>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        creator_coin_class_hash: ClassHash,
        mut exchanges: Span<(SupportedExchanges, ContractAddress)>,
    ) {
        self.creator_coin_class_hash.write(creator_coin_class_hash);

        // Add Exchanges configurations
        loop {
            match exchanges.pop_front() {
                Option::Some((exchange, address)) => self
                    .exchange_configs
                    .write(*exchange, *address),
                Option::None => { break; }
            }
        };
    }

    #[abi(embed_v0)]
    impl FactoryImpl of IFactory<ContractState> {
        fn version(self: @ContractState) -> ByteArray {
            "0.2.0"
        }

        fn create_creator_coin(
            ref self: ContractState,
            owner: ContractAddress,
            name: felt252,
            symbol: felt252,
            initial_supply: u256,
            contract_address_salt: felt252,
        ) -> ContractAddress {
            let mut calldata = array![owner.into(), name.into(), symbol.into()];
            Serde::serialize(@initial_supply, ref calldata);

            let (creator_coin_address, _) = deploy_syscall(
                self.creator_coin_class_hash.read(), contract_address_salt, calldata.span(), false
            )
                .unwrap_syscall();

            // save creator_coin address
            self.deployed_creator_coins.write(creator_coin_address, true);

            self.emit(CreatorCoinCreated { owner, name, symbol, initial_supply, creator_coin_address });

            creator_coin_address
        }

        fn launch_on_ekubo(
            ref self: ContractState,
            launch_parameters: LaunchParameters,
            ekubo_parameters: EkuboPoolParameters,
        ) -> (u64, EkuboLP) {
            let team_allocation = check_common_launch_parameters(@self, launch_parameters);

            assert(ekubo_parameters.fee <= 0x51eb851eb851ec00000000000000000, errors::FEE_TOO_HIGH);
            assert(ekubo_parameters.tick_spacing >= 5982, errors::TICK_SPACING_TOO_LOW);
            assert(ekubo_parameters.tick_spacing <= 19802, errors::TICK_SPACING_TOO_HIGH);
            assert(ekubo_parameters.bound >= 88712960, errors::BOUND_TOO_LOW);

            let LaunchParameters{creator_coin_address,
            transfer_restriction_delay,
            max_percentage_buy_launch,
            quote_address,
            initial_holders,
            initial_holders_amounts } =
                launch_parameters;

            let launchpad_address = self.exchange_address(SupportedExchanges::Ekubo);
            assert(launchpad_address.is_non_zero(), errors::EXCHANGE_ADDRESS_ZERO);
            assert(ekubo_parameters.starting_price.mag.is_non_zero(), errors::PRICE_ZERO);

            let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };
            let (id, position) = ekubo_adapter::EkuboAdapterImpl::create_and_add_liquidity(
                exchange_address: launchpad_address,
                token_address: creator_coin_address,
                quote_address: quote_address,
                lp_supply: creator_coin.total_supply() - team_allocation,
                additional_parameters: ekubo_parameters
            );

            distribute_team_alloc(creator_coin, initial_holders, initial_holders_amounts);
            creator_coin
                .set_launched(
                    LiquidityType::EkuboNFT(id),
                    LiquidityParameters::Ekubo(
                        EkuboLiquidityParameters {
                            quote_address, ekubo_pool_parameters: ekubo_parameters
                        }
                    ),
                    :transfer_restriction_delay,
                    :max_percentage_buy_launch,
                    :team_allocation,
                );
            self
                .emit(
                    CreatorCoinLaunched {
                        creator_coin_address, quote_token: quote_address, exchange_name: 'Ekubo'
                    }
                );
            (id, position)
        }

        fn locked_liquidity(
            self: @ContractState, token: ContractAddress
        ) -> Option<(ContractAddress, LiquidityType)> {
            let creator_coin = ICreatorCoinDispatcher { contract_address: token };
            let liquidity_type = match creator_coin.liquidity_type() {
                Option::Some(liquidity_type) => liquidity_type,
                Option::None => { return Option::None; },
            };

            let locker_address = match liquidity_type {
                LiquidityType::EkuboNFT(id) => {
                    // Ekubo NFTs are locked inside the EkuboLauncher contract
                    self.exchange_address(SupportedExchanges::Ekubo)
                }
            };

            Option::Some((locker_address, liquidity_type))
        }

        fn exchange_address(self: @ContractState, exchange: SupportedExchanges) -> ContractAddress {
            self.exchange_configs.read(exchange)
        }

        fn is_creator_coin(self: @ContractState, address: ContractAddress) -> bool {
            self.deployed_creator_coins.read(address)
        }

        fn ekubo_core_address(self: @ContractState) -> ContractAddress {
            let launcher = IEkuboLauncherDispatcher {
                contract_address: self.exchange_address(SupportedExchanges::Ekubo)
            };

            launcher.ekubo_core_address()
        }
    }


    /// Checks the launch parameters and calculates the team allocation.
    ///
    /// This function checks that the creator_coin and quote addresses are valid,
    /// that the caller is the owner of the creator_coin,
    /// that the creator_coin has not been launched,
    /// and that the lengths of the initial holders and their amounts are equal and do not exceed the maximum allowed.
    /// It then calculates the maximum team allocation as a percentage of the total supply,
    /// and iteratively adds the amounts of the initial holders to the team allocation,
    /// ensuring that the total allocation does not exceed the maximum.
    /// It finally returns the total team allocation.
    ///
    /// # Arguments
    ///
    /// * `self` - A reference to the ContractState struct.
    /// * `launch_parameters` - The parameters for the token launch.
    ///
    /// # Returns
    ///
    /// * `u256` - The total amount of creator_coin allocated to the team.
    ///
    /// # Panics
    ///
    /// * If the creator_coin address is not a creator_coin.
    /// * If the quote address is a creator_coin.
    /// * If the caller is not the owner of the creator_coin.
    /// * If the creator_coin has been launched.
    /// * If the lengths of the initial holders and their amounts are not equal.
    /// * If the number of initial holders exceeds the maximum allowed.
    /// * If the total team allocation exceeds the maximum allowed.
    ///
    fn check_common_launch_parameters(
        self: @ContractState, launch_parameters: LaunchParameters
    ) -> u256 {
        let LaunchParameters{creator_coin_address,
        transfer_restriction_delay,
        max_percentage_buy_launch,
        quote_address,
        initial_holders,
        initial_holders_amounts } =
            launch_parameters;
        let creator_coin = ICreatorCoinDispatcher { contract_address: creator_coin_address };

        assert(self.is_creator_coin(creator_coin_address), errors::NOT_CREATOR_COIN);
        assert(!self.is_creator_coin(quote_address), errors::QUOTE_TOKEN_IS_CREATOR_COIN);
        assert(!creator_coin.is_launched(), errors::ALREADY_LAUNCHED);
        assert(get_caller_address() == creator_coin.owner(), errors::CALLER_NOT_OWNER);
        assert(initial_holders.len() == initial_holders_amounts.len(), errors::ARRAYS_LEN_DIF);
        assert(initial_holders.len() <= MAX_HOLDERS_LAUNCH.into(), errors::MAX_HOLDERS_REACHED);

        let initial_supply = creator_coin.total_supply();

        // Check that the sum of the amounts of initial holders does not exceed the max allocatable supply for a team.
        let max_team_allocation = initial_supply
            .percent_mul(MAX_SUPPLY_PERCENTAGE_TEAM_ALLOCATION.into());
        let mut team_allocation: u256 = 0;
        let mut i: usize = 0;
        loop {
            if i == initial_holders.len() {
                break;
            }

            let address = *initial_holders.at(i);
            let amount = *initial_holders_amounts.at(i);

            team_allocation += amount;
            assert(team_allocation <= max_team_allocation, errors::MAX_TEAM_ALLOCATION_REACHED);
            i += 1;
        };

        team_allocation
    }

    fn distribute_team_alloc(
        creator_coin: ICreatorCoinDispatcher,
        mut initial_holders: Span<ContractAddress>,
        mut initial_holders_amounts: Span<u256>
    ) {
        loop {
            match initial_holders.pop_front() {
                Option::Some(holder) => {
                    match initial_holders_amounts.pop_front() {
                        Option::Some(amount) => { creator_coin.transfer(*holder, *amount); },
                        // Should never happen as the lengths of the spans are equal.
                        Option::None => { break; }
                    }
                },
                Option::None => { break; }
            }
        }
    }
}
