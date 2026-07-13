# Medialane Protocol — ERC-721 Venue (`Medialane721`)

An immutable ERC-721 marketplace venue for Medialane on Starknet. Makers sign
orders off-chain (SNIP-12); anyone can register them on-chain and fulfil them.
Supports both fixed-price **listings** (sell an NFT) and **bids** (offer payment
for an NFT). Fully independent of the ERC-1155 venue — a separate contract with
its own class, storage, and implementation.

On-chain version: **v0.4.0** (`contract_version()`).

## What it does

- **Signed orders.** An order is a SNIP-12 typed message signed by the offerer.
  It names the traded NFT, the payment (native STRK or an ERC-20), a price, an
  optional validity window, and a royalty cap. No custody: the venue never holds
  assets — it pulls payment and delivers the NFT atomically at fulfilment.
- **Two directions.** A listing offers an ERC-721 for payment; a bid offers
  payment for an ERC-721. The venue enforces exactly this shape.
- **Fixed price.** One price per order, committed at signing (no Dutch/auction
  interpolation in this venue).
- **Free orders.** A zero payment amount is allowed (e.g. gifts, promos).

## Security model

Every check is on-chain and falls into one of two buckets:

1. **Statically determinable from the signed order** — validated at registration,
   fail-fast: offerer is non-zero, the order is bound to this exact contract,
   the offerer's bulk-cancel epoch matches, the royalty cap is within `[0, 100%]`,
   the trade shape is `ERC721 ↔ {NATIVE, ERC20}`, the recipient is non-zero, the
   time window is coherent, and the offerer's signature is valid.
2. **Mutable on-chain state** (ownership, approval, balance, live EIP-2981) — not
   pre-simulated; enforced by atomic revert at fulfilment.

Hardening properties:

- **Reentrancy guard + payment-before-delivery (CEI).** Terminal state is
  persisted before any external call; the guard covers `fulfill_order`,
  `register_order`, and `cancel_order`, so no lifecycle mutation can run inside a
  fill's settlement window.
- **Cross-deployment replay protection.** The order commits to the marketplace
  address (`marketplace == self`) and to a SNIP-12 domain version, so a signature
  for one deployment cannot be replayed against another.
- **Bulk cancel via `counter`.** Each offerer has a cancel epoch; an order is only
  valid while its `counter` matches the offerer's current epoch. Calling
  `increment_counter` invalidates all of that offerer's outstanding orders at
  once. A per-order `salt` gives economically-identical orders distinct hashes.
- **Self-fill guard.** An offerer cannot fulfil their own order.
- **EIP-2981 royalties, capped.** The royalty is read live from the NFT at
  fulfilment and paid to the creator, but never above the seller-signed
  `royalty_max_bps`. Non-2981 collections or any failure yield no royalty (the
  seller keeps the full amount) rather than blocking the sale.
- **Immutable.** No owner, admin, upgrade, or pause. Evolve by deploying a fresh
  class and bumping the version.

## Entrypoints

**Writes**
- `register_order(order)` — register a maker's signed order.
- `fulfill_order(order_hash)` — the caller IS the fulfiller; no fulfiller
  signature required.
- `cancel_order(cancel_request)` — cancel a single order (offerer-signed, so a
  relayer can submit it).
- `increment_counter()` — bulk-cancel all of the caller's outstanding orders.

**Views**
- `get_order_details(order_hash)`
- `get_order_hash(parameters, signer)`
- `get_cancellation_hash(cancellation, signer)`
- `get_counter(offerer)`
- `get_native_token_address()`
- `contract_version()`

## Events

`OrderCreated` · `OrderFulfilled` (enriched with the economic outcome:
`sale_amount`, `royalty_receiver`, `royalty_amount`) · `OrderCancelled` ·
`CounterIncremented`.

## Build & test

```bash
scarb build
snforge test
```

## Deploy

```bash
scarb build
sncast declare --contract-name Medialane721
sncast deploy --class-hash <new_class_hash> --arguments '<native_token_address>'
```

The constructor takes a single argument: the native (STRK) token address, used to
resolve `NATIVE` payment legs to a concrete ERC-20.
