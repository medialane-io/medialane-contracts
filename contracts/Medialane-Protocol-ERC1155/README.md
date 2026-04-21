# Medialane Protocol — ERC-1155

A specialized on-chain marketplace for trading ERC-1155 IP assets on Starknet. Built for the [Mediolano](https://mediolano.app) protocol, it enables creators and collectors to list, buy (in full or in partial quantities), and cancel ERC-1155 token listings using off-chain SNIP-12 signatures, with automatic on-chain royalty distribution via ERC-2981.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `Medialane1155` v2 (current) | `0x03aab04e806542cd88bfd0c5bb2a37334fd742d477a2e0f97af09aa4a36137ca` |
| Mainnet | `Medialane1155` v1 (deprecated) | `0x042005e9b85536072bfa260b95aa6aaef07f48e622031657384d2375195d7123` |
| Mainnet | Manager (DEFAULT_ADMIN_ROLE) | `0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b` |
| Mainnet | Native token (STRK) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |

This contract is the ERC-1155 companion to `Medialane-Protocol` (which handles ERC-721 assets). It is designed to work with IP collections deployed via `IP-Programmable-ERC1155-Collections` (factory: `0x0459a9a3c04be5d884a038744f977dff019897264d4a281f9e0f87af417b3bec`).

---

## What Changed in v2 (partial fills)

v2 introduces **partial fill support** — a buyer can purchase any quantity from 1 up to the full remaining supply in a single transaction. Orders stay `Created` (active) until all units are sold.

Key changes from v1:

| Area | v1 | v2 |
|---|---|---|
| `OrderDetails.fulfiller` | `Option<ContractAddress>` | removed |
| `OrderDetails.remaining_amount` | — | `felt252` — units still available |
| `OrderFulfillment.quantity` | — | `felt252` — units to buy |
| `OrderStatus` after partial fill | `Filled` | `Created` (still active) |
| `OrderStatus` after full fill | `Filled` | `Filled` |
| `OrderFulfilled` event | no quantity/remaining | includes `quantity` + `remaining_amount` |
| SNIP-12 `OrderFulfillment` type hash | `(order_hash, fulfiller, nonce)` | `(order_hash, fulfiller, quantity, nonce)` |

---

## Overview

The contract implements a fixed-price order book with partial fill support:

1. A seller signs an `OrderParameters` struct off-chain using SNIP-12.
2. The signed order is submitted on-chain via `register_order` — stored with `remaining_amount = amount`.
3. A buyer signs an `OrderFulfillment` off-chain (including the desired `quantity`) and submits via `fulfill_order`.
4. On fulfillment the contract atomically:
   - Decrements `remaining_amount` by `quantity`. Sets status to `Filled` only when `remaining_amount == 0`.
   - Transfers `quantity` ERC-1155 tokens from seller to buyer via `safe_transfer_from`.
   - Queries ERC-2981 royalty on `price_per_unit × quantity` and pays the royalty receiver.
   - Transfers the remaining proceeds to the seller.
5. The seller can cancel at any time via a signed `OrderCancellation` submitted to `cancel_order`.

All three actions require valid SNIP-12 signatures. Account nonces are consumed on every write to prevent replay attacks.

---

## Architecture

### Components

| Component | Purpose |
|---|---|
| `NoncesComponent` | Per-account nonce tracking; consumed on register, fulfill, and cancel |
| `AccessControlComponent` | `DEFAULT_ADMIN_ROLE` grants upgrade rights to the manager |
| `UpgradeableComponent` | Contract is upgradeable by the manager |
| `SRC5Component` | ERC-165-style interface introspection |

### SNIP-12 Domain

```
name:    'Medialane1155'
version: 1
```

All off-chain signatures must use this domain to be accepted by the contract.

### Module Layout

```
src/
  lib.cairo               # mod declarations
  core/
    medialane.cairo       # main contract (Medialane1155)
    interface.cairo       # IMedialane1155 trait
    types.cairo           # OrderParameters, OrderDetails, OrderFulfillment, OrderCancellation, ...
    utils.cairo           # SNIP-12 type hashes, felt conversion helpers
    errors.cairo          # error string constants
    events.cairo          # OrderCreated, OrderFulfilled, OrderCancelled
  mocks/
    erc1155.cairo         # MockERC1155 with ERC-2981 support (tests only)
    erc20.cairo           # MockERC20 (tests only)
    account.cairo         # MockAccount / SRC-6 (tests only)
tests/
  tests.cairo             # integration + unit test suite
```

---

## Data Types

### `OrderParameters` — signed by the seller

All fields are `felt252` for Poseidon hashing compatibility.

| Field | Type | Description |
|---|---|---|
| `offerer` | `ContractAddress` | Seller's account address |
| `nft_contract` | `ContractAddress` | ERC-1155 contract holding the tokens |
| `token_id` | `felt252` | Token type ID within the ERC-1155 contract |
| `amount` | `felt252` | Total number of tokens offered for sale |
| `payment_token` | `ContractAddress` | ERC-20 payment token. Zero address = STRK (native) |
| `price_per_unit` | `felt252` | Price per single token, in `payment_token` units |
| `start_time` | `felt252` | Unix timestamp from which the order is fillable |
| `end_time` | `felt252` | Unix timestamp at which the order expires. `0` = no expiry |
| `salt` | `felt252` | Entropy for multiple distinct orders with the same fields |
| `nonce` | `felt252` | Seller's current account nonce (consumed on registration) |

### `OrderDetails` — stored on-chain

Written to storage on `register_order`. `remaining_amount` tracks partial fill progress.

| Field | Type | Description |
|---|---|---|
| `offerer` | `ContractAddress` | Seller address |
| `nft_contract` | `ContractAddress` | ERC-1155 contract |
| `token_id` | `felt252` | Token type ID |
| `amount` | `felt252` | Original listed quantity |
| `payment_token` | `ContractAddress` | Payment ERC-20 (zero = STRK) |
| `price_per_unit` | `felt252` | Price per token |
| `start_time` | `u64` | Active-from timestamp |
| `end_time` | `u64` | Expiry timestamp (0 = no expiry) |
| `order_status` | `OrderStatus` | Current lifecycle state |
| `remaining_amount` | `felt252` | Units still available. Decremented on each partial fill. `0` after full fill. |

### `OrderFulfillment` — signed by the buyer

| Field | Type | Description |
|---|---|---|
| `order_hash` | `felt252` | SNIP-12 hash of the order being purchased |
| `fulfiller` | `ContractAddress` | Buyer's account address |
| `quantity` | `felt252` | Number of units to purchase (1 ≤ quantity ≤ remaining_amount) |
| `nonce` | `felt252` | Buyer's current account nonce (consumed on fulfillment) |

### `OrderCancellation` — signed by the seller

| Field | Type | Description |
|---|---|---|
| `order_hash` | `felt252` | SNIP-12 hash of the order to cancel |
| `offerer` | `ContractAddress` | Seller's account address |
| `nonce` | `felt252` | Seller's current account nonce |

### `OrderStatus` enum

| Variant | Meaning |
|---|---|
| `None` | Never registered |
| `Created` | Active — awaiting fulfillment (including partially filled orders) |
| `Filled` | All units sold (`remaining_amount == 0`) |
| `Cancelled` | Cancelled by the offerer |

---

## Interface

### `register_order(order: Order)`

Registers a fixed-price ERC-1155 sell order. Sets `remaining_amount = amount`.

**Validations:**
1. `offerer` must not be zero.
2. `nft_contract` must not be zero.
3. `amount` must be non-zero.
4. `price_per_unit` must be non-zero.
5. Order hash must not already exist.
6. If `end_time != 0`, order must not already be expired.
7. Seller's SNIP-12 signature must be valid.
8. Seller's nonce must match (then consumed).

**Emits:** `OrderCreated`

---

### `fulfill_order(fulfillment_request: FulfillmentRequest)`

Purchases `quantity` units from a registered order.

**Validations:**
1. Order status must be `Created`.
2. `get_caller_address()` must equal `fulfillment.fulfiller`.
3. `fulfiller` must not equal `offerer`.
4. Buyer's SNIP-12 signature must be valid.
5. `quantity` must be non-zero.
6. `quantity` must be ≤ `remaining_amount`.
7. `start_time` must have passed.
8. If `end_time != 0`, must not have expired.
9. Buyer's nonce must match (then consumed).

**Transfer sequence (CEI):**
1. `remaining_amount` decremented; status set to `Filled` if `remaining_amount == 0`, otherwise stays `Created`.
2. `safe_transfer_from(offerer, fulfiller, token_id, quantity, [])` on the ERC-1155 contract.
3. ERC-2981 royalty queried on `price_per_unit × quantity`.
4. Royalty transferred from buyer to `royalty_receiver` (if non-zero).
5. Remainder transferred from buyer to seller.

**Pre-condition:** buyer must have approved `price_per_unit × quantity` on the payment token.

**Emits:** `OrderFulfilled` (includes `quantity` and `remaining_amount`)

---

### `cancel_order(cancel_request: CancelRequest)`

Cancels a registered order. Only the original offerer can cancel.

**Validations:** order must be `Created`; offerer must match; valid SNIP-12 signature; nonce match.

**Emits:** `OrderCancelled`

---

### `get_order_details(order_hash: felt252) -> OrderDetails`

Returns the stored `OrderDetails`. Returns a zero-valued struct (status `None`) if never registered.

---

### `get_order_hash(parameters: OrderParameters, signer: ContractAddress) -> felt252`

Computes the SNIP-12 message hash. Useful for frontends to derive the hash the seller must sign.

---

### `get_native_token() -> ContractAddress`

Returns the STRK token address configured at deployment.

---

### `nonces(account: ContractAddress) -> felt252`

Returns the current nonce for an account. Must be read before constructing any signed payload.

---

## Events

### `OrderCreated`

| Field | Indexed | Description |
|---|---|---|
| `order_hash` | yes | SNIP-12 hash |
| `offerer` | yes | Seller address |
| `nft_contract` | no | ERC-1155 contract |
| `token_id` | no | Token type ID |
| `amount` | no | Total listed quantity |
| `price_per_unit` | no | Price per token |
| `payment_token` | no | Payment ERC-20 |

### `OrderFulfilled`

| Field | Indexed | Description |
|---|---|---|
| `order_hash` | yes | SNIP-12 hash |
| `offerer` | yes | Seller address |
| `fulfiller` | yes | Buyer address |
| `quantity` | no | Units purchased in this fill |
| `remaining_amount` | no | Units still available after this fill (0 = fully sold) |
| `royalty_receiver` | no | Royalty recipient (zero if none) |
| `royalty_amount` | no | Royalty paid (u256, zero if none) |

### `OrderCancelled`

| Field | Indexed | Description |
|---|---|---|
| `order_hash` | yes | SNIP-12 hash |
| `offerer` | yes | Seller address |

---

## ERC-2981 Royalty Handling

At fulfillment the royalty is computed on `price_per_unit × quantity` (the actual sale value of this fill):

1. `supports_interface(IERC2981_ID)` checked on the NFT contract.
2. If supported, `royalty_info(token_id, price_per_unit × quantity)` called.
3. If `receiver` is non-zero and `royalty_amount > 0`: royalty transferred to receiver, remainder to seller.
4. If ERC-2981 not supported: full amount goes to seller.

`IERC2981_ID`: `0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b`

---

## SNIP-12 Type Hashes

**OrderParameters**
```
"OrderParameters"("offerer":"ContractAddress","nft_contract":"ContractAddress","token_id":"felt","amount":"felt","payment_token":"ContractAddress","price_per_unit":"felt","start_time":"felt","end_time":"felt","salt":"felt","nonce":"felt")
```

**OrderFulfillment** *(quantity added in v2)*
```
"OrderFulfillment"("order_hash":"felt","fulfiller":"ContractAddress","quantity":"felt","nonce":"felt")
```

**OrderCancellation**
```
"OrderCancellation"("order_hash":"felt","offerer":"ContractAddress","nonce":"felt")
```

---

## Off-Chain Integration Guide

### 1. Fetch nonces

```ts
const sellerNonce = await provider.callContract({
  contractAddress: MEDIALANE1155,
  entrypoint: 'nonces',
  calldata: [sellerAddress],
});
```

### 2. Build and sign `OrderParameters` (seller)

```ts
const domain = {
  name: 'Medialane1155',
  version: '1',
  chainId: '0x534e5f4d41494e', // SN_MAIN
  revision: '1',
};

const types = {
  StarknetDomain: [
    { name: 'name', type: 'shortstring' },
    { name: 'version', type: 'shortstring' },
    { name: 'chainId', type: 'shortstring' },
    { name: 'revision', type: 'shortstring' },
  ],
  OrderParameters: [
    { name: 'offerer', type: 'ContractAddress' },
    { name: 'nft_contract', type: 'ContractAddress' },
    { name: 'token_id', type: 'felt' },
    { name: 'amount', type: 'felt' },
    { name: 'payment_token', type: 'ContractAddress' },
    { name: 'price_per_unit', type: 'felt' },
    { name: 'start_time', type: 'felt' },
    { name: 'end_time', type: 'felt' },
    { name: 'salt', type: 'felt' },
    { name: 'nonce', type: 'felt' },
  ],
};

const message = {
  offerer: sellerAddress,
  nft_contract: collectionAddress,
  token_id: '1',
  amount: '100',              // total editions for sale
  payment_token: STRK_ADDRESS,
  price_per_unit: '1000000000000000000', // 1 STRK
  start_time: String(Math.floor(Date.now() / 1000)),
  end_time: '0',
  salt: String(Math.random() * 1e9 | 0),
  nonce: sellerNonce,
};

const signature = await sellerAccount.signMessage({ domain, types, primaryType: 'OrderParameters', message });
```

### 3. Approve ERC-1155 (seller, one-time per collection)

```ts
await sellerAccount.execute({
  contractAddress: collectionAddress,
  entrypoint: 'set_approval_for_all',
  calldata: [MEDIALANE1155, '1'],
});
```

### 4. Register the order

```ts
await sellerAccount.execute({
  contractAddress: MEDIALANE1155,
  entrypoint: 'register_order',
  calldata: CallData.compile({ order: { parameters: message, signature } }),
});
```

### 5. Approve payment token (buyer, per purchase)

```ts
// total = price_per_unit × quantity
const total = BigInt(pricePerUnit) * BigInt(quantity);
await buyerAccount.execute({
  contractAddress: STRK_ADDRESS,
  entrypoint: 'approve',
  calldata: [MEDIALANE1155, total.toString(), '0'], // u256 low, high
});
```

### 6. Sign and submit `OrderFulfillment` (buyer)

```ts
// IMPORTANT: quantity is required in v2 — field order must match type hash exactly
const fulfillmentTypes = {
  StarknetDomain: [ /* same as above */ ],
  OrderFulfillment: [
    { name: 'order_hash', type: 'felt' },
    { name: 'fulfiller', type: 'ContractAddress' },
    { name: 'quantity', type: 'felt' },   // required — between fulfiller and nonce
    { name: 'nonce', type: 'felt' },
  ],
};

const fulfillmentMessage = {
  order_hash: orderHash,
  fulfiller: buyerAddress,
  quantity: '5',        // buy 5 of the 100 available
  nonce: buyerNonce,
};

const sig = await buyerAccount.signMessage({
  domain,
  types: fulfillmentTypes,
  primaryType: 'OrderFulfillment',
  message: fulfillmentMessage,
});

await buyerAccount.execute({
  contractAddress: MEDIALANE1155,
  entrypoint: 'fulfill_order',
  calldata: CallData.compile({ fulfillment_request: { fulfillment: fulfillmentMessage, signature: sig } }),
});
```

---

## Error Reference

| Error string | Condition |
|---|---|
| `'Invalid signature'` | SNIP-12 signature failed `is_valid_signature` |
| `'Order expired'` | `end_time != 0` and `now >= end_time` |
| `'Order not yet valid'` | `now < start_time` at fulfillment |
| `'Order not found'` | No order exists for this hash |
| `'Order already created'` | Order hash already registered |
| `'Order already filled'` | All units sold |
| `'Order cancelled'` | Cancelled by the offerer |
| `'Transfer failed'` | ERC-20 `transfer_from` to seller failed |
| `'Royalty transfer failed'` | ERC-20 `transfer_from` to royalty receiver failed |
| `'Caller not offerer'` | `cancelation.offerer` does not match stored offerer |
| `'Caller not fulfiller'` | `get_caller_address()` does not match `fulfillment.fulfiller` |
| `'Cannot fill own order'` | `fulfiller == offerer` |
| `'Offerer cannot be zero'` | `offerer` is zero address |
| `'NFT contract cannot be zero'` | `nft_contract` is zero address |
| `'Amount must be nonzero'` | `amount == 0` |
| `'Price must be nonzero'` | `price_per_unit == 0` |
| `'Quantity must be nonzero'` | `quantity == 0` in `OrderFulfillment` |
| `'Insufficient remaining units'` | `quantity > remaining_amount` |
| `'Royalty exceeds sale price'` | `royalty_info` returned amount > total price |

---

## Security Properties

**Replay protection** — every write action consumes the signer's account nonce.

**CEI pattern** — `remaining_amount` and `order_status` are updated in storage before any external token transfers. A re-entrant `onERC1155Received` callback cannot re-fill an in-progress order.

**Caller binding** — the fulfiller address is embedded in the signed payload and compared to `get_caller_address()`.

**Self-fulfillment guard** — offerer cannot fill their own order.

**Partial fill safety** — `quantity` is validated as non-zero and ≤ `remaining_amount` before any state changes. Comparison uses `felt252 → u256` conversion since `felt252` has no defined `PartialOrd`.

**SRC5 guard on royalties** — `supports_interface(IERC2981_ID)` checked before calling `royalty_info`.

**Royalty cap** — reverts if `royalty_info` returns an amount exceeding the fill's total price.

---

## Development

```bash
cd contracts/Medialane-Protocol-ERC1155

# Build
scarb build

# Run tests
snforge test

# Format
scarb fmt
```
