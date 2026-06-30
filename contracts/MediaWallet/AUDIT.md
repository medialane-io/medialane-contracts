# Audit Delta

This document describes all changes from the audited Argent baseline.
See `FORK.md` for the exact commit and audit reference.

## Removals (no new logic — reduced attack surface)

| File / Directory | Reason |
|---|---|
| `src/signer/webauthn.cairo` | WebAuthn/P256 deferred to Starknet native quantum-resistant upgrade |
| `src/signer/eip191.cairo` | Ethereum compat deferred to Phase 2 multichain |
| `src/multisig_account/` | Separate contract if ever needed; not this account |
| `src/mocks/` (partial) | Test utilities for removed modules only; `src5_mocks.cairo` retained |
| `Webauthn`, `Eip191` variants | Removed from `SignerType`, `SignerSignature`, `Signer` enums |

## Renames (no logic change)

| Before | After |
|---|---|
| `ArgentAccount` (contract) | `MediaWallet` |
| `IArgentAccount` / `IArgentMultiOwnerAccount` | `IMediaWalletAccount` |
| `IDeprecatedArgentAccount` | `IDeprecatedMediaWalletAccount` |
| `IEmitArgentAccountEvent` | `IEmitMediaWalletEvent` |
| `ArgentAccountEvent` | `MediaWalletEvent` |
| Package name `argent` | `media_wallet` |
| All `argent::` import paths | `media_wallet::` |

GPL-3.0 SPDX headers added to all `src/` files.

## New code (full audit scope)

### `src/factory.cairo` — `MediaWalletFactory`

Permissionless factory for deterministic `MediaWallet` deployment.

**Interface:**
- `deploy_wallet(owner_pubkey: felt252, salt: felt252) → ContractAddress`
- `compute_address(owner_pubkey: felt252, salt: felt252) → ContractAddress`
- `wallet_class_hash() → ClassHash`

**Properties:**
- `deploy_from_zero: true` — address is independent of factory address
- Class hash fixed at construction; factory is immutable
- No admin key, no upgrade, no fee
- Address computation uses standard Starknet Pedersen hash (CONTRACT_ADDRESS_PREFIX)

**Tests:** 4 tests in `tests/test_factory.cairo`
- `test_wallet_class_hash_is_fixed`
- `test_compute_address_matches_deploy`
- `test_deploy_wallet_different_salts_different_addresses`
- `test_compute_address_deterministic_before_deploy`

## Unchanged (covered by Argent audit)

- `src/multiowner_account/argent_account.cairo` → `MediaWallet` contract (rename only)
- `src/multiowner_account/owner_manager.cairo` — owner linked list component
- `src/multiowner_account/guardian_manager.cairo` — guardian component
- `src/multiowner_account/recovery.cairo` — escape struct and types
- `src/multiowner_account/upgrade_migration.cairo` — legacy migration (Webauthn/Eip191 migration paths removed)
- `src/multiowner_account/events.cairo` — account events
- `src/session/` — session key management (SNIP-9 compatible)
- `src/outside_execution/` — SNIP-9 V2 gasless execution
- `src/recovery.cairo` — EscapeStatus enum
- `src/upgrade.cairo` — owner-controlled replace_class component
- `src/signer/signer_signature.cairo` — Stark/secp256k1/secp256r1 verification (Webauthn/Eip191 variants removed)
- `src/linked_set/` — doubly-linked list (required by owner_manager)
- `src/utils/` — shared primitives
- `src/introspection.cairo` — SRC5 component
- `src/offchain_message.cairo` — SNIP-12 typed data
