# Medialane Protocol — ERC-1155

A specialized on-chain marketplace for trading ERC-1155 IP assets on Starknet. Built for the [Mediolano](https://mediolano.app) protocol, it enables creators and collectors to list, buy, and cancel ERC-1155 token listings using off-chain SNIP-12 signatures, with automatic on-chain royalty distribution via ERC-2981.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `Medialane1155` contract | `0x042005e9b85536072bfa260b95aa6aaef07f48e622031657384d2375195d7123` |
| Mainnet | `Medialane1155` class hash | `0x36c4a12e624b2bf756213de98dac72d5e431cee7ee76b2d29a478132d6b2b14` |
| Mainnet | Manager (DEFAULT_ADMIN_ROLE) | `0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b` |
| Mainnet | Native token (STRK) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |

This contract is the ERC-1155 companion to `Medialane-Protocol` (which handles ERC-721 assets). It is designed to work with IP collections deployed via `IP-Programmable-ERC1155-Collections` (factory: `0x0459a9a3c04be5d884a038744f977dff019897264d4a281f9e0f87af417b3bec`).

---

## Overview

The contract implements a simple fixed-price order book:

1. A seller (offerer) signs an `OrderParameters` struct off-chain using SNIP-12 typed data.
2. The signed order is submitted on-chain via `register_order` — the order is stored and the offerer's nonce is consumed.
3. A buyer (fulfiller) signs an `OrderFulfillment` struct off-chain and submits it via `fulfill_order`.
4. On fulfillment the contract atomically:
   - Transfers ERC-1155 tokens from seller to buyer (`safe_transfer_from`).
   - Queries the NFT contract for ERC-2981 royalty info and pays the royalty receiver.
   - Transfers the remaining sale proceeds to the seller.
5. Either party can cancel (seller only) by signing an `OrderCancellation` and calling `cancel_order`.

All three actions require valid SNIP-12 signatures. Account nonces are consumed on every write operation to prevent replay attacks.

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

The struct the seller signs off-chain. All fields are `felt252` for Poseidon hashing compatibility.

| Field | Type | Description |
|---|---|---|
| `offerer` | `ContractAddress` | Seller's account address |
| `nft_contract` | `ContractAddress` | ERC-1155 contract holding the tokens |
| `token_id` | `felt252` | Token type ID within the ERC-1155 contract |
| `amount` | `felt252` | Number of tokens offered for sale |
| `payment_token` | `ContractAddress` | ERC-20 payment token. Zero address = STRK (native) |
| `price_per_unit` | `felt252` | Price per single token, denominated in `payment_token` |
| `start_time` | `felt252` | Unix timestamp from which the order becomes fillable (inclusive) |
| `end_time` | `felt252` | Unix timestamp at which the order expires (exclusive). `0` = no expiry |
| `salt` | `felt252` | Entropy to allow multiple distinct orders with the same other fields |
| `nonce` | `felt252` | Seller's current account nonce (consumed on registration) |

**Total price paid by the buyer** = `price_per_unit × amount`.

### `OrderDetails` — stored on-chain

Written to contract storage when an order is registered. Fields mirror `OrderParameters` but `start_time`/`end_time` are stored as `u64` and `fulfiller` is an `Option`.

| Field | Type | Description |
|---|---|---|
| `offerer` | `ContractAddress` | Seller address |
| `nft_contract` | `ContractAddress` | ERC-1155 contract |
| `token_id` | `felt252` | Token type ID |
| `amount` | `felt252` | Number of tokens |
| `payment_token` | `ContractAddress` | Payment ERC-20 (zero = STRK) |
| `price_per_unit` | `felt252` | Price per token |
| `start_time` | `u64` | Active-from timestamp |
| `end_time` | `u64` | Expiry timestamp (0 = no expiry) |
| `order_status` | `OrderStatus` | Current lifecycle state |
| `fulfiller` | `Option<ContractAddress>` | Set to buyer address after fulfillment |

### `OrderFulfillment` — signed by the buyer

| Field | Type | Description |
|---|---|---|
| `order_hash` | `felt252` | SNIP-12 hash of the order being purchased |
| `fulfiller` | `ContractAddress` | Buyer's account address (must equal `get_caller_address()`) |
| `nonce` | `felt252` | Buyer's current account nonce (consumed on fulfillment) |

### `OrderCancellation` — signed by the seller to cancel

| Field | Type | Description |
|---|---|---|
| `order_hash` | `felt252` | SNIP-12 hash of the order to cancel |
| `offerer` | `ContractAddress` | Seller's account address (must match the stored order) |
| `nonce` | `felt252` | Seller's current account nonce (consumed on cancellation) |

### `OrderStatus` enum

| Variant | Meaning |
|---|---|
| `None` | Order hash never registered (default zero value) |
| `Created` | Registered and awaiting fulfillment |
| `Filled` | Matched and executed |
| `Cancelled` | Cancelled by the offerer |

---

## Interface

### `register_order(order: Order)`

Registers a new fixed-price ERC-1155 sell order.

**Validations (in order):**
1. `offerer` must not be the zero address.
2. `nft_contract` must not be the zero address.
3. `amount` must be non-zero.
4. `price_per_unit` must be non-zero.
5. Order hash must not already exist (`OrderStatus::None`).
6. If `end_time != 0`, current timestamp must be less than `end_time` (order not already expired).
7. Seller's SNIP-12 signature must be valid (`is_valid_signature` on the offerer's SRC-6 account).
8. Seller's nonce must match `params.nonce` (then consumed).

**Effects:**
- Writes `OrderDetails` to storage with status `Created`.
- Emits `OrderCreated`.

**Pre-condition for the buyer:** the seller must call `setApprovalForAll(medialane1155_address, true)` on the ERC-1155 contract before `fulfill_order` is called.

---

### `fulfill_order(fulfillment_request: FulfillmentRequest)`

Purchases a registered order.

**Validations (in order):**
1. Order must have status `Created`.
2. `get_caller_address()` must equal `fulfillment.fulfiller` (prevents tx replay by a third party).
3. `fulfiller` must not equal `offerer` (self-fulfillment is rejected).
4. Buyer's SNIP-12 signature must be valid.
5. Current timestamp must be `>= start_time` (order window has opened).
6. If `end_time != 0`, current timestamp must be `< end_time`.
7. Buyer's nonce must match `fulfillment.nonce` (then consumed).

**Transfer sequence (CEI — state committed before external calls):**
1. Status set to `Filled` and fulfiller recorded in storage.
2. `safe_transfer_from(offerer, fulfiller, token_id, amount, [])` on the ERC-1155 contract.
3. ERC-2981 royalty queried via SRC5 interface check + `royalty_info(token_id, total_price)`.
4. Royalty amount transferred from buyer to `royalty_receiver` (if non-zero).
5. Remainder `(total_price - royalty_amount)` transferred from buyer to seller.

**Pre-condition for the buyer:** must have called `approve(medialane1155_address, total_price)` (or `increaseAllowance`) on the payment ERC-20 contract before calling this function.

**Emits:** `OrderFulfilled` with royalty details.

---

### `cancel_order(cancel_request: CancelRequest)`

Cancels a registered order. Only the original offerer can cancel.

**Validations:**
1. Order must have status `Created`.
2. `cancelation.offerer` must match the stored `order.offerer`.
3. Seller's SNIP-12 signature on the cancellation must be valid.
4. Seller's nonce must match `cancelation.nonce` (then consumed).

**Effects:**
- Sets order status to `Cancelled`.
- Emits `OrderCancelled`.

No token transfers occur on cancellation. The ERC-1155 approval granted by the seller is not revoked automatically — the seller should revoke it separately if desired.

---

### `get_order_details(order_hash: felt252) -> OrderDetails`

Returns the stored `OrderDetails` for a given order hash. Returns a zero-valued struct (status `None`) if the hash was never registered.

---

### `get_order_hash(parameters: OrderParameters, signer: ContractAddress) -> felt252`

Computes the SNIP-12 message hash for a set of order parameters and a signer address. Useful for frontends and off-chain tooling to derive the hash that the seller must sign, and to verify it matches what the contract will compute on-chain.

---

### `get_native_token() -> ContractAddress`

Returns the STRK token address configured at deployment. This is the payment token used when `payment_token` in an order is the zero address.

---

### `upgrade(new_class_hash: ClassHash)`

Replaces the contract implementation. Restricted to accounts holding `DEFAULT_ADMIN_ROLE`. Emits an `Upgraded` event from `UpgradeableComponent`.

---

### `nonces(account: ContractAddress) -> felt252`

Returns the current nonce for an account. Exposed by `NoncesComponent`. Must be read before constructing any signed payload (`OrderParameters`, `OrderFulfillment`, `OrderCancellation`).

---

## Events

### `OrderCreated`

| Field | Indexed | Description |
|---|---|---|
| `order_hash` | yes | SNIP-12 hash of the order |
| `offerer` | yes | Seller address |
| `nft_contract` | no | ERC-1155 contract address |
| `token_id` | no | Token type ID |
| `amount` | no | Number of tokens listed |
| `price_per_unit` | no | Price per token |
| `payment_token` | no | Payment ERC-20 (zero = STRK) |

### `OrderFulfilled`

| Field | Indexed | Description |
|---|---|---|
| `order_hash` | yes | SNIP-12 hash of the order |
| `offerer` | yes | Seller address |
| `fulfiller` | yes | Buyer address |
| `royalty_receiver` | no | Recipient of the royalty payment (zero if none) |
| `royalty_amount` | no | Royalty paid in payment token units (zero if none) |

### `OrderCancelled`

| Field | Indexed | Description |
|---|---|---|
| `order_hash` | yes | SNIP-12 hash of the order |
| `offerer` | yes | Seller address |

---

## ERC-2981 Royalty Handling

At fulfillment the contract automatically checks whether the ERC-1155 collection supports ERC-2981:

1. Calls `supports_interface(IERC2981_ID)` on the NFT contract via SRC5.
2. If supported, calls `royalty_info(token_id, total_price)` to get `(receiver, royalty_amount)`.
3. If `receiver` is non-zero and `royalty_amount > 0`:
   - Asserts `royalty_amount <= total_price` (safety check).
   - Transfers `royalty_amount` from buyer to `receiver`.
   - Transfers `total_price - royalty_amount` from buyer to seller.
4. If ERC-2981 is not supported, the full `total_price` goes to the seller.

`IERC2981_ID`: `0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b`

IP collections deployed via `IP-Programmable-ERC1155-Collections` implement ERC-2981. The factory allows each collection to configure its royalty receiver and rate at deploy time.

---

## SNIP-12 Type Hashes

The type strings used to compute the Poseidon-based typed data hashes:

**OrderParameters**
```
"OrderParameters"("offerer":"ContractAddress","nft_contract":"ContractAddress","token_id":"felt","amount":"felt","payment_token":"ContractAddress","price_per_unit":"felt","start_time":"felt","end_time":"felt","salt":"felt","nonce":"felt")
```

**OrderFulfillment**
```
"OrderFulfillment"("order_hash":"felt","fulfiller":"ContractAddress","nonce":"felt")
```

**OrderCancellation**
```
"OrderCancellation"("order_hash":"felt","offerer":"ContractAddress","nonce":"felt")
```

All three are hashed using Poseidon over their type string via the `selector!()` macro, which computes the Starknet Keccak of the string.

---

## Off-Chain Integration Guide

### 1. Fetch the seller's nonce

```ts
const nonce = await provider.callContract({
  contractAddress: MEDIALANE1155,
  entrypoint: 'nonces',
  calldata: [sellerAddress],
});
```

### 2. Build and sign `OrderParameters` (seller)

```ts
import { typedData, hash } from 'starknet';

const domain = {
  name: 'Medialane1155',
  version: '1',
  chainId: '0x534e5f4d41494e', // SN_MAIN
  revision: '1',
};

const types = {
  StarknetDomain: [
    { name: 'name',     type: 'shortstring' },
    { name: 'version',  type: 'shortstring' },
    { name: 'chainId',  type: 'shortstring' },
    { name: 'revision', type: 'shortstring' },
  ],
  OrderParameters: [
    { name: 'offerer',        type: 'ContractAddress' },
    { name: 'nft_contract',   type: 'ContractAddress' },
    { name: 'token_id',       type: 'felt' },
    { name: 'amount',         type: 'felt' },
    { name: 'payment_token',  type: 'ContractAddress' },
    { name: 'price_per_unit', type: 'felt' },
    { name: 'start_time',     type: 'felt' },
    { name: 'end_time',       type: 'felt' },
    { name: 'salt',           type: 'felt' },
    { name: 'nonce',          type: 'felt' },
  ],
};

const message = {
  offerer:        sellerAddress,
  nft_contract:   collectionAddress,
  token_id:       '1',
  amount:         '10',
  payment_token:  '0x0', // 0x0 = STRK
  price_per_unit: '1000000000000000000', // 1 STRK (18 decimals)
  start_time:     String(Math.floor(Date.now() / 1000)),
  end_time:       '0', // no expiry
  salt:           String(Date.now()),
  nonce:          sellerNonce,
};

const msgHash = typedData.getMessageHash({ domain, types, primaryType: 'OrderParameters', message });
const signature = await sellerAccount.signMessage({ domain, types, primaryType: 'OrderParameters', message });
```

### 3. Approve the ERC-1155 (seller, one-time per collection)

```ts
await sellerAccount.execute({
  contractAddress: collectionAddress,
  entrypoint: 'set_approval_for_all',
  calldata: [MEDIALANE1155, '1'],
});
```

### 4. Register the order (seller submits signed order on-chain)

```ts
await sellerAccount.execute({
  contractAddress: MEDIALANE1155,
  entrypoint: 'register_order',
  calldata: CallData.compile({
    order: {
      parameters: message,
      signature: signature,
    },
  }),
});
```

### 5. Approve the payment token (buyer)

```ts
// total_price = price_per_unit * amount
await buyerAccount.execute({
  contractAddress: paymentTokenAddress, // STRK address if payment_token is 0
  entrypoint: 'approve',
  calldata: [MEDIALANE1155, totalPrice, '0'], // u256 low, high
});
```

### 6. Sign and submit `OrderFulfillment` (buyer)

```ts
const fulfillmentTypes = {
  StarknetDomain: [ /* same as above */ ],
  OrderFulfillment: [
    { name: 'order_hash', type: 'felt' },
    { name: 'fulfiller',  type: 'ContractAddress' },
    { name: 'nonce',      type: 'felt' },
  ],
};

const fulfillmentMessage = {
  order_hash: orderHash,
  fulfiller:  buyerAddress,
  nonce:      buyerNonce,
};

const fulfillmentSig = await buyerAccount.signMessage({
  domain,
  types: fulfillmentTypes,
  primaryType: 'OrderFulfillment',
  message: fulfillmentMessage,
});

await buyerAccount.execute({
  contractAddress: MEDIALANE1155,
  entrypoint: 'fulfill_order',
  calldata: CallData.compile({
    fulfillment_request: {
      fulfillment: fulfillmentMessage,
      signature: fulfillmentSig,
    },
  }),
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
| `'Order already filled'` | Order has already been fulfilled |
| `'Order cancelled'` | Order was cancelled by the offerer |
| `'Transfer failed'` | ERC-20 `transfer_from` to seller returned false |
| `'Royalty transfer failed'` | ERC-20 `transfer_from` to royalty receiver returned false |
| `'Caller not offerer'` | `cancelation.offerer` does not match the stored order offerer |
| `'Caller not fulfiller'` | `get_caller_address()` does not match `fulfillment.fulfiller` |
| `'Cannot fill own order'` | `fulfiller == offerer` |
| `'Offerer cannot be zero'` | `offerer` field is the zero address |
| `'NFT contract cannot be zero'` | `nft_contract` field is the zero address |
| `'Amount must be nonzero'` | `amount == 0` |
| `'Price must be nonzero'` | `price_per_unit == 0` |
| `'Royalty exceeds sale price'` | `royalty_info` returned an amount greater than `total_price` |

---

## Security Properties

**Replay protection** — every write action (register, fulfill, cancel) consumes the signer's account nonce. A replayed signature will fail with `INVALID_SIGNATURE` or a nonce mismatch.

**CEI pattern** — in `fulfill_order`, the order status is set to `Filled` and written to storage before any external token calls. A re-entrant `onERC1155Received` callback cannot re-enter `fulfill_order` on the same order hash because its status is already `Filled`.

**Caller binding** — the fulfiller address is embedded in the signed payload and compared to `get_caller_address()`. A third party cannot relay a buyer's signed fulfillment to purchase on their behalf.

**Self-fulfillment guard** — an offerer cannot fill their own order (`fulfiller != offerer`).

**SRC5 guard on royalties** — the contract checks `supports_interface(IERC2981_ID)` before calling `royalty_info`, preventing panics on ERC-1155 contracts that do not implement the royalty standard.

**Royalty cap** — if `royalty_info` returns an amount exceeding the total sale price, the transaction reverts with `'Royalty exceeds sale price'`.

---

## Development

```bash
cd contracts/Medialane-Protocol-ERC1155

# Build
scarb build

# Run tests (requires Scarb 2.11.4 + snforge 0.48.1)
PATH="/path/to/scarb-2.11.4/bin:$PATH" snforge test

# Run a single test
snforge test test_mock_erc1155_royalty_five_percent

# Format
scarb fmt
```

### Test Coverage

| Category | Tests | Status |
|---|---|---|
| Input validation (zero offerer, amount, price, contract) | 4 | passing |
| Order timing (expired end_time at registration) | 2 | passing |
| Status checks (unknown order, non-existent fulfill/cancel) | 3 | passing |
| Hash determinism (same params → same hash, different → different) | 3 | passing |
| ERC-2981 mock (0%, 5%, 8% royalty) | 3 | passing |
| Native token query | 1 | passing |
| Integration (requires valid StarknetJS signature) | 4 | ignored |

The 4 ignored tests cover the full happy path (register → fulfill, duplicate register, wrong caller, double fill). They require pre-computed SNIP-12 signatures from StarknetJS against the `Medialane1155` domain before they can be enabled.
