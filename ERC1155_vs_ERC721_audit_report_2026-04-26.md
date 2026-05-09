# Medialane ERC1155 vs ERC721 Audit Report

Date: 2026-04-26

Scope:
- `contracts/Medialane-Protocol-ERC721`
- `contracts/Medialane-Protocol-ERC1155`

Method:
- Source diff of contract, types, interface, events, README, and test suites
- Manual feature-parity review
- Local build/test attempt

## Executive Summary

`Medialane-Protocol-ERC1155` is not a parity implementation of `Medialane-Protocol-ERC721`. It is a narrower marketplace with a different order model:

- ERC721 is a generic fixed-price matcher for `NATIVE`, `ERC20`, `ERC721`, and `ERC1155` items on both sides of the trade.
- ERC1155 is a specialized sell-order contract for `ERC1155 -> STRK/ERC20`, with partial fills and ERC-2981 royalty splitting.

That narrower design is reasonable if intentional, but it means ERC1155 does not currently provide "the same features" as ERC721. The largest missing capabilities are:

- no generic offer/consideration model
- no configurable payment recipient
- no storage-level representation of the richer ERC721 order semantics
- no ABI/domain compatibility with the ERC721 integration surface

The ERC1155 contract also has meaningfully lighter test coverage around signature failures, time-window enforcement, event payloads, and edge cases.

## Findings

### 1. High: ERC1155 drops ERC721's generic order model, so major marketplace features are missing

ERC721 stores full `offer` and `consideration` items, each with `item_type`, `token`, `identifier_or_criteria`, and amount fields, allowing the protocol to trade multiple asset classes through one generic transfer path. See:

- `contracts/Medialane-Protocol-ERC721/src/core/types.cairo:44`
- `contracts/Medialane-Protocol-ERC721/src/core/types.cairo:60`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:265`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:301`

By contrast, ERC1155 replaces those structs with a fixed schema:

- seller
- `nft_contract`
- `token_id`
- `amount`
- `payment_token`
- `price_per_unit`

See:

- `contracts/Medialane-Protocol-ERC1155/src/core/types.cairo:13`
- `contracts/Medialane-Protocol-ERC1155/src/core/types.cairo:58`
- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:109`
- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:327`

Impact:

- ERC1155 cannot support ERC721's generic "any supported item type on either side" feature set.
- ERC1155 cannot support ERC721-for-ERC20, ERC1155-for-ERC1155, ERC20-for-ERC1155, or future asset-pair expansion without another schema rewrite.
- Shared frontend/orderbook logic cannot treat both protocols as the same product surface.

If the product goal is true parity, ERC1155 needs a richer order schema closer to ERC721's `OfferItem` and `ConsiderationItem`, then layer partial-fill logic on top.

### 2. High: ERC1155 removes configurable consideration recipients

ERC721 lets the signed order specify `consideration.recipient`, and fulfillment transfers payment to that address:

- `contracts/Medialane-Protocol-ERC721/src/core/types.cairo:61`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:284`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:290`

ERC1155 always routes the non-royalty proceeds to `offerer`:

- `contracts/Medialane-Protocol-ERC1155/src/core/types.cairo:60`
- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:353`

Impact:

- no treasury recipient
- no delegated payout recipient
- no custodial or split-settlement recipient pattern
- no feature-equivalent replacement for ERC721's signed payment destination

Royalties do not replace this capability. They add a second payout leg, but they do not let the seller choose a destination for primary sale proceeds.

### 3. Medium: registration semantics are different, so order lifecycle parity is not preserved

ERC721 rejects registration when `start_time` is already in the past:

- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:207`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:210`

ERC1155 intentionally allows registration after `start_time`, as long as the order is not expired and `start_time < end_time` when `end_time != 0`:

- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:262`
- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:267`
- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:270`

Impact:

- Same signed order can be acceptable in ERC1155 and rejected in ERC721.
- Shared backend/frontend assumptions about when an order may be registered are not portable.
- "Same features" at the UX and API layer is not currently true even before considering asset-type support.

This may be an intentional improvement, but it is still a parity gap that should be either normalized or documented as a deliberate divergence.

### 4. Medium: ERC1155 changed the signing domain and interface surface, preventing drop-in integration reuse

ERC721 uses:

- contract/interface name `Medialane` / `IMedialane`
- SNIP-12 domain name `'Medialane'`
- getter `get_native_token_address`

References:

- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:46`
- `contracts/Medialane-Protocol-ERC721/src/core/interface.cairo:5`
- `contracts/Medialane-Protocol-ERC721/src/core/interface.cairo:11`

ERC1155 uses:

- contract/interface name `Medialane1155` / `IMedialane1155`
- SNIP-12 domain name `'Medialane1155'`
- getter `get_native_token`

References:

- `contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo:84`
- `contracts/Medialane-Protocol-ERC1155/src/core/interface.cairo:5`
- `contracts/Medialane-Protocol-ERC1155/src/core/interface.cairo:20`

Impact:

- shared typed-data signing code cannot be reused as-is
- shared ABI client generation cannot be reused as-is
- shared indexer/client code must branch on method names and type definitions

This is not a vulnerability, but it is a real implementation cost if the goal is a uniform protocol surface.

### 5. Medium: ERC1155 has materially weaker test coverage than ERC721 for core security and parity behaviors

ERC721 covers:

- valid register/fill/cancel
- invalid registration signature
- invalid fulfillment signature
- expired fulfillment
- not-yet-valid fulfillment
- double-fill prevention
- cancel-after-fill prevention

See:

- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:271`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:337`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:452`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:519`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:551`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:617`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:683`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:749`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:828`

ERC1155 adds good coverage for partial fills and royalties, but it does not currently test several important paths:

- invalid signature on `register_order`
- invalid signature on `fulfill_order`
- invalid signature on `cancel_order`
- fill before `start_time`
- fill after `end_time`
- self-fill rejection (`Cannot fill own order`)
- overfill rejection (`Insufficient remaining units`)
- event payload assertions for `quantity`, `remaining_amount`, and royalty fields
- zero-address payment token path as STRK/native alias

ERC1155 test references:

- `contracts/Medialane-Protocol-ERC1155/tests/tests.cairo:334`
- `contracts/Medialane-Protocol-ERC1155/tests/tests.cairo:434`
- `contracts/Medialane-Protocol-ERC1155/tests/tests.cairo:565`
- `contracts/Medialane-Protocol-ERC1155/tests/tests.cairo:610`
- `contracts/Medialane-Protocol-ERC1155/tests/tests.cairo:650`
- `contracts/Medialane-Protocol-ERC1155/tests/tests.cairo:702`

Impact:

- parity regressions can slip in unnoticed
- signature and time-window behavior is less confidently locked down
- indexer-facing event guarantees are not currently asserted

## Feature Parity Matrix

| Capability | ERC721 | ERC1155 | Notes |
|---|---|---|---|
| Off-chain signed order registration | Yes | Yes | Both use SNIP-12 |
| Off-chain signed fulfillment | Yes | Yes | ERC1155 adds `quantity` |
| Off-chain signed cancellation | Yes | Yes | Present in both |
| Replay protection with nonces | Yes | Yes | Present in both |
| CEI before transfers | Yes | Yes | Present in both |
| Generic asset-type support | Yes | No | ERC721 supports `NATIVE`, `ERC20`, `ERC721`, `ERC1155`; ERC1155 is specialized |
| Configurable payment recipient | Yes | No | ERC1155 always pays `offerer` after royalties |
| Partial fills | No | Yes | ERC1155 improvement |
| ERC-2981 royalties | No | Yes | ERC1155 improvement |
| Storage of final fulfiller | Yes | No | ERC1155 emits fills but does not store a buyer field |
| Same SNIP-12 domain name | Yes | No | `'Medialane'` vs `'Medialane1155'` |
| Same ABI method names | No | No | `get_native_token_address` vs `get_native_token` |
| Event payload richness | Basic | Richer | ERC1155 emits more detail |
| Time-window registration behavior | Future-only | Past allowed if not expired | Behavioral divergence |

## Recommendation

If the goal is strict feature parity, the safest route is:

1. Keep ERC1155 partial-fill and royalty logic.
2. Reintroduce ERC721's generic `OfferItem` and `ConsiderationItem` model.
3. Add an explicit recipient field for primary sale proceeds.
4. Decide whether time-window registration should match ERC721 or the newer ERC1155 behavior, then align both.
5. Normalize the external interface where practical, or formally accept that the two protocols are intentionally different products.
6. Expand ERC1155 tests to cover signature failures, time-window failures, self-fill rejection, overfill rejection, and event assertions.

If the goal is only functional equivalence for "ERC1155 sell order for ERC20/STRK" use cases, then the contract is directionally sound, but the repo and docs should stop describing it as having the same feature set as ERC721.

## Verification Notes

I attempted local compile/test verification, but the environment blocked normal Cairo tooling:

- `snforge test` reported that Scarb was unavailable even when `scarb --version` worked in-shell.
- direct `scarb build` attempts were blocked by sandbox/cache issues and then by a Scarb resolver panic in this environment.

So the report is based on source review and test-suite inspection rather than a successful local build.
