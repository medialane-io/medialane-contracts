# Creator Coin

Permissionless launchpad for **Creator Coins** — a creator deploys their own
fixed-supply ERC-20 social token and launches it into a **locked-liquidity Ekubo
pool** with a **capped creator allocation**. Anti-rug by construction; trading
happens on Ekubo (the coin is a standard ERC-20, tradeable anywhere).

> **Status:** design/implementation — **12 snforge tests green**, the Ekubo
> adapter compiles against the live `EkuboProtocol/abis`. **Not yet deployed.**
> Pending: mainnet-fork test, `cairo-auditor` gate, deploy. See
> `medialane-core/docs/specs/2026-06-02-creator-coin-launchpad-design.md` and
> `medialane-core/docs/plans/2026-06-02-creator-coin-contracts.md`.

## Contracts

| Contract | Responsibility |
|---|---|
| `CreatorCoin` | Plain OZ ERC-20, **fixed supply minted once at deploy**, 18 decimals, immutable `creator` for on-chain provenance. Deliberately standard for interoperability. |
| `CoinFactory` | **Immutable, ownerless, zero-fee, permissionless** factory. `create_coin` mints the full supply to the creator; `launch_on_ekubo` seeds + locks the AMM pool. Enforces the anti-rug guarantees on-chain. |
| `LiquidityLock` | Custodies the Ekubo LP **position NFT** until `unlock_time`; only the creator may withdraw, and withdraw returns the NFT. |
| `exchanges::EkuboAdapter` | Concrete `IExchangeAdapter` over Ekubo: builds the `PoolKey`, initialises the pool at the (off-chain-computed) price tick, deposits full-range liquidity via `mint_and_deposit_and_clear_both`, returns the position. |

The factory talks to the AMM through the `IExchangeAdapter` seam, so the launch
logic is unit-tested against `MockExchange` and the concrete `EkuboAdapter` is a
swappable implementation behind it.

## Anti-rug guarantees (enforced on-chain, `00 §1`)

- `creator_allocation_bps <= MAX_ALLOCATION_BPS` (1000 = 10%) — the creator keeps
  at most the cap; the rest seeds the pool.
- `lock_duration >= MIN_LOCK_DURATION` (180 days) — LP cannot be pulled early.
- `seed_amount > 0` and the supply invariant `pool + allocation == total_supply`.

The quote-token allowlist (STRK/ETH/USDC/wBTC) is **platform-layer**, not on-chain
— the factory accepts any ERC-20 quote token to stay permissionless (`00 §2`).

## Off-chain tick design

All Ekubo tick/price math (the initial price tick and the full-range bounds) is
computed **off-chain** by the dapp/SDK using Ekubo's SDK and passed into
`launch_on_ekubo` via `TickParams`. The on-chain adapter therefore carries **no
log math and no protocol constants**; `core`, `positions`, `fee`, and
`tick_spacing` are wired at adapter deploy.

## Toolchain

This package uses the **modern** Starknet toolchain (pinned in `.tool-versions`):

- scarb **2.18.0**, cairo edition `2024_07`
- OpenZeppelin Cairo **2.0.0** (exact-pinned `=2.0.0` to avoid `utils` 2.1.0 skew)
- `snforge_std` **0.59.0**
- `ekubo = { git = "https://github.com/EkuboProtocol/abis" }`

(The older packages in this repo pin scarb ≤ 2.11.4 + `snforge_std_deprecated`;
that toolchain is being phased out.)

## Build & test

```bash
cd contracts/Creator-Coin
scarb build
snforge test
```

## Layout

```
src/
  creator_coin.cairo        CreatorCoin ERC-20
  coin_factory.cairo        CoinFactory (create_coin + launch_on_ekubo)
  liquidity_lock.cairo      LiquidityLock (NFT custody + time/beneficiary guards)
  exchanges/ekubo_adapter.cairo   Real Ekubo IExchangeAdapter
  interfaces/               ICreatorCoin, ICoinFactory, ILiquidityLock, IExchangeAdapter
  events.cairo, types.cairo
  mocks/                    erc20, erc721, MockExchange (tests)
tests/tests.cairo           12 unit tests
```

## Key event (for the indexer)

`CoinFactory::CoinLaunched(coin_address, creator, coin_id, quote_token,
total_supply, creator_allocation_bps, pool_id, lock_expiry, timestamp)` — the
anchor event the backend projects into a `Collection` (ERC20) + `CoinMarket` row.

## Before mainnet

`unruggable.meme` (the design inspiration) is unaudited and targets an old Cairo;
this is a clean implementation on the current toolchain, but it has **not** been
audited. A `cairo-auditor` pass + a mainnet-fork test against live Ekubo are
required before any deploy.
