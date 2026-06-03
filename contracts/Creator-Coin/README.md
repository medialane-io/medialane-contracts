# Creator Coin

A permissionless, **non-custodial** launchpad for **Creator Coins** on Starknet,
mirroring the battle-tested [`unruggable.meme`](https://github.com/keep-starknet-strange/unruggable.meme)
Ekubo launch.

A creator deploys their own fixed-supply ERC-20, keeps a capped founder allocation
(≤10%), and the remaining supply is deposited as **single-sided liquidity** into an
Ekubo pool. The LP position NFT goes to the creator. **There is no buyback, no swap,
and no liquidity lock** — the platform holds nothing and controls nothing after the
launch transaction. Trading is an ordinary Ekubo swap (the coin is a plain ERC-20,
so it works in any wallet/DEX/aggregator).

> **Status:** implemented, **5 snforge unit tests green**, compiles against the live
> `EkuboProtocol/abis`. **Not yet runtime-verified on live Ekubo and not audited** —
> see [Before mainnet](#before-mainnet). Branch `feat/creator-coin`.
> Canonical model spec:
> `medialane-core/docs/specs/2026-06-02-creator-coin-CORRECTED-model.md`.

---

## Design principles

- **Non-custodial.** The platform integrates immutable contracts; it never holds,
  locks, or restricts a creator's or user's assets. After `launch`, the factory holds
  nothing — the creator owns their coins and their LP position.
- **The contract is the source of truth, and useful to the creator.** No admin, no
  owner, no upgrade, no setters, no fee.
- **Anti-rug by supply distribution, not by restriction.** The whole supply goes to the
  market (minus the ≤10% the creator keeps), so there is no hidden founder bag to dump.
- **Standard ERC-20** for maximum interoperability — no transfer hooks, no launch-window
  anti-whale logic, 18 decimals.

---

## Contracts

| Contract | Responsibility |
|---|---|
| `CreatorCoin` | Plain OpenZeppelin ERC-20. Fixed supply minted once at deploy, 18 decimals, one immutable `creator: ContractAddress` field for on-chain provenance. |
| `CoinFactory` | Immutable, ownerless, zero-fee, permissionless launcher. One atomic `launch`. Keeps a per-creator coin index and emits `CoinLaunched`. |
| `exchanges::EkuboAdapter` | Concrete `IExchangeAdapter` over Ekubo: builds the `PoolKey`, initialises the pool at the off-chain price tick, deposits single-sided liquidity via `Positions.mint_and_deposit_and_clear_both`, and transfers the position NFT to the creator. **No swap.** |
| `mocks::MockExchange` | In-memory `IExchangeAdapter` for unit tests (records the deposited amount, returns deterministic ids). |
| `mocks::{MockERC20, MockERC721}` | Test stand-ins. |

The factory talks to the AMM only through the `IExchangeAdapter` seam, so the launch
orchestration + cap logic are unit-tested against `MockExchange`, and the concrete
`EkuboAdapter` is a swappable implementation verified by the mainnet-fork test.

---

## Launch flow

`CoinFactory.launch` is a single atomic transaction:

1. **Deploy** the `CreatorCoin` via `deploy_syscall` (salt = next coin id); the full
   supply mints to the factory, `creator = caller` is recorded on the coin.
2. **Split.** `creator_allocation = total_supply * creator_allocation_bps / 10000`
   (cap: `creator_allocation_bps <= 1000`). Transfer that allocation **directly** to
   the creator.
3. **Deposit.** Transfer the remaining `pool_amount = total_supply - creator_allocation`
   to the adapter; the adapter initialises the Ekubo pool at the off-chain price tick
   and deposits it as single-sided liquidity.
4. **Hand over.** The adapter transfers the LP **position NFT** to the creator.
5. **Record + emit.** Write the `CoinRecord`, index it per creator, emit `CoinLaunched`.

After this tx the platform holds nothing. The pool starts coin-only; quote (the buyers'
real money) accumulates only as the public buys.

---

## Public API

### `ICoinFactory`

```cairo
// Deploy + launch in one tx. Returns (coin_address, pool_id).
fn launch(
    name: ByteArray, symbol: ByteArray, total_supply: u256,
    quote_token: ContractAddress,      // the pair token (STRK/ETH/USDC/wBTC, UI-curated)
    creator_allocation_bps: u16,       // <= 1000 (10%); the founder allocation
    ticks: TickParams,                 // off-chain price tick + single-sided bounds
) -> (ContractAddress, felt252);

fn get_coin(coin_id: u256) -> CoinRecord;
fn get_last_coin_id() -> u256;
fn get_creator_coin_count(creator: ContractAddress) -> u32;
fn get_creator_coin_ids(creator: ContractAddress, start: u32, count: u32) -> Array<u256>;
fn get_creator_coin_class_hash() -> ClassHash;
```

Constructor: `constructor(creator_coin_class_hash: ClassHash, exchange_adapter: ContractAddress)`.

### `ICreatorCoin`

```cairo
fn creator() -> ContractAddress;   // immutable provenance; plus the full OZ ERC-20 mixin
```

Constructor: `constructor(name, symbol, initial_supply: u256, recipient: ContractAddress, creator: ContractAddress)`.

### `IExchangeAdapter`

```cairo
// The factory transfers `coin_amount` of `coin` to the adapter before calling.
fn add_liquidity(
    coin: ContractAddress, quote: ContractAddress, coin_amount: u256,
    recipient: ContractAddress,        // the creator (receives the position NFT)
    ticks: TickParams,
) -> LaunchResult;                     // { pool_id: felt252, position_id: u256 }
```

`EkuboAdapter` constructor: `constructor(core, positions, fee: u128, tick_spacing: u128)`.

### Types & events

```cairo
struct TickParams {            // all Ekubo i129 split into (mag, sign)
    initial_tick_mag: u128, initial_tick_sign: bool,
    lower_mag: u128, lower_sign: bool,
    upper_mag: u128, upper_sign: bool,
}

struct CoinRecord {
    coin_id: u256, coin_address: ContractAddress, creator: ContractAddress,
    quote_token: ContractAddress, total_supply: u256, creator_allocation_bps: u16,
    pool_id: felt252, created_at: u64,
}

event CoinLaunched {                   // the indexer anchor
    #[key] coin_address, #[key] creator, coin_id, quote_token,
    total_supply, creator_allocation_bps, pool_id, timestamp,
}
```

---

## Off-chain tick computation

All Ekubo tick/price math is computed **off-chain** (dapp/SDK) and passed in via
`TickParams`, so the on-chain adapter carries no log math and no protocol constants:

- `initial_tick` — the pool's starting price (from the creator's chosen price), as an
  Ekubo `i129`.
- `[lower, upper]` — a **single-sided** range entirely above the start price, so only
  the coin is deposited (quote enters as buyers swap up through the range).

The reference logic to port is unrug's `packages/contracts/src/exchanges/ekubo/helpers.cairo`
(`get_initial_tick_from_starting_price`, `get_next_tick_bounds`), expressed against
Ekubo's TS/SDK in the dapp.

---

## Anti-rug guarantee

The **single on-chain guarantee** is the founder-allocation cap:

```
creator_allocation_bps <= 1000   // ≤ 10%
```

The creator gets at most 10% (transferred directly); the rest is liquidity for the
market. Nobody — creator included — can corner the supply and dump it.

There is **no liquidity lock**: the creator owns the LP position and may withdraw it
like any liquidity provider. The accountability for pulling liquidity is transparency
and reputation, not a platform-enforced lock — consistent with Medialane's
non-custodial posture. The quote-token set (STRK/ETH/USDC/wBTC) is **platform-layer UI
curation**, not on-chain; the factory accepts any ERC-20 quote token to stay
permissionless.

---

## Deploy (Starknet mainnet)

Dependency order: `EkuboAdapter` → `CoinFactory`.

```
EkuboAdapter(core, positions, fee, tick_spacing)
CoinFactory(creator_coin_class_hash, exchange_adapter_address)
```

Ekubo mainnet addresses:

| | Address |
|---|---|
| Core | `0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b` |
| Positions | `0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067` |
| Positions NFT | `0x07b696af58c967c1b14c9dde0ace001720635a660a8e90c565ea459345318b30` |
| Router | `0x0199741822c2dc722f6f605204f35e56dbc23bceed54818168c4c49e4fb8737e` |
| Token Registry V3 | `0x064bdb4094881140bc39340146c5fcc5a187a98aec5a53f448ac702e5de5067e` |
| STRK (a quote option) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |

`fee` / `tick_spacing` select the Ekubo fee tier the launchpad uses (confirm the tier
against Ekubo's standard pools during the fork test). Deploy is **authorization-gated**
(mainnet prod write) and **blocked until the audit + fork test pass**.

---

## Security notes (for the `cairo-auditor` pass)

The no-swap design keeps the attack surface small (no custom settlement in the fund
path). Focus areas:

- **CEI / reentrancy on `launch`.** The `quote_token` is permissionless
  (attacker-controllable). It is never *dispatched to* in `launch` (no `transfer_from`
  of quote — single-sided), but `coin.transfer` and the adapter call happen before some
  state writes; confirm no reentrancy path can mis-index or double-launch a coin
  (`coin_id_of`, `last_coin_id`).
- **The cap** under rounding: `total_supply * bps / 10000` — confirm the creator can
  never exceed 10% for any supply/bps, and `pool_amount` is exactly the remainder.
- **Deterministic salt** (`next_id`) for `deploy_syscall` — coin-address squatting /
  front-running of the deployed address.
- **Single-sided deposit assumptions** — that the off-chain `ticks` always describe a
  valid single-sided range so `mint_and_deposit_and_clear_both` deposits the coin
  (and dust is cleared back), for non-18-decimal quote tokens too (USDC 6, wBTC 8).
- **Token ordering** — `addr_lt` sort for `token0 < token1`, and that the `pool_id`
  hash is stable.
- **Position custody** — confirm the LP NFT truly lands with the creator and the
  factory/adapter retain nothing.

The Ekubo interaction itself uses Ekubo's own audited `Positions` peripheral; we add no
custom AMM math.

---

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
  creator_coin.cairo              CreatorCoin ERC-20 (immutable creator)
  coin_factory.cairo              CoinFactory (atomic launch: split + single-sided deposit)
  exchanges/ekubo_adapter.cairo   Real Ekubo IExchangeAdapter (deposit + position to creator)
  interfaces/                     ICreatorCoin, ICoinFactory, IExchangeAdapter
  events.cairo                    CoinLaunched
  types.cairo                     CoinRecord
  mocks/                          erc20, erc721, MockExchange
tests/tests.cairo                 5 unit tests
```

## Before mainnet

`unruggable.meme` (the design inspiration) is **explicitly unaudited** and targets an
old Cairo; this is a clean reimplementation on the current toolchain, but it has **not**
been audited either. Required before any deploy:

1. **Mainnet-fork test** against live Ekubo — confirm a real `launch` creates the pool,
   deposits the single-sided liquidity, and lands the position NFT with the creator.
2. **`cairo-auditor`** pass (focus areas above), findings remediated TDD-style.

Only then is the deploy task (authorization-gated) unblocked.
