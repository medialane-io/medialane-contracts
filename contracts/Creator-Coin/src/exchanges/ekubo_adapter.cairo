/// EkuboAdapter — the real IExchangeAdapter backed by Ekubo concentrated liquidity.
///
/// Built against the current `EkuboProtocol/abis`. The factory transfers the pool
/// coins + seed quote to this adapter, then calls `add_liquidity`, which:
///   1. sorts the pair (Ekubo requires token0 < token1),
///   2. initialises the pool at the off-chain-computed `initial_tick`,
///   3. forwards the tokens to Ekubo's Positions contract and mints a full-range
///      position over the off-chain-computed `[lower, upper]` bounds,
///   4. returns the position NFT id (the factory then locks it).
///
/// All tick/price math is computed off-chain (Ekubo SDK) and passed in via
/// `TickParams`, so this contract carries no protocol constants. `core`,
/// `positions`, `fee`, and `tick_spacing` are wired at deploy.
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
            quote_amount: u256,
            ticks: TickParams,
        ) -> LaunchResult {
            // Sort the pair: Ekubo requires token0 < token1 by integer value.
            let (token0, token1, amount0, amount1) = if addr_lt(coin, quote) {
                (coin, quote, coin_amount, quote_amount)
            } else {
                (quote, coin, quote_amount, coin_amount)
            };

            let fee = self.fee.read();
            let tick_spacing = self.tick_spacing.read();
            let pool_key = PoolKey {
                token0, token1, fee, tick_spacing, extension: 0.try_into().unwrap(),
            };

            // Initialise the pool at the off-chain price tick (no-op if already initialised).
            let core = ICoreDispatcher { contract_address: self.core.read() };
            let _ = core
                .maybe_initialize_pool(
                    pool_key, mk_i129(ticks.initial_tick_mag, ticks.initial_tick_sign),
                );

            // Forward the tokens to Ekubo Positions, then mint a full-range position.
            let positions_addr = self.positions.read();
            IERC20Dispatcher { contract_address: token0 }.transfer(positions_addr, amount0);
            IERC20Dispatcher { contract_address: token1 }.transfer(positions_addr, amount1);

            let bounds = Bounds {
                lower: mk_i129(ticks.lower_mag, ticks.lower_sign),
                upper: mk_i129(ticks.upper_mag, ticks.upper_sign),
            };
            let positions = IPositionsDispatcher { contract_address: positions_addr };
            // clear_both returns any unused dust to this adapter (the caller).
            let (id, _liquidity, _c0, _c1) = positions
                .mint_and_deposit_and_clear_both(pool_key, bounds, 0);

            // Ekubo pools are keyed by struct; expose a stable felt id = hash of the key.
            let pool_id = poseidon_hash_span(
                array![token0.into(), token1.into(), fee.into(), tick_spacing.into()].span(),
            );
            LaunchResult { pool_id, position_id: id.into() }
        }

        fn transfer_position(ref self: ContractState, position_id: u256, to: ContractAddress) {
            let nft = self.position_nft_address();
            IERC721Dispatcher { contract_address: nft }
                .transfer_from(get_contract_address(), to, position_id);
        }

        fn position_nft_address(self: @ContractState) -> ContractAddress {
            IPositionsDispatcher { contract_address: self.positions.read() }.get_nft_address()
        }
    }
}
