# Creator Coin

Permissionless, **non-custodial** launchpad for **Creator Coins** — a creator deploys
their own fixed-supply ERC-20, keeps a capped founder allocation (≤10%), and the rest
is deposited as **single-sided liquidity** into an Ekubo pool. The LP position goes to
the creator. The platform holds nothing, locks nothing. Trading is a standard Ekubo
swap (the coin is a plain ERC-20, tradeable anywhere).

This mirrors the battle-tested [`unruggable.meme`](https://github.com/keep-starknet-strange/unruggable.meme)
Ekubo launch — **no buyback, no swap, no liquidity lock** (unrug's team allocation is a
direct transfer and its pool liquidity is single-sided; we adopt that and drop its
permanent lock so the creator keeps control).

> **Status:** implementation — **5 snforge tests green**, the Ekubo adapter compiles
> against the live `EkuboProtocol/abis`. **Not yet deployed.** Pending: mainnet-fork
> test, `cairo-auditor` gate, deploy. Model:
> `medialane-core/docs/specs/2026-06-02-creator-coin-CORRECTED-model.md`.

## Contracts

| Contract | Responsibility |
|---|---|
| `CreatorCoin` | Plain OZ ERC-20, **fixed supply minted once at deploy**, 18 decimals, immutable `creator` for on-chain provenance. Deliberately standard for interoperability. |
| `CoinFactory` | **Immutable, ownerless, zero-fee, permissionless.** One atomic `launch`: deploy the coin (full supply to the factory) → transfer the ≤10% allocation to the creator → deposit the rest as single-sided liquidity → hand the LP position NFT to the creator. Holds nothing afterward. |
| `exchanges::EkuboAdapter` | Concrete `IExchangeAdapter`: builds the `PoolKey`, initialises the pool at the off-chain price tick, deposits single-sided liquidity via `Positions.mint_and_deposit_and_clear_both`, and transfers the position NFT to the creator. **No swap.** |

The factory talks to the AMM through the `IExchangeAdapter` seam, so the launch logic
is unit-tested against `MockExchange` and the concrete `EkuboAdapter` is a swappable
implementation behind it.

## Anti-rug guarantee (enforced on-chain)

- `creator_allocation_bps <= MAX_ALLOCATION_BPS` (1000 = 10%) — the creator keeps at
  most 10% (transferred directly); the rest is deposited as liquidity for the market.
  Nobody — creator included — can corner the supply and dump it.

That single cap is the whole on-chain guarantee. There is **no liquidity lock**: the
creator owns and controls the LP position like any liquidity provider (sell, withdraw),
with transparency/reputation as the accountability — the platform never holds or locks
it. The quote-token set (STRK/ETH/USDC/wBTC) is **platform-layer** UI curation, not
on-chain — the factory accepts any ERC-20 quote token to stay permissionless.

## Off-chain tick design

All Ekubo tick/price math (initial price tick + the single-sided range bounds) is
computed **off-chain** by the dapp/SDK and passed into `launch` via `TickParams`. The
adapter carries no log math and no protocol constants; `core`, `positions`, `fee`, and
`tick_spacing` are wired at adapter deploy.

## Toolchain

Modern Starknet toolchain (pinned in `.tool-versions`):

- scarb **2.18.0**, cairo edition `2024_07`
- OpenZeppelin Cairo **2.0.0** (exact-pinned `=2.0.0`)
- `snforge_std` **0.59.0**
- `ekubo = { git = "https://github.com/EkuboProtocol/abis" }`

## Build & test

```bash
cd contracts/Creator-Coin
scarb build
snforge test
```

## Layout

```
src/
  creator_coin.cairo              CreatorCoin ERC-20
  coin_factory.cairo              CoinFactory (atomic launch: split + single-sided deposit)
  exchanges/ekubo_adapter.cairo   Real Ekubo IExchangeAdapter (deposit + position to creator)
  interfaces/                     ICreatorCoin, ICoinFactory, IExchangeAdapter
  events.cairo, types.cairo
  mocks/                          erc20, erc721, MockExchange (tests)
tests/tests.cairo                 5 unit tests
```

## Key event (for the indexer)

`CoinFactory::CoinLaunched(coin_address, creator, coin_id, quote_token, total_supply,
creator_allocation_bps, pool_id, timestamp)` — the anchor event the backend projects
into a `Collection` (ERC20) + `CoinMarket` row.

## Before mainnet

`unruggable.meme` (the design inspiration) is unaudited and targets an old Cairo; this
is a clean implementation on the current toolchain, but it has **not** been audited. A
`cairo-auditor` pass + a mainnet-fork test against live Ekubo are required before any
deploy.
