# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Overview

Cairo smart contracts for the Medialane platform on Starknet mainnet.

## Toolchain

- **sncast** (Starknet Foundry) — deploy, declare, invoke, call. Version: 0.55.0+
- **scarb** — Cairo build tool
- **snfoundry.toml** — named network + account profiles

```bash
# Build
scarb build

# Declare (publish class)
sncast --profile nftcomments-mainnet declare --contract-name <ContractName>

# Invoke (call a write method)
sncast --profile nftcomments-mainnet invoke \
  --contract-address <address> \
  --function <fn_name> \
  --calldata <felts>
```

**Important sncast notes:**
- Version in use: `0.59.0` (via asdf — run `~/.asdf/shims/sncast` if not in PATH)
- `--fee-token` flag is NOT supported — omit it entirely (fee paid in ETH by default)
- If upgrade fails with "Caller is not the owner" — contract owner may be a different wallet. Use Starkscan "Write Contract" UI as the owner wallet instead.

## Deployer Accounts

| Name | Address | Purpose |
|---|---|---|
| `medialane-deployer` | `0x06acfcef048dcaac4a11fab313507d53145ed2a468f2a6188527918f1b12d935` | New mainnet deployer — fund with ~0.1 STRK before first deploy |
| `mediolanoprotocol` | `0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b` | Legacy admin — owner/admin role on all existing contracts |
| `nftcomments-deployer` | see CLAUDE.md NFTComments section | NFTComments upgrade deployer |

Accounts file: `/Users/medialane/.starknet_accounts/starknet_open_zeppelin_accounts.json`

**Deploy a new account (one-time after funding):**
```bash
~/.asdf/shims/sncast account deploy \
  --url "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/tOTwt1ug3YNOsaPjinDvS" \
  --name medialane-deployer
```

---

## Contracts

### NFTComments (`contracts/NFTComments/`)

Stores on-chain NFT comments as events. No comment storage on-chain — comments live in `CommentAdded` events, indexed by the backend.

- **Mainnet address**: `0x070edbfa68a870e8a69736db58906391dcd8fcf848ac80a72ac1bf9192d8e232`
- **Class hash (after 2026-03-22 upgrade)**: `0x1edbebcd184c3ea65c19f59f2cbc11ef8b3a2883b4fe97db1caf0b29c6ea0dd`
- **Owner**: `0x05f9f8d300601199297b7ecd92928e1444a2556aa84c8544b8b513d2a18a65a2` (personal wallet)
- **Upgrade tx**: `0x1aaeebe7d63e3090b725393a4eb09375f05063440e0f97ce0ce6b659a60329f`
- **Deployer account**: `nftcomments-deployer` (in `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`)

**Key features:**
- `add_comment(nft_contract, token_id, content)` — emits `CommentAdded` event
- 60s per-address rate limit: `last_comment_time: Map<ContractAddress, u64>` + `assert!(now >= last_time + 60_u64, ...)`
- Max comment length: 1000 bytes (enforced on-chain)
- Content stored as Cairo `ByteArray`
- Upgradeable (OZ UpgradeableComponent) + Ownable (OZ OwnableComponent)

**`CommentAdded` event:**
```cairo
struct CommentAdded {
    #[key] nft_contract: ContractAddress,
    #[key] token_id: u256,
    #[key] author: ContractAddress,
    content: ByteArray,
    timestamp: u64,
}
```

**Upgrade workflow:**
1. `scarb build` in `contracts/NFTComments/`
2. `sncast --profile nftcomments-mainnet declare --contract-name NFTComments` → get new class hash
3. Invoke `upgrade(new_class_hash)` as the **owner wallet** (not `nftcomments-deployer` unless they match)
4. If ownership mismatch: use Starkscan "Write Contract" → connect owner wallet → call `upgrade`

**Storage import pitfall**: `Map<K, V>` read/write requires explicit trait imports:
```cairo
use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};
```

### Pop-Protocol (`contracts/Pop-Protocol/`)

Soulbound proof-of-participation credentials. Factory + collection pattern: platform deploys one POPFactory; organizers call `create_collection()` to deploy per-event POPCollection instances.

- **POPFactory address**: `0x00b32c34b427d8f346b5843ada6a37bd3368d879fc752cd52b68a87287f60111`
- **POPFactory class hash**: `0x0785b924853826513482486707bb3acee462e5a465a0c917267aad4f0ecc3bae`
- **POPCollection class hash**: `0x077c421686f10851872561953ea16898d933364b7f8937a5d7e2b1ba0a36263f`
- **Deploy block**: `8328934`
- **Admin (DEFAULT_ADMIN_ROLE + ORGANIZER_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Deploy tx**: `0x0093f80504b888511bef39f7a5cc20e0c8b99ebdff16908d937efe9a38d06799`
- **Deployer account**: `mediolanoprotocol` (in `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`)
- **snfoundry.toml profile**: `pop-mainnet` (in `contracts/Pop-Protocol/snfoundry.toml`)

**Build + declare workflow:**
```bash
# Full PATH required (scarb + cargo + universal-sierra-compiler all from kalamaha user)
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile pop-mainnet declare --contract-name POPCollection
PATH="..." sncast --profile pop-mainnet declare --contract-name POPFactory
PATH="..." sncast --profile pop-mainnet deploy \
  --class-hash <factory_class_hash> \
  --arguments '<admin>, <pop_collection_class_hash>'
```

**Upgrading POPCollection class (new features):**
1. Modify contract, `scarb build`, declare new POPCollection → new class hash
2. Call `set_pop_collection_class_hash(new_class_hash)` on the factory as admin
3. All new `create_collection()` calls will deploy the updated class
4. Existing deployed collections are unaffected (immutable once deployed)

**Backend env vars:**
```
POP_FACTORY_ADDRESS=0x00b32c34b427d8f346b5843ada6a37bd3368d879fc752cd52b68a87287f60111
POP_START_BLOCK=8328934
```

**Key events indexed by backend:**
- `POPFactory::CollectionCreated` → registers Collection with `source: POP_PROTOCOL`
- `POPCollection::AllowlistUpdated` → syncs PopAllowlist table (slow-poll per collection)

### Collection-Drop (`contracts/Collection-Drop/`)

Multi-tenant timed NFT drop service. Factory + collection pattern: platform deploys one DropFactory; organizers call `create_drop()` to deploy per-drop DropCollection instances (transferable ERC-721).

- **DropFactory address**: `0x03587f42e29daee1b193f6cf83bf8627908ed6632d0d83fcb26225c50547d800`
- **DropFactory class hash**: `0x072b3f26370b2a125732165dd07491e808a0de67ab9e0f95e5ab9013b15a3383`
- **DropCollection class hash**: `0x00092e72cdb63067521e803aaf7d4101c3e3ce026ae6bc045ec4228027e58282`
- **Admin (DEFAULT_ADMIN_ROLE + ORGANIZER_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Deploy tx**: `0x058fb5762389cd23e6e7e36089bff5dc7546c03f7fd34673504564fc34614696`
- **Deployer account**: `mediolanoprotocol` (in `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`)
- **snfoundry.toml profile**: `drop-mainnet` (in `contracts/Collection-Drop/snfoundry.toml`)

**Build + declare workflow:**
```bash
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile drop-mainnet declare --contract-name DropCollection
PATH="..." sncast --profile drop-mainnet declare --contract-name DropFactory
PATH="..." sncast --profile drop-mainnet deploy \
  --class-hash <factory_class_hash> \
  --arguments '<admin>, <drop_collection_class_hash>'
```

**Gas note**: DropCollection declaration costs ~59 STRK (large contract). The `mediolanoprotocol` account needs ~200+ STRK balance before declaring — sncast sets max bounds at ~2.25x estimated fee. If declare fails with "Resources bounds exceed balance", top up the account.

**Upgrading DropCollection class (new features):**
1. Modify contract, `scarb build`, declare new DropCollection → new class hash
2. Call `set_drop_collection_class_hash(new_class_hash)` on the factory as admin
3. All new `create_drop()` calls will deploy the updated class

**Test runner:**
```bash
PATH="...snforge 0.48.1 bin..." snforge test
# Uses snforge_std_deprecated = "0.48.1" in Scarb.toml (required for Scarb < 2.12.0)
```

**Backend env vars (to add):**
```
DROP_FACTORY_ADDRESS=0x03587f42e29daee1b193f6cf83bf8627908ed6632d0d83fcb26225c50547d800
DROP_START_BLOCK=8341335
```

**Key events indexed by backend:**
- `DropFactory::DropCreated` → registers Collection with `source: COLLECTION_DROP`
- `DropCollection::TokensClaimed` → updates mint counts

---

### Creator-Coin (`contracts/Creator-Coin/`)

Permissionless launchpad for **Creator Coins** — a **faithful fork of Keep Starknet
Strange's audited launchpad framework** (MIT; `LICENSE` in the package). Protocol
mechanics are preserved verbatim; only the naming is Medialane's (renamed end to end —
**no `unruggable`/`memecoin` identifiers remain anywhere in the package**).

A coin is created in two steps: (1) deploy a fixed-supply ERC-20 `CreatorCoin` via the
`Factory` (permissionless); (2) launch it on Ekubo (owner-only, once) with
transfer-restriction (anti-snipe) params and a quote token. At launch all liquidity goes
into the Ekubo pool, the team allocation (≤10% of supply, ≤10 holders) is bought back out
at the starting price and distributed, and the coin's ownership is renounced. **The
principal LP position is held permanently by `EkuboLauncher`** — no code path withdraws
it; only pool fees (quote side) are withdrawable by the position owner. Ekubo-only since
v0.2.0: the Jediswap/StarkDeFi adapters and the `LockManager` locker are removed
(Ekubo's NFT position in the launcher IS the lock).

- **Status**: **v0.2.0, merged to `main` (PR #11, 2026-07-09)** — on-chain `version()`
  ("0.2.0") on Factory/CreatorCoin/EkuboLauncher, Ekubo-only purge, dead-code cleanup.
  25/25 unit tests green on the pinned toolchain; audited (`cairo-auditor`, no
  Critical/High — `medialane-core/docs/audits/2026-06-03-creator-coin-audit.md`) plus a
  full source review 2026-07-09 (PR #11). **The mainnet deployment below is the
  2026-06-04 pre-v0.2.0 build (Ekubo-only)** — v0.2.0 on `main` is not yet
  declared/deployed.
  Ekubo fork tests were *not* runnable (snforge 0.16 can't fork current mainnet / Sierra
  1.7.0) — the Ekubo launch path is validated by unrug's production history + audit + a
  **team smoke launch (✅ passed 2026-06-04** — tx `0x253e00…233d77`, coin
  `0x6d42e3…2500a0`; verified is_launched, team alloc distributed, LP locked in
  EkuboLauncher as EkuboNFT 2287380).

- **Integration requirements** (2026-07-09 audit; also in `@medialane/sdk` CLAUDE.md):
  1. The quote transfer that funds the team buyback and `launch_on_ekubo` must be **one
     atomic multicall** (SDK: `quoteFundAmount`) — the buyback sweeps the Factory's
     entire quote balance, so quote pre-funded in a separate tx can be consumed by
     someone else's launch.
  2. **Team allocation must sum to ≥ 1 coin (1e18 raw)** — the launcher donates exactly
     1 coin to the Ekubo token registry out of the team position, so less (including
     zero holders) reverts with an unreadable u256 underflow. Validate app-side.
  3. Coin-side pool fees are unrecoverable by design (`withdraw_fees` pays quote only).
  4. The anti-snipe max-buy cap is per-transaction — friction, not a guarantee.

  **Mainnet deployment (2026-06-04, deployer `medialane-deployer`
  0x06acf…35, via Lava RPC + starknet.js):**

  | Item | Address / hash |
  |---|---|
  | **Factory** (entrypoint) | `0x50fa807b5274079fb19374673d7bab6d2dc3af7e1032ea43eb6e44bcbde4c3c` |
  | **EkuboLauncher** | `0x4f7fceb5ac10f12f9544a09580592e5bdf1b7f04f48765eecf12286d8ccb7b4` |
  | CreatorCoin class hash | `0x743e4c8a5b96bb83bbf4af04edbbb482d5ece89eed9b729a79fb7df0cd0b6b6` |
  | EkuboLauncher class hash | `0x701706df0fd3dcac12eb0f810e7142eae7bf2b25fb279259331195e0053e9be` |
  | Factory class hash | `0x51765926b1344c9a20b8cd4b5abe7b7d47375ae97cf6804db3ea5d4b05a9b55` |

  Deployed (pre-v0.2.0) Factory ctor: `(creator_coin_class_hash, lock_manager=0x0
  [unused], exchanges=[(Ekubo, launcher)], migrated=[])` → **only Ekubo registered**.
  The v0.2.0 Factory ctor is `(creator_coin_class_hash, exchanges)`. EkuboLauncher ctor:
  `(core, registry, positions, router)` with unrug-matched Ekubo addrs (Core
  `0x00…0325b4b`, Registry `0x0013e258…`, Positions `0x02e0af…`, Router `0x01b6f5…`).
  Verified on-chain: classes deployed, Ekubo wired, Jediswap disabled. **The deployer is
  also `CreatorCoin.owner`-eligible only via `create_creator_coin` (permissionless).**
- **Contracts**: `Factory` (`src/factory/factory.cairo`, the entrypoint), `CreatorCoin`
  (`src/token/creator_coin.cairo`, ERC-20 + framework fns `is_launched` /
  `get_team_allocation` / `liquidity_type`), `EkuboLauncher`
  (`src/exchanges/ekubo/launcher.cairo`, holds the locked LP positions).
- **Provenance / design note**: forked from `keep-starknet-strange/unruggable.meme`
  `packages/contracts`. ⚠️ The earlier
  `medialane-core/docs/specs/2026-06-02-creator-coin-CORRECTED-model.md` (non-custodial,
  no-lock, no-buyback, LP-to-creator) was **scrapped** — it misread the upstream and
  broke the anti-rug guarantee. The shipped design is the faithful fork above (permanent
  Ekubo LP lock + team buyback). Treat that doc as historical until rewritten.

> **Toolchain note:** this package keeps **unrug's own toolchain** — `starknet 2.4.3` /
> `openzeppelin 0.8.0` / `snforge_std 0.16.0` (pinned in the package `Scarb.toml`).
> Each `contracts/*` package is self-contained with its own toolchain (there is no root
> workspace), so this does not need to match the 2.18 packages. The leftover
> `.tool-versions` (scarb 2.18) is stale and does not reflect what the package compiles
> against. Building/testing requires installing scarb ~2.4.3 + starknet-foundry ~0.16.

**Build + test:**
```bash
cd contracts/Creator-Coin
scarb build
snforge test               # fork tests need an RPC url in [[tool.snforge.fork]]
snforge test unit_tests    # unit tests need no RPC
```

**Backend indexing / env vars (post-deploy):** to be mapped against the fork's actual
factory launch events once the package is finalized and deployed (`CREATOR_COIN_FACTORY_ADDRESS`,
`CREATOR_COIN_START_BLOCK`).

---

### MediaWallet (`contracts/MediaWallet/`)

Self-sovereign Starknet account contract (GPL-3.0, open source). **Faithful fork of
`argentlabs/argent-contracts-starknet` at the ChainSecurity-audited v0.5.0 commit** —
the exact baseline commit is pinned in `FORK.md` and the five baseline audit PDFs are
vendored in `audit/`. The complete delta from the audited baseline lives in `AUDIT.md`
(that delta is the scope of any future audit engagement).

**Delta from baseline:** WebAuthn/P256, EIP-191, and the multisig module removed
(trailing `SignerSignature` enum variants — remaining wire indices Starknet=0,
Secp256k1=1, Secp256r1=2 are byte-identical to the audited baseline); renamed end to
end (**no `argent` identifiers remain in any `.cairo` file** — error short-strings use
the `'wallet/…'` prefix, same length as the original so all stay ≤ 31 chars); one piece
of new code: `MediaWalletFactory` (`src/factory.cairo`, ~100 lines).

**Key properties:**
- Single Stark-curve owner; optional user-designated guardian recovery; session keys;
  SNIP-9 V2 outside execution (gasless/paymaster). SNIP-12 domains are deliberately
  unchanged from upstream (`'SessionAccount.session'`, `'Account.execute_from_outside'`)
  so standard session/paymaster tooling works.
- The concise 2-felt/4-felt Stark signature path is intact — plain starknet.js accounts
  work unmodified.
- Owner-controlled `replace_class` upgrades; `get_name()` returns `'MediaWallet'` and
  the upgrade path asserts name equality, so Argent↔MediaWallet cross-grades are
  structurally blocked.
- `MediaWalletFactory`: permissionless, immutable (class hash fixed at construction, no
  admin/fee/upgrade), `deploy_from_zero: true` — the wallet address depends only on
  class hash + salt + owner pubkey, never on the factory (counterfactual
  `compute_address` before deploy).

- **Status**: on `main` (added 2026-06-30; rename completed 2026-07-09), audited-fork
  review passed 2026-07-09, **not yet declared/deployed**.

> **Toolchain:** scarb 2.10.1 + starknet-foundry 0.38.3, pinned in the package
> `.tool-versions` (both installed via asdf on this machine).

**Build + test:**
```bash
cd contracts/MediaWallet
scarb build
snforge test    # 120 tests, no RPC needed
```

**Deploy:** declare `MediaWallet` → deploy `MediaWalletFactory(wallet_class_hash)` →
wallets via `factory.deploy_wallet(owner_pubkey, salt)`; predict addresses with
`factory.compute_address(owner_pubkey, salt)`.

---

### Medialane-Protocol-ERC721 (`contracts/Medialane-Protocol-ERC721/`)

> **REDESIGN IN PROGRESS (2026-05-30, branch `feat/marketplace-721-redesign`, NOT yet audited/deployed).**
> The contract is renamed **`Medialane721`** (SNIP-12 version **4**), package `0.4.0`, 30 snforge tests.
> New signed order schema (`marketplace` binding, `royalty_max_bps`, `counter`; no `nonce`/`end_amount`),
> EIP-2981 royalties, reentrancy guard + payment-before-delivery, self-fill guard, shape allow-list.
> Declare with `--contract-name Medialane721`. Full record + deploy/migration plan:
> `medialane-core/docs/audits/2026-05-30-marketplace-redesign-implementation.md`.
> The addresses below are the **current live (pre-redesign)** deployment, to be superseded by a fresh class.

Core marketplace contracts (order registration, fulfillment, cancellation). Audited and redeployed 2026-04-05.

- **Contract address**: `0x0234f4e8838801ebf01d7f4166d42aed9a55bc67c1301162decf9e2040e05f16`
- **Class hash**: `0x06e45fbc001580e52948d528e236002cd35a226b557a81400e0fb77ddbaa7727`
- **Deploy tx**: `0x0272a9d748dc4a589f19c1445474ff6833f50bc6cb2c09a20295fcf0e4ccbc31`
- **Manager (DEFAULT_ADMIN_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Native token**: STRK (`0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`)
- **snfoundry.toml profile**: `medialane-mainnet` (in `contracts/Medialane-Protocol/snfoundry.toml`)

**Previous deployment**: `0x04299b51289aa700de4ce19cc77bcea8430bfd1aef04193efab09d60a3a7ee0f` (superseded — security fixes applied)

**Key security fixes in this deployment (2026-04-05):**
- M-03: `cancel_order` now verifies signer is the order's offerer
- M-02: `fulfill_order` now verifies caller == fulfiller (prevents front-running)
- M-04: `end_amount` must equal `start_amount` (fixed price enforced)
- M-01: Immediate-validity orders (`start_time == now`) now registerable
- M-05: CEI pattern — order marked Filled before ERC-1155 external call
- M-06/07/08/09: input validation hardened throughout

**Build + declare + deploy workflow:**
```bash
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile medialane-mainnet declare --contract-name Medialane
PATH="..." sncast --profile medialane-mainnet deploy \
  --class-hash <new_class_hash> \
  --arguments '<manager_address>, <native_token_address>'
```

---

### Medialane-Protocol-ERC1155 (`contracts/Medialane-Protocol-ERC1155/`)

> **REDESIGN IN PROGRESS (2026-05-30, branch `feat/marketplace-1155-redesign`, NOT yet audited/deployed).**
> The contract is renamed **`Medialane1155`** (drop the `V2` suffix; SNIP-12 version **3**), package `0.4.0`, 33 snforge tests.
> Same new order schema as the 721 venue (`marketplace` binding, `royalty_max_bps`, `counter`; no `nonce`/`end_amount`),
> partial fills, **corrected EIP-2981 interface id** (the old hardcoded id never matched the OZ collection → royalties
> were silently unpaid), reentrancy guard + payment-before-delivery. `fulfill_order(order_hash, quantity)`, no fulfiller sig.
> Declare with `--contract-name Medialane1155`. Full record: `medialane-core/docs/audits/2026-05-30-marketplace-redesign-implementation.md`.
> The addresses below are the **current live (pre-redesign)** deployment, to be superseded by a fresh class.

ERC-1155 marketplace with partial fills. Redesigned and deployed 2026-04-20.

- **Contract address**: `0x03aab04e806542cd88bfd0c5bb2a37334fd742d477a2e0f97af09aa4a36137ca`
- **Class hash**: `0x6c7b47744ff1a99eacdfe0f097fdae9f5c45d0cf660ae5170b1e7d270c19313`
- **Declare tx**: `0x34471831de2d90cfdcece30aa457127231b0153f8b7472aa233cfcbc535197`
- **Deploy tx**: `0xabb28bd7056b8ad5465ef9eebdc691c013eb7808be7a1d948fde4308c75a4b`
- **Manager (DEFAULT_ADMIN_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Native token**: STRK (`0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`)
- **snfoundry.toml profile**: `medialane1155-mainnet`

**Previous deployment**: `0x042005e9b85536072bfa260b95aa6aaef07f48e622031657384d2375195d7123` (broken — never emitted any OrderCreated events)

**Key changes in this deployment (2026-04-20):**
- Partial fills: buyer chooses `quantity` (1 ≤ Q ≤ remaining_amount); order stays `Created` until fully consumed
- `OrderFulfillment` struct: added `quantity: felt252` between `fulfiller` and `nonce`
- `OrderDetails` struct: `fulfiller: Option` removed; `remaining_amount: felt252` added
- `FULFILLMENT_TYPE_HASH` updated to match new struct field order
- New errors: `INVALID_QUANTITY`, `INSUFFICIENT_REMAINING`
- `OrderFulfilled` event: added `quantity` + `remaining_amount` fields

**Build + declare + deploy workflow:**
```bash
cd contracts/Medialane-Protocol-ERC1155
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile medialane1155-mainnet declare --contract-name Medialane1155
PATH="..." sncast --profile medialane1155-mainnet deploy \
  --class-hash <new_class_hash> \
  --arguments '0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b, 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d'
```

---

## Network Config (`snfoundry.toml`)

```toml
[sncast.nftcomments-mainnet]
account = "nftcomments-deployer"
accounts-file = "/Users/kalamaha/.starknet_accounts/starknet_open_zeppelin_accounts.json"
network = "mainnet"

[sncast.pop-mainnet]
account = "mediolanoprotocol"
accounts-file = "/Users/medialane/.starknet_accounts/starknet_open_zeppelin_accounts.json"
url = "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/tOTwt1ug3YNOsaPjinDvS"
wait-params = { timeout = 300, retry-interval = 10 }

[sncast.drop-mainnet]
account = "mediolanoprotocol"
accounts-file = "/Users/medialane/.starknet_accounts/starknet_open_zeppelin_accounts.json"
url = "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/tOTwt1ug3YNOsaPjinDvS"
wait-params = { timeout = 300, retry-interval = 10 }
```

**Accounts file location**: The `starknet_open_zeppelin_accounts.json` was originally at `/Users/kalamaha/.starknet_accounts/` (old username) and has been copied to `/Users/medialane/.starknet_accounts/`. Both paths work.

Add new profiles here for additional contracts/accounts.

---

### MDLN Token (`contracts/MDLN/`) — Ethereum L1 (Solidity)

Governance and utility token for the Medialane DAO. Deployed on Ethereum mainnet; bridged to Starknet via StarkGate.

- **Stack**: Solidity 0.8.24 + OpenZeppelin v5 + Hardhat
- **Token contract**: `medialane.sol` → `MedialaneToken`
- **Vesting contract**: `MDLNVesting.sol`
- **Status**: Deployed and verified on Ethereum mainnet (2026-04-07)
- **MDLN Token (mainnet)**: `0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15`
- **MDLNVesting (mainnet)**: `0x912f61d5e6db656ec1a7be8db8957c5f1e345d58`
- **Gnosis Safe (DAO treasury)**: `0xA7603783edD8ee6FF4B085f90Af53341282d244C` (Ethereum mainnet)
- **Sepolia MDLN**: `0x3c64605Bd08A49032FaF44c4C71d5549cAee09Ef`
- **Sepolia Vesting**: `0x77566634d13Fdf6ae292270eeB26d50De74faafA`

**Tokenomics:**
- Supply: 21,000,000 MDLN (fixed, no minting)
- 100% minted to Gnosis Safe at deploy
- Safe transfers 18.9M to `MDLNVesting` → unlocks 2.1M/year for 9 years
- Safe retains 2.1M as operational runway
- No team allocation, no VCs — community enters via LP
- Initial LP seeding: Starknet Foundation grant (in progress)

**Key design:**
- `ERC20Votes` — native Snapshot + future on-chain Governor support
- `ERC20Permit` — gasless approvals, required by StarkGate
- `ERC20Burnable` — fee-burn mechanics via DAO vote
- Fully immutable — no owner, no admin, no upgrade
- Custom errors: `MDLN_ZeroAddress`, `MDLN_TreasuryNotContract`
- Treasury must be a contract (rejects EOA deploy)

**Vesting contract (`MDLNVesting`):**
- Holds 18.9M MDLN, releases 2.1M/year to Gnosis Safe
- Permissionless `release()` — anyone can trigger once tranche is due
- Catch-up safe — multiple elapsed tranches released in one call
- Views: `tranchesDue()`, `nextReleaseAt()`, `lockedBalance()`

**Build & test (requires Node 22 LTS):**
```bash
# Install Node 22 via Homebrew if needed:
# brew install node@22

cd contracts/MDLN
cp .env.example .env   # fill DEPLOYER_PRIVATE_KEY, ETH_RPC_URL, ETHERSCAN_API_KEY
npm install
npx hardhat test

# Deploy to Sepolia (testnet)
npx hardhat run scripts/deploy.js --network sepolia

# Deploy to mainnet
npx hardhat run scripts/deploy.js --network mainnet
npx hardhat verify --network mainnet <token_address> "0xA7603783edD8ee6FF4B085f90Af53341282d244C"
npx hardhat verify --network mainnet <vesting_address> "<token_address>" "0xA7603783edD8ee6FF4B085f90Af53341282d244C"
```

**Post-deploy checklist:**
1. From Gnosis Safe: transfer 18,900,000 MDLN to vesting contract
2. Verify both contracts on Etherscan
3. Register MDLN on StarkGate for L2 bridging
4. Create Snapshot space pointing at MDLN token address
5. Seed Uniswap LP (after Starknet Foundation grant lands)
