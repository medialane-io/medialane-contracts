/// EkuboAdapter — the real IExchangeAdapter backed by Ekubo.
///
/// `launch()`:
///   1. initialises the pool at the off-chain `initial_tick`,
///   2. deposits the full coin supply as liquidity via Ekubo `Positions`
///      (Positions handles its own lock + clears any dust back to us),
///   3. runs the founder buyback — swaps `quote_in` of `quote` for `coin` inside a
///      Core `lock` callback and `withdraw`s the bought coins straight to the creator,
///   4. transfers the LP position NFT to the creator.
///
/// All tick/price math is off-chain (`TickParams`). `core`, `positions`, `fee`,
/// `tick_spacing`, and the swap sqrt-ratio bounds are wired at deploy.
///
/// NOTE: the buyback swap settlement (sqrt limits, delta signs, pay/withdraw) is the
/// part verified by the mainnet-fork test (Task 6). The factory's orchestration + cap
/// logic is unit-covered via MockExchange.
#[starknet::contract]
pub mod EkuboAdapter {
    use core::poseidon::poseidon_hash_span;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker, SwapParameters};
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
        min_sqrt_ratio: u256,
        max_sqrt_ratio: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ContractAddress,
        positions: ContractAddress,
        fee: u128,
        tick_spacing: u128,
        min_sqrt_ratio: u256,
        max_sqrt_ratio: u256,
    ) {
        self.core.write(core);
        self.positions.write(positions);
        self.fee.write(fee);
        self.tick_spacing.write(tick_spacing);
        self.min_sqrt_ratio.write(min_sqrt_ratio);
        self.max_sqrt_ratio.write(max_sqrt_ratio);
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

    fn build_pool_key(
        token0: ContractAddress, token1: ContractAddress, fee: u128, tick_spacing: u128,
    ) -> PoolKey {
        PoolKey { token0, token1, fee, tick_spacing, extension: 0.try_into().unwrap() }
    }

    #[abi(embed_v0)]
    impl EkuboAdapterImpl of IExchangeAdapter<ContractState> {
        fn launch(
            ref self: ContractState,
            coin: ContractAddress,
            quote: ContractAddress,
            coin_supply: u256,
            quote_in: u256,
            creator: ContractAddress,
            ticks: TickParams,
        ) -> LaunchResult {
            let fee = self.fee.read();
            let tick_spacing = self.tick_spacing.read();
            let (token0, token1) = if addr_lt(coin, quote) {
                (coin, quote)
            } else {
                (quote, coin)
            };
            let pool_key = build_pool_key(token0, token1, fee, tick_spacing);

            let core = ICoreDispatcher { contract_address: self.core.read() };
            let _ = core
                .maybe_initialize_pool(
                    pool_key, mk_i129(ticks.initial_tick_mag, ticks.initial_tick_sign),
                );

            // Deposit the full coin supply as liquidity via Positions.
            let positions_addr = self.positions.read();
            IERC20Dispatcher { contract_address: coin }.transfer(positions_addr, coin_supply);
            let bounds = Bounds {
                lower: mk_i129(ticks.lower_mag, ticks.lower_sign),
                upper: mk_i129(ticks.upper_mag, ticks.upper_sign),
            };
            let positions = IPositionsDispatcher { contract_address: positions_addr };
            let (position_id, _liquidity, _c0, _c1) = positions
                .mint_and_deposit_and_clear_both(pool_key, bounds, 0);

            // Founder buyback: swap quote -> coin inside a Core lock; the callback
            // withdraws the bought coins straight to the creator and returns the amount.
            let mut coins_bought: u256 = 0;
            if quote_in > 0 {
                let mut data: Array<felt252> = array![];
                (coin, quote, quote_in, creator, token0, token1).serialize(ref data);
                let mut ret = core.lock(data.span());
                coins_bought = Serde::<u256>::deserialize(ref ret).unwrap();
            }

            // Transfer the LP position NFT to the creator.
            let nft = self.position_nft_address();
            IERC721Dispatcher { contract_address: nft }
                .transfer_from(get_contract_address(), creator, position_id.into());

            let pool_id = poseidon_hash_span(
                array![token0.into(), token1.into(), fee.into(), tick_spacing.into()].span(),
            );
            LaunchResult { pool_id, position_id: position_id.into(), coins_bought }
        }

        fn position_nft_address(self: @ContractState) -> ContractAddress {
            IPositionsDispatcher { contract_address: self.positions.read() }.get_nft_address()
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core_addr = self.core.read();
            let core = ICoreDispatcher { contract_address: core_addr };

            let mut d = data;
            let coin: ContractAddress = Serde::deserialize(ref d).unwrap();
            let quote: ContractAddress = Serde::deserialize(ref d).unwrap();
            let quote_in: u256 = Serde::deserialize(ref d).unwrap();
            let creator: ContractAddress = Serde::deserialize(ref d).unwrap();
            let token0: ContractAddress = Serde::deserialize(ref d).unwrap();
            let token1: ContractAddress = Serde::deserialize(ref d).unwrap();

            let pool_key = build_pool_key(
                token0, token1, self.fee.read(), self.tick_spacing.read(),
            );

            // Exact-input swap of `quote_in` of the quote token.
            let quote_is_token1 = quote == token1;
            let sqrt_ratio_limit = if quote_is_token1 {
                self.min_sqrt_ratio.read()
            } else {
                self.max_sqrt_ratio.read()
            };
            let params = SwapParameters {
                amount: i129 { mag: quote_in.try_into().unwrap(), sign: false },
                is_token1: quote_is_token1,
                sqrt_ratio_limit,
                skip_ahead: 0,
            };
            let delta = core.swap(pool_key, params);

            // Pay the quote we owe; withdraw the coin we received to the creator.
            IERC20Dispatcher { contract_address: quote }.transfer(core_addr, quote_in);
            core.pay(quote);
            let coin_delta = if coin == token0 {
                delta.amount0
            } else {
                delta.amount1
            };
            let coins_out: u128 = coin_delta.mag;
            core.withdraw(coin, creator, coins_out);

            let mut ret: Array<felt252> = array![];
            let coins_out_u256: u256 = coins_out.into();
            coins_out_u256.serialize(ref ret);
            ret.span()
        }
    }
}
