# Collection Drop

A factory + collection system for launching timed NFT drops on Starknet. Organizers deploy `DropFactory` once; creators call `create_drop()` to spin up independent `DropCollection` ERC-721 contracts with configurable claim conditions, allowlists, and optional ERC-20 pricing.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `DropFactory` | `0x03587f42e29daee1b193f6cf83bf8627908ed6632d0d83fcb26225c50547d800` |
| Mainnet | Admin (`DEFAULT_ADMIN_ROLE` + `ORGANIZER_ROLE`) | `0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b` |

---

## Architecture

```
DropFactory (singleton)
  └─ create_drop() → deploys a DropCollection via deploy_syscall
       DropCollection (one per drop, independent ERC-721)
         ├─ claim(quantity)        — public mint with condition checks
         ├─ admin_mint(...)        — bypasses conditions, for gifting
         ├─ set_phase(...)         — atomic condition + allowlist update
         └─ withdraw_payments()    — pulls ERC-20 proceeds to organizer
```

## Claim Conditions (`ClaimConditions`)

| Field | Description |
|---|---|
| `start_time` | Unix timestamp after which claims open (0 = immediately) |
| `end_time` | Unix timestamp after which claims close (0 = never) |
| `price` | Price per token in payment token's smallest unit (0 = free) |
| `payment_token` | ERC-20 contract for payment (zero address if free) |
| `max_quantity_per_wallet` | Per-wallet mint cap (0 = unlimited) |

## Phase Transitions

Use `set_phase(conditions, allowlist_enabled)` to atomically swap conditions **and** the allowlist gate in a single transaction. This eliminates the race window that exists when calling `set_claim_conditions` and `set_allowlist_enabled` separately.

```
Phase 1 (allowlist only):
  set_phase({ ..., max_quantity_per_wallet: 2 }, allowlist_enabled: true)
  batch_add_to_allowlist([...])

Phase 2 (public):
  set_phase({ ..., max_quantity_per_wallet: 5 }, allowlist_enabled: false)
```

## Supply

- **Capped**: `max_supply > 0` — hard cap enforced in `_mint_batch` immediately before writing `last_token_id`.
- **Open edition**: `max_supply = 0` — unlimited mints; `remaining_supply()` returns `u256::MAX` as sentinel.

## Security Properties

- **CEI order** — mint state (`last_token_id`, `minted_by_wallet`) is committed *before* the ERC-20 `transfer_from` call. A re-entrant claim during payment sees the updated supply and wallet count, blocking double-claims.
- **Definitive supply guard** — `_mint_batch` re-checks supply immediately adjacent to the state write, eliminating any window between the pre-check in `_validate_claim` and the actual mint.
- **Immutable instances** — each `DropCollection` is non-upgradeable; `DEFAULT_ADMIN_ROLE` can only pause, never rug.

## Roles

| Role | Holder | Permissions |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Platform admin | Emergency pause |
| `ORGANIZER_ROLE` | Platform admin + creator | Conditions, allowlist, metadata, withdraw |

## Build & Test

```bash
# Requires scarb 2.9.2+ and snforge 0.48.1 (or scarb 2.18+ with SCARB_IGNORE_CAIRO_VERSION=true)
scarb build
SCARB_IGNORE_CAIRO_VERSION=true snforge test
```

## Upgrade Workflow (DropCollection class)

New features in `DropCollection` affect **future drops only** — existing deployed collections are immutable.

1. Modify `drop_collection.cairo` and `scarb build`
2. Declare new class: `sncast --profile drop-mainnet declare --contract-name DropCollection`
3. Update factory: `sncast --profile drop-mainnet invoke --contract-address <factory> --function set_drop_collection_class_hash --calldata <new_class_hash>`
