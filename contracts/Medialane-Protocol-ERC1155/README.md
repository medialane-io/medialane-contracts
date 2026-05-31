# Medialane Protocol — ERC-1155 Venue (`Medialane1155`)

Immutable ERC-1155 marketplace venue for Medialane on Starknet. Off-chain signed
orders (SNIP-12), on-chain registration, partial fills. Fully independent of the
ERC-721 venue (separate contract, audit, and implementation).

## Design (redesign 2026-05-29, audit `medialane-core/docs/audits/2026-05-29-medialane-erc1155-audit.md`)

- **SNIP-12 `version = 3`** and a signed `marketplace: ContractAddress` field,
  asserted `== get_contract_address()` at registration — binds every order to one
  deployment (cross-deployment replay protection).
- **`fulfill_order(order_hash, quantity)`** — the caller IS the fulfiller; no
  fulfiller signature. Partial fills: `1 ≤ quantity ≤ remaining_amount`; the order
  stays `Created` until fully consumed.
- **Per-unit pricing**: the payment leg's `amount` is the price *per unit*;
  `sale = price_per_unit * quantity` (overflow-checked).
- **EIP-2981 royalties** read from the NFT at fulfilment and **capped at the
  seller-signed `royalty_max_bps`**; remainder to the seller. Uses the OZ
  `IERC2981_ID` constant (never a hardcoded hex).
- **Bulk-cancel via `counter`** (per-offerer epoch) instead of sequential nonces;
  `salt` provides per-order uniqueness (client must randomize).
- **Security**: reentrancy guard + payment-before-delivery (CEI), self-fill guard,
  shape allow-list (`ERC1155 ↔ {NATIVE, ERC20}`, both directions). Zero-price
  (free) orders allowed.
- Fully **immutable** — no owner/admin/upgrade/pause. Evolve by redeploy
  (fresh class, bump `version`).

## Entrypoints

`register_order` · `fulfill_order(order_hash, quantity)` · `cancel_order`
(offerer-signed) · `increment_counter` · views: `get_order_details`,
`get_order_hash`, `get_cancellation_hash`, `get_counter`, `get_native_token_address`.

## Build & test

```bash
~/.asdf/shims/scarb build
~/.asdf/shims/snforge test     # 33 tests; sign in-Cairo via snforge_std keypairs
```

## Deploy (fresh class + deploy; testing on mainnet)

```bash
scarb build
sncast --profile medialane1155-mainnet declare --contract-name Medialane1155
sncast --profile medialane1155-mainnet deploy \
  --class-hash <new_class_hash> \
  --arguments '<native_token_address>'   # STRK
```

Constructor takes only the native (STRK) token address. After deploy, register
the venue in the SDK service registry and point clients at the new class.
