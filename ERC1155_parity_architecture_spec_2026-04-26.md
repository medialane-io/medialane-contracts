# ERC1155 Parity Architecture Spec

Date: 2026-04-26

Status: Proposed

Scope:
- `contracts/Medialane-Protocol-ERC721`
- future redesign of `contracts/Medialane-Protocol-ERC1155`

Related baseline audit:
- [ERC721 architecture audit](/Users/kalamaha/dev/medialane-contracts/ERC721_architecture_audit_report_2026-04-26.md)

Implementation map:
- [ERC1155 v2 implementation map](/Users/kalamaha/dev/medialane-contracts/ERC1155_v2_implementation_map_2026-04-26.md)

## Goal

Redesign `Medialane-Protocol-ERC1155` so it follows the same Seaport-inspired architectural model as `Medialane-Protocol-ERC721`, while preserving the ERC1155-specific features Medialane needs:

- partial fills
- ERC-2981 royalties
- creator monetization extensions

The target is not byte-level or ABI-level identity. The target is protocol parity:

- same core mental model
- same order primitives
- same indexer/client architecture
- same signing flow patterns
- same future extensibility for monetization features

## Design Principles

1. Preserve the ERC721 protocol shape wherever possible.
2. Make ERC1155-specific behavior additive, not structural.
3. Keep the signed order model generic enough for future creator monetization.
4. Prefer shared off-chain infrastructure over per-contract custom logic.
5. Version explicitly when changing typed-data structures or event payloads.
6. Improve ERC721 baseline weaknesses before they become ERC1155 v2 defaults.

## Recommended Direction

Do not continue with the current ERC1155 contract shape as the long-term marketplace standard.

Instead, build `Medialane-Protocol-ERC1155 v2` as:

- Seaport-style core order model from ERC721
- ERC1155-aware fulfillment semantics
- monetization hooks layered on top of consideration settlement

In practice, that means ERC1155 should move back toward the ERC721 primitives:

- `ItemType`
- `OfferItem`
- `ConsiderationItem`
- `OrderParameters`
- `OrderDetails`
- generic transfer routing by item type

Then extend them only where ERC1155 genuinely needs more information.

## Target Architecture

### 1. Shared Order Model

ERC1155 should adopt the same base types as ERC721:

```cairo
enum ItemType {
    NATIVE,
    ERC20,
    ERC721,
    ERC1155,
}

struct OfferItem {
    item_type: felt252,
    token: ContractAddress,
    identifier_or_criteria: felt252,
    start_amount: felt252,
    end_amount: felt252,
}

struct ConsiderationItem {
    item_type: felt252,
    token: ContractAddress,
    identifier_or_criteria: felt252,
    start_amount: felt252,
    end_amount: felt252,
    recipient: ContractAddress,
}
```

This preserves the same architectural base as ERC721 and restores these capabilities:

- generic item representation
- configurable payment recipients
- future support for fees, splits, treasuries, referrals, and bundles
- shared typed-data generation logic

### 2. ERC1155 Extension Model

ERC1155 should extend fulfillment, not replace the order schema.

There are two viable approaches:

#### Option A: Minimal parity-first extension

Keep `OrderParameters` exactly aligned with ERC721 and add only ERC1155-specific behavior in fulfillment:

- partial fill quantity
- per-fill settlement amount
- royalty calculation based on actual filled quantity

This is the recommended starting point.

#### Option B: Explicit advanced order model

Introduce a versioned order schema with multiple offer/consideration items or richer constraints.

This is more flexible, but it is a bigger protocol jump and is not needed to restore parity.

Recommendation: use Option A first.

### 3. Fulfillment Semantics

The ERC1155-specific behavior should live in `OrderFulfillment` and in storage:

```cairo
struct OrderFulfillment {
    order_hash: felt252,
    fulfiller: ContractAddress,
    quantity: felt252,
    nonce: felt252,
}
```

Storage should preserve ERC721-compatible fields, plus the additional ERC1155 fill tracking:

```cairo
struct OrderDetails {
    offerer: ContractAddress,
    offer: OfferItem,
    consideration: ConsiderationItem,
    start_time: u64,
    end_time: u64,
    order_status: OrderStatus,
    fulfiller: Option<ContractAddress>,
    total_amount: felt252,
    remaining_amount: felt252,
}
```

Notes:

- `offer` and `consideration` should remain first-class storage members.
- `total_amount` and `remaining_amount` are the ERC1155-specific additions.
- `fulfiller` may remain `None` until a full fill, or reflect the most recent fulfiller. This needs a product decision.

Recommended behavior:

- if `remaining_amount == 0`, mark `Filled`
- otherwise remain `Created`
- keep `fulfiller` as the most recent fulfiller only if downstream consumers benefit from it

If no consumer truly needs stored fulfiller state, it can be omitted and derived from events. But that should be a deliberate cross-protocol decision, not an ERC1155-only divergence.

## ABI Recommendations

### Keep

- `register_order(order)`
- `fulfill_order(fulfillment_request)`
- `cancel_order(cancel_request)`
- `get_order_details(order_hash)`
- `get_order_hash(parameters, signer)`
- `nonces(account)`

### Normalize

ERC1155 should use the same getter naming as ERC721:

- prefer `get_native_token_address`

That reduces unnecessary client branching.

### Typed-Data Domain

Current ERC721 domain:

- name: `Medialane`
- version: `1`

Current ERC1155 domain:

- name: `Medialane1155`
- version: `1`

Recommended path:

- introduce a new explicit version for the redesigned ERC1155 contract
- keep the domain name aligned to the Medialane marketplace family

Two acceptable choices:

#### Choice 1: Use `name = 'Medialane'`, `version = 2`

Pros:

- strongest parity signal
- easiest shared client mental model

Cons:

- frontend/backend must be careful about version and contract address

#### Choice 2: Use `name = 'Medialane1155'`, `version = 2`

Pros:

- clearer contract-family separation
- less risk of accidental typed-data mixups

Cons:

- slightly weaker parity at the signing layer

Recommendation:

- prefer `name = 'Medialane'`, `version = 2` if you want one marketplace family
- prefer `name = 'Medialane1155'`, `version = 2` if operational separation is more important than aesthetic parity

Either way, the type structure should converge with ERC721.

## Settlement Model

### Baseline Parity

ERC1155 settlement should preserve ERC721's generic transfer pipeline:

1. transfer offered asset from offerer to fulfiller
2. transfer consideration from fulfiller to recipient

### ERC1155 Monetization Extension

Settlement should become a routed pipeline:

1. compute actual fill amount from `quantity`
2. transfer offered ERC1155 units
3. compute royalty from `sale_value`
4. distribute royalty if applicable
5. distribute remaining consideration to the signed recipient
6. optionally distribute platform or referral consideration legs if encoded

Important principle:

royalties should not replace `consideration.recipient`

Instead:

- royalties are an overlay on settlement
- signed consideration remains the source of truth for primary sale destination

This is critical for creator monetization flexibility.

## Monetization-Ready Architecture

To support Medialane's long-term roadmap, the redesign should leave room for:

- creator revenue splits
- collaborator payouts
- referral fees
- fan rewards or rebates
- gated commerce utilities
- primary vs secondary sale behavior
- protocol fee toggles

The cleanest way to support those without redesigning again is:

1. restore generic `ConsiderationItem`
2. introduce versioned settlement helpers
3. keep event payloads rich enough for indexing payout flows

There are two reasonable monetization models.

### Model A: Single consideration item plus derived royalty routing

Simpler and closer to current code.

Good for:

- seller payout
- ERC-2981 royalties

Weaker for:

- multi-party creator splits
- protocol/referral fee composition

### Model B: Multiple consideration legs

More Seaport-like and more future-proof.

Good for:

- seller payout
- creator split recipients
- protocol fees
- affiliate/referral payouts

Recommendation:

- implement Model A first if speed matters
- but design the storage, event model, and type versioning so Model B can be added without another total rewrite

## Event Model

Event design should support both parity and indexing.

### Preserve

- `OrderCreated`
- `OrderFulfilled`
- `OrderCancelled`

### Recommended payload shape

#### `OrderCreated`

Keep ERC721's indexed identity:

- `order_hash`
- `offerer`

Add optional non-indexed details if useful for indexers:

- `offer_item_type`
- `offer_token`
- `offer_identifier`
- `offer_amount`
- `consideration_item_type`
- `consideration_token`
- `consideration_amount`
- `recipient`

#### `OrderFulfilled`

Must include:

- `order_hash`
- `offerer`
- `fulfiller`

For ERC1155, also include:

- `quantity`
- `remaining_amount`
- `sale_amount`
- `royalty_receiver`
- `royalty_amount`

Optional future additions:

- `protocol_fee_amount`
- `referral_fee_amount`

Recommendation:

keep the ERC721 event identity fields untouched and extend with non-indexed ERC1155-specific settlement fields.

## Validation Rules

### Shared Rules with ERC721

- non-zero offerer
- valid item types
- fixed-price enforcement unless explicitly versioned otherwise
- valid signature
- nonce consumption
- caller must equal fulfiller
- only offerer may cancel
- CEI before external transfers

### Shared Rules to Improve from ERC721

- reject `start_time >= end_time` when `end_time != 0`
- validate token addresses at registration
- validate consideration recipient at registration
- define supported trade shapes in docs and tests
- use named error constants instead of repeated inline literals

### ERC1155-Specific Rules

- offer item must be `ERC1155`
- `quantity > 0`
- `quantity <= remaining_amount`
- sale amount must be computed from actual filled quantity
- royalty amount cannot exceed sale amount

### Time Window Semantics

Current divergence:

- ERC721 registration requires `now <= start_time`
- ERC1155 allows registering after `start_time`

Recommendation:

align both protocols on one rule set before expanding ERC1155.

Preferred rule:

- registration allowed anytime before expiry
- fulfillment allowed only inside active window

Reason:

- more robust to block timing and delayed submission
- better UX
- easier off-chain listing workflows

This implies adopting the newer ERC1155 registration rule in the shared model, then later updating ERC721 if you want full behavioral parity.

## Suggested Type Versioning

To avoid confusion, treat the redesign as a new protocol version.

Recommended naming:

- `Medialane1155V2` for the contract
- `IMedialane1155V2` for the interface

Then keep internal type naming aligned with ERC721:

- `OrderParameters`
- `OfferItem`
- `ConsiderationItem`
- `OrderFulfillment`
- `OrderCancellation`

That gives you:

- explicit deployment/version separation
- shared off-chain type vocabulary
- less confusion during migration

## Implementation Plan

### Phase 1: Spec and alignment

1. Freeze the target ERC1155 v2 order model.
2. Decide typed-data domain naming/version.
3. Decide whether `fulfiller` stays in storage.
4. Decide whether the first release supports only one consideration leg or prepares for many.
5. Apply ERC721 audit recommendations that should become v2 baseline rules.

### Phase 2: Contract refactor

1. Reintroduce `ItemType`, `OfferItem`, and `ConsiderationItem`.
2. Rewrite `OrderParameters` to mirror ERC721.
3. Add `remaining_amount` and `quantity` support.
4. Refactor `_execute_transfers` into a settlement pipeline.
5. Add royalty routing without losing recipient flexibility.

### Phase 3: Event and client parity

1. Normalize ABI naming where practical.
2. Preserve shared event identity fields.
3. Update scripts and typed-data generation.
4. Update README and deployment docs.

### Phase 4: Test parity

ERC1155 v2 tests should include all current ERC721 core tests plus ERC1155-specific additions:

- register valid order
- fulfill valid order
- cancel valid order
- invalid registration signature
- invalid fulfillment signature
- invalid cancellation signature
- expired fulfillment
- not-yet-valid fulfillment
- duplicate registration rejection
- double-fill rejection
- cancel-after-fill rejection
- wrong caller rejection
- wrong offerer rejection
- self-fill rejection
- overfill rejection
- zero-address native-token alias flow
- partial fill success
- full fill success
- royalty success
- event payload assertions

## Migration Considerations

This should be a new deployment, not a mutation of the current ERC1155 deployed contract shape.

Reasons:

- signed payload schema changes
- interface changes
- storage model changes
- event interpretation changes

Migration strategy:

1. deploy new ERC1155 v2 class and contract
2. update backend/indexer to support both legacy and v2 contracts
3. route new listings to v2 only
4. leave legacy contract readable for historical orders

## Final Recommendation

The best long-term Medialane architecture is:

- one shared Seaport-inspired marketplace vocabulary
- one shared order model
- asset-specific fulfillment logic
- monetization layered into settlement, not hardcoded into one contract flavor

For ERC1155 specifically, the next implementation should aim for:

- ERC721 parity in primitives
- ERC1155-specific partial-fill semantics
- ERC-2981 royalties as an additive payout layer
- future-ready consideration routing for creator monetization

This gives Medialane a cleaner foundation for a unified creator and collector marketplace instead of two contracts that happen to share a name.
