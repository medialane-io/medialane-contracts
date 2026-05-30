# Medialane Protocol — ERC-721 Venue (`Medialane721`)

Immutable ERC-721 marketplace venue for Medialane on Starknet. Off-chain signed
orders (SNIP-12), on-chain registration, fixed-price sales and bids. Fully
independent of the ERC-1155 venue (separate contract, audit, and implementation).

## Design (redesign 2026-05-29, audit `medialane-core/docs/audits/2026-05-29-medialane-erc721-audit.md`)

- **SNIP-12 `version = 4`** and a signed `marketplace: ContractAddress` field,
  asserted `== get_contract_address()` at registration — binds every order to one
  deployment (cross-deployment replay protection).
- **`fulfill_order(order_hash)`** — the caller IS the fulfiller; no fulfiller
  signature.
- **EIP-2981 royalties** read from the NFT at fulfilment and **capped at the
  seller-signed `royalty_max_bps`**; remainder to the seller. Uses the OZ
  `IERC2981_ID` constant.
- **Bulk-cancel via `counter`** (per-offerer epoch) instead of sequential nonces;
  `salt` provides per-order uniqueness (client must randomize).
- **Security**: reentrancy guard + payment-before-delivery (CEI), self-fill guard,
  shape allow-list (`ERC721 ↔ {NATIVE, ERC20}`, both directions). Zero-price
  (free) orders allowed.
- Fully **immutable** — no owner/admin/upgrade/pause. Evolve by redeploy
  (fresh class, bump `version`).

## Entrypoints

`register_order` · `fulfill_order(order_hash)` · `cancel_order` (offerer-signed) ·
`increment_counter` · views: `get_order_details`, `get_order_hash`,
`get_cancellation_hash`, `get_counter`, `get_native_token_address`.

## Build & test

```bash
~/.asdf/shims/scarb build
~/.asdf/shims/snforge test     # 30 tests; sign in-Cairo via snforge_std keypairs
```

## Deploy (fresh class + deploy; testing on mainnet)

```bash
scarb build
sncast --profile medialane-mainnet declare --contract-name Medialane721
sncast --profile medialane-mainnet deploy \
  --class-hash <new_class_hash> \
  --arguments '<native_token_address>'   # STRK
```

Constructor takes only the native (STRK) token address. After deploy, register
the venue in the SDK service registry and point clients at the new class.
