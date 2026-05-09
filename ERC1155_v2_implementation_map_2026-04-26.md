# ERC1155 v2 Implementation Map

Date: 2026-04-26

Status: Recommended implementation path

Related docs:
- [ERC721 architecture audit](/Users/kalamaha/dev/medialane-contracts/ERC721_architecture_audit_report_2026-04-26.md)
- [ERC1155 parity architecture spec](/Users/kalamaha/dev/medialane-contracts/ERC1155_parity_architecture_spec_2026-04-26.md)
- [ERC1155 v2 refactor checklist](/Users/kalamaha/dev/medialane-contracts/ERC1155_v2_refactor_checklist_2026-04-26.md)

## Lead Recommendation

Build ERC1155 v2 as "ERC721 marketplace architecture plus audit improvements," not as a copy of the current ERC1155 contract.

The current ERC1155 contract already has useful pieces:

- partial-fill accounting
- ERC-2981 royalty probing
- royalty payment routing
- better registration timing than ERC721

But v2 should replace its narrow order model with the ERC721-style marketplace vocabulary:

- `ItemType`
- `OfferItem`
- `ConsiderationItem`
- `OrderParameters`
- generic transfer routing

## Frozen Defaults

These are the defaults I recommend using unless product needs push us elsewhere.

### Typed-Data Domain

- Contract: `Medialane1155V2`
- Interface: `IMedialane1155V2`
- SNIP-12 domain name: `Medialane`
- SNIP-12 version: `2`

Reason:

- We want one Medialane marketplace family.
- Version `2` prevents signature confusion with deployed ERC721 and legacy ERC1155.

### Launch Trade Shapes

Launch support:

- `ERC1155` offer for `ERC20` consideration
- `ERC1155` offer for `NATIVE` consideration

Documented extension, not required for first implementation:

- `ERC20` or `NATIVE` offer for `ERC1155` consideration, for bid flow

Reason:

- Listings are the clearest path to parity with current ERC1155 behavior.
- Bid flow can reuse the same model later, but it requires stronger product and UX decisions.

### Order Shape

Use ERC721-style `OrderParameters`:

```cairo
struct OrderParameters {
    offerer: ContractAddress,
    offer: OfferItem,
    consideration: ConsiderationItem,
    start_time: felt252,
    end_time: felt252,
    salt: felt252,
    nonce: felt252,
}
```

### Storage Shape

Recommended `OrderDetails`:

```cairo
struct OrderDetails {
    offerer: ContractAddress,
    offer: OfferItem,
    consideration: ConsiderationItem,
    start_time: u64,
    end_time: u64,
    order_status: OrderStatus,
    total_amount: felt252,
    remaining_amount: felt252,
}
```

Do not store `fulfiller` in ERC1155 v2.

Reason:

- Partial fills can have many buyers.
- A single stored `fulfiller` is ambiguous.
- Fulfillers should be indexed from `OrderFulfilled` events.

### Monetization Scope

Ship with:

- one signed `ConsiderationItem`
- ERC-2981 royalty overlay
- primary proceeds paid to `consideration.recipient`

Do not ship with multiple consideration legs yet.

Reason:

- This restores recipient flexibility immediately.
- It keeps v2 focused.
- Settlement can still be structured so multi-recipient `OrderParametersV3` can be added later.

### Time Semantics

Use the improved ERC1155 timing model:

- registration allowed anytime before expiry
- fulfillment allowed only inside active window
- when `end_time != 0`, require `start_time < end_time`

Reason:

- Better UX for off-chain signed listings.
- Avoids permanently unfulfillable orders.
- Fixes a weakness found in the ERC721 audit.

### Error Strategy

Add or reuse named error constants.

Reason:

- Error strings should not drift between ERC721 and ERC1155.
- Tests become clearer and less brittle.

## File-by-File Map

### `src/core/types.cairo`

Replace the narrow ERC1155 order model with ERC721-style primitives.

Add:

- `ItemType`
- `OfferItem`
- `ConsiderationItem`
- `OfferItemHashImpl`
- `ConsiderationItemHashImpl`

Change:

- `OrderParameters` should use `offer` and `consideration`
- `OrderDetails` should store `offer` and `consideration`
- `OrderDetails` should add `total_amount` and `remaining_amount`
- `OrderFulfillment` should keep `quantity`

Remove from the primary signed order model:

- `nft_contract`
- `token_id`
- `amount`
- `payment_token`
- `price_per_unit`

These values are represented by:

- `offer.token`
- `offer.identifier_or_criteria`
- `offer.start_amount`
- `consideration.token`
- `consideration.start_amount`
- `consideration.recipient`

Acceptance criteria:

- Type vocabulary matches ERC721 where possible.
- Quantity remains fulfillment-specific.
- Hash tests prove changes to offer, consideration, recipient, and quantity affect signatures.

### `src/core/utils.cairo`

Replace current ERC1155 type hashes with v2 hashes.

Add:

- `OFFER_ITEM_TYPE_HASH`
- `CONSIDERATION_ITEM_TYPE_HASH`

Change:

- `ORDER_PARAMETERS_TYPE_HASH` should match ERC721-style nested order type.
- `FULFILLMENT_TYPE_HASH` should include `quantity`.
- `CANCELATION_TYPE_HASH` can remain structurally aligned with ERC721.

Keep:

- `IERC2981_ID`
- `felt_to_u64`
- `felt_to_u256`

Add if useful:

- shared helpers for validated felt-to-u256 conversions
- named constants for royalty and native-token behavior

Acceptance criteria:

- Type strings are explicit and readable.
- Hashes are computed with `selector!()`, not unexplained literals.

### `src/core/interface.cairo`

Create or rename to `IMedialane1155V2`.

Keep:

- `register_order`
- `fulfill_order`
- `cancel_order`
- `get_order_details`
- `get_order_hash`

Change:

- expose `get_native_token_address`, matching ERC721 naming

Acceptance criteria:

- Shared client code can call the same getter on ERC721 and ERC1155 v2.
- Legacy ERC1155 interface remains distinguishable.

### `src/core/events.cairo`

Preserve event identity fields.

`OrderCreated`:

- keep `order_hash`
- keep `offerer`
- optionally add non-indexed offer/consideration summary fields

`OrderFulfilled`:

- keep `order_hash`
- keep `offerer`
- keep `fulfiller`
- add `quantity`
- add `remaining_amount`
- add `sale_amount`
- add `royalty_receiver`
- add `royalty_amount`

`OrderCancelled`:

- keep `order_hash`
- keep `offerer`

Acceptance criteria:

- ERC721 and ERC1155 v2 share event identity semantics.
- ERC1155 v2 exposes enough data for partial-fill and royalty indexing.

### `src/core/errors.cairo`

Add an errors module if it does not exist in ERC1155.

Use named constants for:

- invalid signature
- order expired
- order not yet valid
- order not found
- order already created
- order already filled
- order cancelled
- invalid item type
- invalid amount
- invalid token address
- invalid recipient
- caller not fulfiller
- caller not offerer
- unsupported trade shape
- invalid quantity
- insufficient remaining
- royalty exceeds sale price
- price overflow

Acceptance criteria:

- Contract uses named errors consistently.
- Tests reference stable expected messages.

### `src/core/medialane.cairo`

Rename contract module for v2:

- `Medialane1155V2`

Change SNIP-12 metadata:

- name: `Medialane`
- version: `2`

Registration flow:

1. read parameters
2. validate offerer
3. validate offer item
4. validate consideration item
5. validate supported trade shape
6. validate fixed-price amounts
7. validate registration time
8. validate order hash is unused
9. validate offerer signature
10. consume offerer nonce
11. write `OrderDetails`
12. emit `OrderCreated`

Fulfillment flow:

1. read order
2. validate caller equals fulfiller
3. validate fulfiller is not offerer
4. validate quantity
5. validate active window
6. validate fulfillment signature
7. consume fulfiller nonce
8. decrement remaining and update status before external calls
9. execute settlement
10. emit `OrderFulfilled`

Settlement flow:

1. transfer ERC1155 offer from seller to buyer
2. compute sale amount from consideration amount and fill quantity
3. resolve `NATIVE` consideration to `native_token_address`
4. query ERC-2981 royalty
5. pay royalty from fulfiller
6. pay remainder to `consideration.recipient`

Important details:

- royalty must not redirect primary proceeds away from `consideration.recipient`
- unsupported trade shapes should fail at registration
- order status must be updated before external token transfers

Acceptance criteria:

- Same architecture as ERC721.
- Better validation than ERC721.
- Same partial-fill and royalty capability as legacy ERC1155.

### `tests/tests.cairo`

Build the test suite in layers.

Hash tests:

- deterministic order hash
- deterministic fulfillment hash
- deterministic cancellation hash
- hash changes when recipient changes
- hash changes when quantity changes

Registration tests:

- valid ERC1155-for-ERC20 listing
- valid ERC1155-for-NATIVE listing
- reject duplicate order
- reject zero offerer
- reject zero ERC1155 token address
- reject zero consideration recipient
- reject unsupported trade shape
- reject `start_time >= end_time` when expiry exists
- reject expired order registration
- reject invalid signature

Fulfillment tests:

- full fill without royalty
- partial fill without royalty
- full fill with royalty
- partial fill with royalty
- reject wrong caller
- reject self-fill
- reject quantity zero
- reject overfill
- reject not-yet-valid fulfillment
- reject expired fulfillment
- reject invalid signature
- reject double full-fill

Cancellation tests:

- valid cancellation
- reject wrong offerer
- reject cancellation after full fill
- reject cancellation after cancellation
- reject invalid signature

Event tests:

- `OrderCreated`
- partial `OrderFulfilled`
- full `OrderFulfilled`
- royalty metadata
- `OrderCancelled`

Acceptance criteria:

- ERC1155 v2 test coverage is at least as strong as ERC721.
- ERC1155-specific behavior is tested explicitly.

### `scripts/compute_signatures.mjs`

Update signature generation for v2 typed data.

Change:

- domain name `Medialane`
- domain version `2`
- order shape to nested `OfferItem` / `ConsiderationItem`
- fulfillment shape includes `quantity`

Add fixtures for:

- full fill
- partial fill
- cancel
- invalid signature cases

Acceptance criteria:

- Tests can regenerate signatures from one command.
- Fixture comments identify offer side and consideration side clearly.

### `README.md`

Rewrite around shared marketplace architecture.

Include:

- v2 domain/version
- supported launch trade shapes
- order schema
- partial-fill behavior
- royalty behavior
- native-token alias behavior
- migration notes from legacy ERC1155

Acceptance criteria:

- README says ERC1155 v2 is a Medialane marketplace extension, not a separate marketplace design.

## Implementation Sequence

1. Add `errors.cairo`.
2. Refactor `types.cairo` to shared marketplace vocabulary.
3. Refactor `utils.cairo` type hashes.
4. Update `interface.cairo`.
5. Update `events.cairo`.
6. Refactor `medialane.cairo` registration and settlement.
7. Update signature script.
8. Rewrite tests.
9. Update README.
10. Run build/tests after Scarb 2.18.0 is available.

## Open Risks

### Native payment modeling

Current ERC721 models `NATIVE` as an item type whose transfer is still `IERC20.transfer_from` on stored STRK. ERC1155 v2 should preserve that convention for Starknet STRK.

### Unit price calculation

With one `ConsiderationItem`, price per unit is derived from:

```text
consideration.start_amount / offer.start_amount
```

For exact settlement, first implementation should require the consideration amount to divide evenly by the offered amount.

If fractional pricing is needed later, use a more explicit pricing field in a future order version.

### Bid flow

ERC20/NATIVE-for-ERC1155 bid flow is architecturally supported by the shared model, but partial-fill semantics differ depending on who owns which side. Launching it should be a separate acceptance decision.

## Done Definition

ERC1155 v2 implementation is done when:

- order model uses `OfferItem` and `ConsiderationItem`
- launch trade shapes are enforced
- invalid orders are rejected before storage
- partial fills update state before external calls
- royalties pay on actual sale amount
- primary proceeds go to `consideration.recipient`
- events expose fill and royalty data
- signatures use `Medialane` domain version `2`
- tests cover parity and ERC1155-specific behavior
