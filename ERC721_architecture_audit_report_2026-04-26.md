# Medialane ERC721 Architecture Audit Report

Date: 2026-04-26

Scope:
- `contracts/Medialane-Protocol-ERC721`

Purpose:
- Audit ERC721 as the source architecture for ERC1155 v2
- Identify security issues, design constraints, and refactor opportunities
- Separate "keep this as the baseline" from "improve this before ERC1155 inherits it"

## Executive Summary

`Medialane-Protocol-ERC721` is a strong baseline for the marketplace architecture. The best parts to preserve are:

- generic `ItemType` / `OfferItem` / `ConsiderationItem` vocabulary
- SNIP-12 signed orders, fulfillments, and cancellations
- nonce-based replay protection
- caller-bound fulfillment to reduce mempool replay/front-running
- offerer-bound cancellation
- CEI state update before token transfers
- immutable deployment model

However, ERC721 should not be copied directly into ERC1155 v2 without tightening a few things. The most important improvements are:

- reject permanently unfulfillable time windows at registration
- validate token addresses and consideration recipient at registration
- formalize allowed trade shapes instead of accepting any item pair
- standardize errors through `errors.cairo`
- expand tests beyond the single ERC721-for-ERC20 happy path
- refresh TypeScript signing helpers so they are a reliable protocol reference

## Findings

### 1. High: Invalid time windows can register permanently unfulfillable orders

`register_order` validates that `now <= start_time` and, when `end_time != 0`, that `now < end_time`.

References:
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:95`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:97`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:207`

It does not validate `start_time < end_time` when `end_time != 0`.

Impact:
- An order with `start_time > end_time` can be registered if both timestamps are still in the future.
- The order can never be fulfilled because fulfillment requires `now >= start_time` and `now < end_time`.
- The offerer must spend another signed cancellation to clean it up.

Recommendation:
- Add registration validation:
  - if `end_time != 0`, require `start_time < end_time`
- For future shared architecture, prefer the cleaner rule:
  - register anytime before expiry
  - fulfill only inside active window

This is one of the ERC721 behaviors ERC1155 v2 should improve rather than copy.

### 2. Medium: Token address and recipient validation happens too late

`register_order` validates item type and fixed-price amounts, but token zero-address checks and `consideration.recipient` checks happen in `_transfer_item` / `_execute_transfers` during fulfillment.

References:
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:70`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:78`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:284`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:320`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:326`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:332`

Impact:
- Invalid orders can be registered and indexed as `Created`.
- Buyers can waste time or gas attempting unfulfillable orders.
- The README states token contracts and recipient are zero-address checked as a security property, but that is not true at registration time.

Recommendation:
- Add a registration-time `_validate_item` helper.
- Validate:
  - non-zero token for `ERC20`, `ERC721`, and `ERC1155`
  - zero or ignored token rules for `NATIVE`
  - non-zero consideration recipient
  - amount constraints per item type

ERC1155 v2 should do this from the start.

### 3. Medium: Generic item model is powerful, but trade-shape policy is undefined

The contract supports four item types for both `offer` and `consideration`:

References:
- `contracts/Medialane-Protocol-ERC721/src/core/types.cairo:8`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:265`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:301`

That gives Medialane a Seaport-like vocabulary, but there is no explicit policy for which pairs are intended:

- ERC721 for ERC20 listing
- ERC20 for ERC721 bid
- ERC721 for ERC721 swap
- ERC1155 for ERC20
- ERC20 for ERC1155
- ERC20 for ERC20
- NATIVE for NATIVE

Impact:
- The architecture looks generic, but the product surface is not formally defined.
- Backend/indexer/frontend teams may assume different supported pairs.
- ERC1155 v2 could inherit a flexible model without a clear marketplace policy.

Recommendation:
- Define `TradeShape` in docs/tests, even if not on-chain.
- Decide whether on-chain validation should restrict impossible or unsupported pairs.
- At minimum, add tests for every supported pair and reject-list tests for unsupported pairs.

For ERC1155 v2, keep the generic model, but explicitly declare the first supported shapes.

### 4. Medium: Single `ConsiderationItem` limits monetization architecture

The current order model has one consideration leg:

References:
- `contracts/Medialane-Protocol-ERC721/src/core/types.cairo:60`
- `contracts/Medialane-Protocol-ERC721/src/core/types.cairo:88`

This is fine for the current fixed-price marketplace, but Seaport's monetization strength comes from multiple consideration recipients.

Impact:
- Protocol fees, creator splits, affiliate rewards, and fan rebates cannot be expressed directly in the signed order.
- ERC1155 royalties can be added as an overlay, but that does not solve richer payout composition.

Recommendation:
- Do not add multi-consideration in the first ERC1155 v2 pass unless the release scope expands.
- Do structure settlement so multi-consideration can become `OrderParametersV3` later.
- Document single-consideration as a deliberate v1/v2 limitation.

This is a strategic constraint, not an immediate bug.

### 5. Medium: Errors are defined but not used consistently

`errors.cairo` defines a useful error vocabulary, but the main contract mostly uses inline string literals.

References:
- `contracts/Medialane-Protocol-ERC721/src/core/errors.cairo:1`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:68`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:70`
- `contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo:132`

Impact:
- Tests are tied to repeated literal strings.
- ERC721 and ERC1155 can drift in revert reasons.
- Shared architecture is harder to audit and document.

Recommendation:
- Refactor ERC721 and ERC1155 v2 to use named error constants.
- Keep messages stable because frontend/indexer/tooling may rely on them.

This is a good low-risk refactor before or alongside ERC1155 v2.

### 6. Medium: Tests validate only a narrow slice of the advertised architecture

Current tests cover core ERC721-for-ERC20 listing behavior well, including invalid signatures and time-window fulfillment.

References:
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:271`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:337`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:452`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:521`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:553`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:619`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:685`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:751`
- `contracts/Medialane-Protocol-ERC721/tests/tests.cairo:830`

Missing or undercovered:

- invalid time-window registration (`start_time >= end_time`)
- zero token address registration
- zero consideration recipient registration
- ERC20-for-ERC721 bid flow
- ERC721-for-ERC721 swap flow, if supported
- ERC1155 item flow, if advertised as supported
- `NATIVE` item flow
- wrong-caller fulfillment
- wrong-offerer cancellation
- duplicate registration
- cancellation after cancellation
- event payloads for all flows

Impact:
- The code advertises a broader generic protocol than the tests prove.
- ERC1155 v2 could inherit untested assumptions.

Recommendation:
- Create a shared marketplace behavior test matrix.
- Use the ERC721 test matrix as the required baseline for ERC1155 v2.

### 7. Low: Event payloads are minimal for indexer-rich marketplace features

Events only include identity fields:

References:
- `contracts/Medialane-Protocol-ERC721/src/core/events.cairo:3`
- `contracts/Medialane-Protocol-ERC721/src/core/events.cairo:11`
- `contracts/Medialane-Protocol-ERC721/src/core/events.cairo:21`

Impact:
- Indexers need to reconstruct most order details from calldata or storage reads.
- Future monetization analytics may want settlement fields directly in events.

Recommendation:
- Preserve current identity fields for compatibility.
- For future versions, add non-indexed settlement detail fields where they reduce indexer fragility.
- For ERC1155 v2, include `quantity`, `remaining_amount`, `sale_amount`, `royalty_receiver`, and `royalty_amount`.

### 8. Low: TypeScript helper trade names appear inverted and should not be used as-is for v2

In `handleOrderParameters`, `TradeType.ERC20_FOR_ERC721` selects an ERC721 offer and ERC20 consideration, while `TradeType.ERC721_FOR_ERC20` selects an ERC20 offer and ERC721 consideration.

References:
- `contracts/Medialane-Protocol-ERC721/scripts/types.ts:42`
- `contracts/Medialane-Protocol-ERC721/scripts/utils.ts:369`
- `contracts/Medialane-Protocol-ERC721/scripts/utils.ts:374`

Impact:
- The signing helper is confusing as a protocol reference.
- Future ERC1155 scripts may copy the same naming drift.
- Test signature regeneration becomes easier to misuse.

Recommendation:
- Rename trade types from the offerer's perspective, or define them explicitly as maker/taker flows.
- Add generated signature fixtures with comments that explain the offer and consideration sides.

## Architecture Recommendations for ERC1155 v2

Use ERC721 as the conceptual baseline, but make these improvements before inheritance:

1. Keep the generic item vocabulary.
2. Add registration-time item validation.
3. Add `start_time < end_time` validation when expiry is set.
4. Prefer the newer time model: register before expiry, fulfill inside active window.
5. Preserve `consideration.recipient` as first-class settlement data.
6. Use named error constants.
7. Define supported trade shapes in docs and tests.
8. Keep one consideration leg for v2, but structure settlement for future multi-recipient support.
9. Treat ERC1155 partial fills and royalties as settlement extensions, not a new order architecture.

## Refactor Priority

### Before ERC1155 v2 implementation

- Define shared marketplace vocabulary and validation rules.
- Decide supported trade shapes.
- Decide typed-data domain/version.
- Build an ERC721-derived test matrix for v2.

### During ERC1155 v2 implementation

- Use ERC721 `OfferItem` / `ConsiderationItem` structure.
- Add partial-fill storage fields.
- Add royalty overlay in settlement.
- Restore configurable primary proceeds recipient.
- Use named errors.

### Later ERC721 v2 or shared-core work

- Consider upgrading ERC721 registration timing.
- Consider richer events.
- Consider multi-consideration order version.
- Consider shared Cairo modules if contract organization allows it cleanly.

## Verification Notes

I attempted to run the ERC721 test suite:

```bash
PATH="/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" snforge test
```

The run did not reach tests because `snforge` reported Scarb was unavailable. The repository pins `scarb 2.18.0` in `.tool-versions`, but this machine currently has `scarb 2.17.0` installed under asdf.

References:
- `contracts/Medialane-Protocol-ERC721/.tool-versions:1`
- `contracts/Medialane-Protocol-ERC721/Scarb.toml:7`

So this audit is based on source review and test-suite inspection, not a passing local test run.

## Final Assessment

ERC721 is the right architectural parent for ERC1155 v2, but it should be treated as a strong draft rather than a final shared core.

The main refactor is conceptual: turn ERC721's useful generic marketplace vocabulary into a deliberately specified Medialane marketplace vocabulary. Then ERC1155 v2 can inherit the shape, improve the validation model, and add partial fills and royalties without becoming a separate protocol family.
