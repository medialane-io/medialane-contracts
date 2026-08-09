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
| `src/utils/bytes.cairo` | Dead sha256/byte helpers left over from the removed WebAuthn path (zero callers); deleted 2026-08-03. Account class hash unchanged — was already dead-code-eliminated from the Sierra. |
| `IMediaWallet` trait (`src/account.cairo`) | Unused, multisig-shaped trait never embedded (the live interface is `IMediaWalletAccount`); deleted 2026-08-03 with its orphaned `Signer` import. |

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
| Error short-string prefix `'argent/…'` | `'wallet/…'` (same length — every string stays ≤ 31 chars; no logic change) |
| `src/multiowner_account/argent_account.cairo` | `src/multiowner_account/wallet_account.cairo` (file/module rename; contract was already `MediaWallet`) |
| `tests/argent_account/`, `tests/setup/argent_account_setup.cairo`, `ARGENT_ACCOUNT_ADDRESS` | `tests/wallet_account/`, `tests/setup/wallet_account_setup.cairo`, `WALLET_ACCOUNT_ADDRESS` |
| Doc comments naming the removed `Eip191` variant | reference only the retained signer types |

GPL-3.0 SPDX headers added to all `src/` files.

## New code (full audit scope)

**None.** The delta from the audited baseline is renames and removals only — no logic was
added to or modified in the account. A future audit engagement scoped to "the MediaWallet
delta" therefore has an empty logic scope; what remains to review is that the removals are
complete and that the renames are faithful, both of which a normalized diff against
`6243bcf` demonstrates mechanically.

`src/factory.cairo` (`MediaWalletFactory`) previously occupied this section. It was removed
2026-08-09 as redundant: it derived addresses with `deploy_from_zero: true`, which is the
same derivation a native `DEPLOY_ACCOUNT` transaction performs, and the account already
validates its own deployment through `__validate_deploy__`. Wallets deploy themselves; see
the README. Removing it left the `MediaWallet` class hash byte-identical
(`0x14b210c7d47392691144bafecdca3c6c7791cc295ea305988da0a724c05ac31`), so no already-deployed
wallet is affected. The factory instance previously declared on mainnet is abandoned, not
migrated — it never deployed a wallet.

## Unchanged (covered by Argent audit)

- `src/multiowner_account/wallet_account.cairo` — the `MediaWallet` contract (rename only)
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
