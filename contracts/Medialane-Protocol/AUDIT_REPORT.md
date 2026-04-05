# Medialane Protocol — Security Audit Report

**Scope**: `contracts/Medialane-Protocol/`
**Date**: 2026-04-05
**Auditor**: Cairo Auditor (claude-sonnet-4-6)

---

## Summary Table

| ID | Severity | Title | File:Line |
|----|----------|-------|-----------|
| M-01 | High | `register_order` requires `start_time` in the future — breaks immediate-validity orders | `medialane.cairo:310` |
| M-02 | High | Any address can fulfill any order — no fulfiller identity check | `medialane.cairo:179-218` |
| M-03 | High | `cancel_order` does not verify `cancelation.offerer` matches stored order offerer | `medialane.cairo:235-261` |
| M-04 | High | `end_amount` is signed but silently ignored during transfer — price manipulation vector | `medialane.cairo:418-443`, `types.cairo:49,66` |
| M-05 | Medium | Reentrancy: state update occurs after external token transfer calls in `fulfill_order` | `medialane.cairo:200-206` |
| M-06 | Medium | `felt_to_u64` panics on overflow — malformed time felts DoS `register_order` | `utils.cairo:71`, `medialane.cairo:132-133` |
| M-07 | Medium | `item_type` stored as raw `felt252`, not validated at registration — permanently unfulfillable order | `types.cairo:46-51`, `medialane.cairo:119-158` |
| M-08 | Medium | `.try_into().unwrap()` on `item_type` in `_transfer_item` panics instead of clean revert | `medialane.cairo:421,439` |
| M-09 | Medium | No zero-address check on `offerer` in `register_order` | `medialane.cairo:123-127` |
| M-10 | Low | Cancellation nonce is independent of order nonce — ambiguous and unlinked | `medialane.cairo:251`, `types.cairo:129-132` |
| M-11 | Low | `upgrade` has no timelock — admin can atomically replace contract logic | `medialane.cairo:96-101` |
| M-12 | Low | `get_order_details` returns zeroed struct for unknown hashes | `medialane.cairo:271-273` |
| M-13 | Informational | `end_amount` is signed but has no defined on-chain semantics | `medialane.cairo:418-443` |
| M-14 | Informational | `OFFER_ITEM_TYPE_HASH` and `CONSIDERATION_ITEM_TYPE_HASH` are hardcoded hex literals | `utils.cairo:56-60` |
| M-15 | Informational | No protocol fee mechanism | `medialane.cairo:407-444` |

**Totals**: 4 High · 5 Medium · 2 Low · 4 Informational

---

## Findings

---

### [M-01] High — `register_order` enforces `start_time` in the future, breaking immediate-validity orders

**File**: `src/core/medialane.cairo:310`

**Description**: `_validate_future_order` asserts `current_timestamp < start_time`. Any order with `start_time == now` reverts with `ORDER_NOT_YET_VALID`. The complementary `_validate_active_order` at fulfillment asserts `current_timestamp >= start_time`, making registration and fulfillment mutually exclusive for orders that start immediately.

```cairo
// medialane.cairo:310
assert(current_timestamp < start_time, errors::ORDER_NOT_YET_VALID);
```

**Impact**: Sellers cannot create immediately-active listings. Any UI that submits `start_time = now` produces consistent failures.

**Recommendation**: Change the registration check to `current_timestamp <= start_time`, or allow orders whose `start_time` is already in the past (already active) at registration time.

---

### [M-02] High — Any address can fulfill any order; no fulfiller identity enforcement

**File**: `src/core/medialane.cairo:179-218`

**Description**: `fulfill_order` accepts any `FulfillmentRequest` from any caller. There is no check that `get_caller_address() == fulfillment_intent.fulfiller`. The signed fulfillment message is public in the mempool, allowing front-running: an attacker submits the identical calldata first and receives the offered NFT while the consideration transfers to the order's `recipient`.

**Impact**: Front-running attacks on fulfillment transactions. Attacker pays gas and receives the offered asset. No private/allowlisted sales are possible.

**Recommendation**: Add `assert(get_caller_address() == fulfiller, errors::CALLER_NOT_FULFILLER)` inside `fulfill_order`, or include the caller address in the fulfillment hash.

---

### [M-03] High — `cancel_order` does not verify `cancelation.offerer` matches the stored order offerer

**File**: `src/core/medialane.cairo:235-261`

**Description**: The cancellation flow validates a SNIP-12 signature from `cancelation_intent.offerer` but never checks this matches `order_details.offerer` read from storage. Any SRC-6 account holder can cancel a victim's order by signing `OrderCancellation{ order_hash: victim_hash, offerer: attacker_address, nonce: fresh }`.

```cairo
// medialane.cairo:239-245
let offerer = cancelation_intent.offerer;   // user-supplied, never cross-checked
let order_hash = cancelation_intent.order_hash;
self._validate_order_status(order_hash, OrderStatus::Created);
let cancelation_hash = cancelation_intent.get_message_hash(offerer);
self._validate_hash_signature(cancelation_hash, offerer, signature);
```

**Impact**: Any deployed SRC-6 account can cancel any other user's live order at zero cost beyond gas. Legitimate trades can be griefed at will.

**Recommendation**: After reading the order from storage, assert:
```cairo
assert(cancelation_intent.offerer == order_details.offerer, errors::CALLER_NOT_OFFERER);
```

---

### [M-04] High — `end_amount` committed in signed hash but silently ignored during transfer

**File**: `src/core/medialane.cairo:418-443`, `src/core/types.cairo:49,66`

**Description**: Both `OfferItem` and `ConsiderationItem` carry `start_amount` and `end_amount`. Both are included in the SNIP-12 struct hash. However, `_execute_transfers` unconditionally uses `start_amount` only; `end_amount` is passed to `_transfer_item` but never read inside that function. A UI displaying `end_amount` as the price while only `start_amount` (e.g. 1 wei) is transferred deceives the offerer.

**Impact**: Offerers can be misled into signing orders where actual transfer value is a fraction of the displayed price. Silent fund loss.

**Recommendation**: Remove `end_amount` (if fixed-price only) and regenerate type hashes, or implement Dutch-auction interpolation. At minimum, assert `start_amount == end_amount` until auction logic is supported.

---

### [M-05] Medium — Reentrancy: state update occurs after external calls in `fulfill_order`

**File**: `src/core/medialane.cairo:200-206`

**Description**: External token transfers execute before the order status is written to `Filled`:

```cairo
// medialane.cairo:200-206
self._execute_transfers(order_details, fulfiller);   // external calls first

order_details.order_status = OrderStatus::Filled;
self.orders.write(order_hash, order_details);        // state update after
```

ERC-1155 `safe_transfer_from` invokes `onERC1155Received` on the recipient — a fully arbitrary external call — before the order is marked filled. A malicious recipient can re-enter `fulfill_order` while the order is still in `Created` status.

**Impact**: For ERC-1155 orders with a malicious recipient, reentrancy is exploitable. Violates checks-effects-interactions.

**Recommendation**: Move `self.orders.write(order_hash, ...)` to before `_execute_transfers`.

---

### [M-06] Medium — `felt_to_u64` panics on overflow — DoS of `register_order`

**File**: `src/core/utils.cairo:71`, `src/core/medialane.cairo:132-133`

**Description**: `felt_to_u64` calls `.try_into().unwrap()`, which panics if the felt252 value exceeds `u64::MAX`. `start_time` and `end_time` in `OrderParameters` are `felt252` with no upper-bound validation. A malformed timestamp burns the signed nonce permanently — the order can never be registered.

**Impact**: Denial of service: signed orders with oversized timestamps become permanently unregisterable, wasting the offerer's nonce.

**Recommendation**: Replace `.unwrap()` with an explicit bounds check and a clean error, or validate time fields before calling `felt_to_u64`.

---

### [M-07] Medium — `item_type` not validated at registration — permanently unfulfillable orders stored

**File**: `src/core/types.cairo:46-51`, `src/core/medialane.cairo:119-158`

**Description**: `item_type` is stored as raw `felt252` at registration. Validation via `try_into()` occurs only at fulfillment time (`.unwrap()` panic). An order registered with an unknown `item_type` occupies its hash slot and consumes the nonce, but will always panic when any fulfiller attempts to execute it.

**Impact**: An offerer who signs an order with a typo in `item_type` permanently loses that nonce and cannot fulfill the order.

**Recommendation**: Validate `item_type` against the `ItemType` enum during `register_order` and emit `errors::INVALID_ITEM_TYPE` on failure.

---

### [M-08] Medium — `.try_into().unwrap()` panics instead of clean revert in `_transfer_item`

**File**: `src/core/medialane.cairo:421, 439`

**Description**: Related to M-07. The `.unwrap()` calls produce opaque runtime panics rather than the defined application error constant, making the revert reason invisible to callers and difficult to index.

```cairo
offer_item.item_type.try_into().unwrap(),         // line 421
consideration_item.item_type.try_into().unwrap(), // line 439
```

**Recommendation**: Use `.expect(errors::INVALID_ITEM_TYPE)` or match explicitly and assert.

---

### [M-09] Medium — No zero-address check on `offerer` in `register_order`

**File**: `src/core/medialane.cairo:123-127`

**Description**: `register_order` passes `order_parameters.offerer` directly to `ISRC6Dispatcher` without a non-zero guard. A zero-address offerer produces inconsistent behavior (silent failure or panic depending on VM version) and locks that hash slot permanently since no valid signature for address 0 can be constructed.

**Impact**: Edge-case hash-slot poisoning; the offerer loses the ability to re-use that nonce.

**Recommendation**: Add `assert(offerer.is_non_zero(), 'Offerer cannot be zero')` at the top of `register_order`.

---

### [M-10] Low — Cancellation nonce is independent of order nonce

**File**: `src/core/medialane.cairo:251`, `src/core/types.cairo:129-132`

**Description**: `cancel_order` consumes a nonce on the offerer's nonce counter that is entirely separate from the order's registration nonce. Offerers must manage two independent nonce spaces. Consuming a cancellation nonce for value `N` prevents reuse of `N` for a future order.

**Recommendation**: Consider a dedicated cancellation nonce space separate from the order nonce space, or link the cancellation to the original order nonce.

---

### [M-11] Low — `upgrade` has no timelock

**File**: `src/core/medialane.cairo:96-101`

**Description**: A single `DEFAULT_ADMIN_ROLE` holder can atomically replace the contract class hash in one transaction. No proposal step, no delay, no multi-sig requirement.

```cairo
fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
    self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
    self.upgradeable.upgrade(new_class_hash);
}
```

**Impact**: Compromised admin key enables complete contract takeover in a single transaction.

**Recommendation**: Implement a 48-hour timelock between `propose_upgrade` and `execute_upgrade`, or require a multi-signature admin. At minimum, emit an application-level `UpgradeProposed` event.

---

### [M-12] Low — `get_order_details` returns zeroed struct for unknown hashes

**File**: `src/core/medialane.cairo:271-273`

**Description**: Missing `Map` entries return the zero default for `OrderDetails`. An unknown order hash returns a struct with `order_status = OrderStatus::None` and all addresses/amounts as zero — indistinguishable from a legitimately zero-field order at the storage level.

**Impact**: Off-chain indexers may misinterpret missing orders as valid zero-valued ones.

**Recommendation**: Document this behavior explicitly, or return `Option<OrderDetails>` from the interface.

---

### [M-13] Informational — `end_amount` has no defined on-chain semantics

**File**: `src/core/medialane.cairo:418-443`

**Description**: `end_amount` is committed to the SNIP-12 hash but never used in any execution path. The Seaport-style Dutch-auction interpolation it implies is not implemented.

**Recommendation**: Remove `end_amount` and regenerate type hashes, or document it as reserved and enforce `end_amount == start_amount`.

---

### [M-14] Informational — `OFFER_ITEM_TYPE_HASH` and `CONSIDERATION_ITEM_TYPE_HASH` are hardcoded hex literals

**File**: `src/core/utils.cairo:56-60`

**Description**: Other type hashes use `selector!(...)` at compile time. These two are bare hex constants. If the associated struct fields are ever modified, the hashes diverge silently with no compilation warning.

```cairo
pub const OFFER_ITEM_TYPE_HASH: felt252 =
    0x31e7083107691cc7e3645b18aa6fbf556783779ea1620502b1b5f60ec1edf8f;
```

**Recommendation**: Derive these constants via `selector!(...)` matching the same type-string format, and add a unit test asserting the hardcoded value equals the derived one.

---

### [M-15] Informational — No protocol fee mechanism

**File**: `src/core/medialane.cairo:407-444`

**Description**: `_execute_transfers` routes assets directly peer-to-peer with no fee deduction or fee recipient. Adding fees later requires a contract upgrade with associated migration risk.

**Recommendation**: Reserve storage slots for `fee_recipient: ContractAddress` and `fee_bps: u16` now, even if set to zero, to avoid a storage layout change on the first fee-enabling upgrade.

---

*End of report — 4 High · 5 Medium · 2 Low · 4 Informational*
