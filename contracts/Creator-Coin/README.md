# Creator Coin contracts

Permissionless launchpad contracts for **Creator Coins** on Starknet: a fixed-supply
ERC-20 token plus a fully automated, **locked-liquidity** launch on Ekubo (and Jediswap).

Forked from Keep Starknet Strange's audited launchpad framework (see [LICENSE](LICENSE)).
The protocol mechanics are preserved verbatim; only the naming is Medialane's.

## Overview

A Creator Coin is created in two steps.

1. **Deploy** the `CreatorCoin` contract through the `Factory`, specifying the owner,
   name, symbol, and total supply. `CreatorCoin` is a standard ERC-20 plus a few
   framework functions:
   - `is_launched` — whether the coin has been launched yet.
   - `get_team_allocation` — the amount of tokens allocated to the team.
   - `liquidity_type` — the liquidity backing the coin: an NFT position on Ekubo, or an
     ERC-20 pair on a UniV2-style AMM.

2. **Launch** the coin on the chosen exchange (Ekubo or Jediswap); the process is fully
   automated. At launch the creator provides:
   - The address of the coin to launch.
   - The duration of transfer restrictions (which cap the percentage of total supply
     buyable in a single transaction while active — an anti-snipe guard).
   - The maximum percentage of total supply buyable per transaction while the
     restriction is active.
   - The quote token to use in the liquidity pool.

### Launch mechanics

- **Ekubo (capital-efficient):** liquidity is supplied only between fixed bounds, so a
  coin can launch without depositing a large amount of quote token.
  1. The team provides quote equal to the value of its allocation at the starting
     price, sent to the factory.
  2. The factory mints the liquidity positions: the team allocation concentrated in the
     first tick, then the remaining supply in the range above it.
  3. The factory uses the team's quote to buy the team allocation back out of the pool
     (the allocation is concentrated in the first tick, so it is bought back at ~the
     starting price) and forwards those tokens to the initial holders specified at
     launch.
  4. The principal LP position is held by the `EkuboLauncher` contract — **the liquidity
     is locked** — and pool fees are withdrawable by the coin's owner through
     `EkuboLauncher`.

- **Jediswap:** the creator supplies an amount of quote liquidity (e.g. ETH or STRK) and
  an unlock time. The amount supplied at launch sets the initial price (and marketcap),
  and the minted LP position is transferred to a locker for a minimum of 6 months
  (parametrizable at launch).

## Structure

### Contracts

- **Factory** (`src/factory/factory.cairo`) — creates and launches Creator Coins; the
  entrypoint for every interaction with the framework.
- **CreatorCoin** (`src/token/creator_coin.cairo`) — the ERC-20 token, deployed by the
  factory, with the extra framework functions above.
- **Lock manager** (`src/locker/lock_manager.cairo`) — locks ERC-20 tokens (including
  tokens with an increasing `balanceOf`) for a period. Each lock deploys a dedicated
  holder contract, released after the lock period; all interactions go through
  `LockManager`.
- **EkuboLauncher** (`src/exchanges/ekubo/launcher.cairo`) — automates the Ekubo launch
  (create the pool, add liquidity, hold the minted position) and lets coin owners
  withdraw the fees earned by the pool.

### Tests

`src/tests/`, written with [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/):

- `fork_tests/` — run against a fork of Starknet mainnet, used to exercise the contracts
  in a real environment (primarily the Ekubo interactions).
- `unit_tests/` — local isolation tests covering all contracts and their interactions,
  including the Jediswap flow (deployed locally).

## 🛠️ Build

```bash
scarb build
```

## 🧪 Test

Fork tests require an RPC key from a provider that supports v0.6 RPC (e.g. Nethermind or
BlastAPI). Add the URL to the `[[tool.snforge.fork]]` section of `Scarb.toml`, then:

```bash
snforge test
```

Unit tests need no RPC provider:

```bash
snforge test unit_tests
```

## 🚀 Deploy

```bash
cd scripts
cp .env.example .env   # fill in the values
npm run deploy
```

## 📖 License

MIT — see [LICENSE](LICENSE). Forked from Keep Starknet Strange's launchpad framework.
