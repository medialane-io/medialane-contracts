/// EkuboAdapter — the real IExchangeAdapter backed by Ekubo.
///
/// `add_liquidity()` mirrors unrug's proven Ekubo launch (minus the permanent lock):
///   1. initialises the pool at the off-chain `initial_tick`,
///   2. deposits `coin_amount` of the coin as **single-sided** liquidity via Ekubo
///      `Positions` (Positions handles its own lock + clears any dust back to us),
///   3. transfers the resulting LP position NFT to `recipient` (the creator).
///
/// No swap, no buyback — quote enters the pool only as the public buys. All tick/price
/// math is off-chain (`TickParams`). `core`, `positions`, `fee`, `tick_spacing` are
/// wired at deploy. Verified end-to-end by the mainnet-fork test (Task 6).
#[starknet::contract]
pub mod EkuboAdapter {
    use core::poseidon::poseidon_hash_span;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::types::keys::PoolKey;
    use ekubo::types::bounds::Bounds;
    use ekubo::types::i129::i129;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use creator_coin::interfaces::IExchangeAdapter::{IExchangeAdapter, LaunchResult, TickParams};

    #[storage]
    struct Storage {
        core: ContractAddress,
        positions: ContractAddress,
        fee: u128,
        tick_spacing: u128,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ContractAddress,
        positions: ContractAddress,
        fee: u128,
        tick_spacing: u128,
    ) {
        self.core.write(core);
        self.positions.write(positions);
        self.fee.write(fee);
        self.tick_spacing.write(tick_spacing);
    }

    fn mk_i129(mag: u128, sign: bool) -> i129 {
        i129 { mag, sign: sign && mag != 0 }
    }

    fn addr_lt(a: ContractAddress, b: ContractAddress) -> bool {
        let af: felt252 = a.into();
        let bf: felt252 = b.into();
        let au: u256 = af.into();
        let bu: u256 = bf.into();
        au < bu
    }

    #[abi(embed_v0)]
    impl EkuboAdapterImpl of IExchangeAdapter<ContractState> {
        fn add_liquidity(
            ref self: ContractState,
            coin: ContractAddress,
            quote: ContractAddress,
            coin_amount: u256,
            recipient: ContractAddress,
            ticks: TickParams,
        ) -> LaunchResult {
            let fee = self.fee.read();
            let tick_spacing = self.tick_spacing.read();
            // Ekubo requires token0 < token1 by integer value.
            let (token0, token1) = if addr_lt(coin, quote) {
                (coin, quote)
            } else {
                (quote, coin)
            };
            let pool_key = PoolKey {
                token0, token1, fee, tick_spacing, extension: 0.try_into().unwrap(),
            };

            let core = ICoreDispatcher { contract_address: self.core.read() };
            let _ = core
                .maybe_initialize_pool(
                    pool_key, mk_i129(ticks.initial_tick_mag, ticks.initial_tick_sign),
                );

            // Deposit the coin as single-sided liquidity via Positions.
            let positions_addr = self.positions.read();
            IERC20Dispatcher { contract_address: coin }.transfer(positions_addr, coin_amount);
            let bounds = Bounds {
                lower: mk_i129(ticks.lower_mag, ticks.lower_sign),
                upper: mk_i129(ticks.upper_mag, ticks.upper_sign),
            };
            let positions = IPositionsDispatcher { contract_address: positions_addr };
            let (position_id, _liquidity, _c0, _c1) = positions
                .mint_and_deposit_and_clear_both(pool_key, bounds, 0);

            // Hand the LP position NFT to the creator.
            let nft = positions.get_nft_address();
            IERC721Dispatcher { contract_address: nft }
                .transfer_from(get_contract_address(), recipient, position_id.into());

            let pool_id = poseidon_hash_span(
                array![token0.into(), token1.into(), fee.into(), tick_spacing.into()].span(),
            );
            LaunchResult { pool_id, position_id: position_id.into() }
        }
    }
}
