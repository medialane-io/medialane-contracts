# ERC1155 v2 Refactor Checklist

Date: 2026-04-26

Status: Ready for execution

Related docs:
- [ERC721 architecture audit](/Users/kalamaha/dev/medialane-contracts/ERC721_architecture_audit_report_2026-04-26.md)
- [ERC1155 parity architecture spec](/Users/kalamaha/dev/medialane-contracts/ERC1155_parity_architecture_spec_2026-04-26.md)
- [ERC1155 v2 implementation map](/Users/kalamaha/dev/medialane-contracts/ERC1155_v2_implementation_map_2026-04-26.md)
- [ERC1155 vs ERC721 audit report](/Users/kalamaha/dev/medialane-contracts/ERC1155_vs_ERC721_audit_report_2026-04-26.md)

## Objective

Refactor `Medialane-Protocol-ERC1155` into an ERC1155 v2 contract that matches the Seaport-inspired architecture of `Medialane-Protocol-ERC721`, while preserving:

- partial fills
- ERC-2981 royalties
- creator monetization extensibility

## Guiding Decisions

These should be treated as the default unless we explicitly change course:

- Reintroduce ERC721-style `ItemType`, `OfferItem`, and `ConsiderationItem`
- Keep ERC1155-specific behavior in fulfillment and settlement, not in a separate order model
- Preserve configurable `consideration.recipient`
- Normalize the ERC1155 ABI to look more like ERC721
- Treat the redesign as a new deployment and new typed-data version
- Prefer registration-anytime-before-expiry semantics for the long term
- Improve ERC721 validation gaps before using it as the v2 baseline

## Phase 0: Product Decisions

These need a yes/no decision before code work is finalized.

### 0.1 Typed-data domain choice

- Decide between:
  - `name = 'Medialane'`, `version = 2`
  - `name = 'Medialane1155'`, `version = 2`
- Acceptance criteria:
  - choice is documented in the spec and README
  - frontend signing code has one clear implementation target

### 0.2 Stored fulfiller policy

- Decide whether `OrderDetails.fulfiller` should:
  - mirror ERC721 and store the last/full fulfiller
  - be removed entirely and derived from events
- Acceptance criteria:
  - storage shape is fixed before implementing tests and indexer updates

### 0.3 First-release monetization scope

- Decide whether ERC1155 v2 ships with:
  - one `ConsiderationItem` plus royalty overlay
  - or immediate support for multiple payout legs
- Recommendation:
  - ship one consideration leg first
- Acceptance criteria:
  - scope is frozen before hash/type definitions are finalized

### 0.4 Supported trade-shape policy

- Decide which item pairs are supported in ERC1155 v2 launch
- Recommended launch support:
  - ERC1155 offer for ERC20 or NATIVE consideration
  - ERC20 or NATIVE offer for ERC1155 consideration, if bid flow is in scope
- Acceptance criteria:
  - supported shapes are documented
  - unsupported shapes have explicit tests or documented off-chain filtering

## Phase 1: Contract Skeleton

### 1.1 Create v2 contract target

- Add a new contract module for the redesign instead of mutating the deployed shape in place
- Recommended target naming:
  - `Medialane1155V2`
  - `IMedialane1155V2`
- Acceptance criteria:
  - legacy ERC1155 contract remains intact
  - v2 contract compiles independently once toolchain is available

### 1.2 Reintroduce shared base types

- Add or restore:
  - `ItemType`
  - `OfferItem`
  - `ConsiderationItem`
- Align these with ERC721 unless there is a documented reason not to
- Acceptance criteria:
  - type fields and hashing logic match ERC721 conventions
  - ERC1155-specific code no longer uses the narrow `nft_contract/payment_token/price_per_unit` order schema as the primary model

### 1.3 Rebuild `OrderParameters`

- Replace the current ERC1155 order schema with the ERC721-style signed order shape
- Preserve:
  - `offerer`
  - `offer`
  - `consideration`
  - `start_time`
  - `end_time`
  - `salt`
  - `nonce`
- Acceptance criteria:
  - `OrderParameters` is structurally aligned with ERC721
  - hash generation is versioned and deterministic

## Phase 2: Storage and Lifecycle

### 2.1 Redesign `OrderDetails`

- Restore ERC721-style storage members:
  - `offerer`
  - `offer`
  - `consideration`
  - `start_time`
  - `end_time`
  - `order_status`
- Add ERC1155-specific fields:
  - `total_amount`
  - `remaining_amount`
- Add `fulfiller` only if chosen in Phase 0
- Acceptance criteria:
  - storage is rich enough to reconstruct generic order semantics
  - partial fill tracking does not discard Seaport-style order structure

### 2.2 Preserve order lifecycle

- Keep lifecycle:
  - `None`
  - `Created`
  - `Filled`
  - `Cancelled`
- Acceptance criteria:
  - partial fills stay in `Created`
  - only zero remaining amount transitions to `Filled`

### 2.3 Align registration semantics

- Implement the chosen shared rule for registration timing
- Recommended target:
  - register anytime before expiry
  - fulfill only during active window
- Acceptance criteria:
  - timing behavior is documented
  - tests cover both registration and fulfillment windows

### 2.4 Add registration-time item validation

- Validate before storing an order:
  - token address for `ERC20`, `ERC721`, and `ERC1155`
  - consideration recipient
  - amount constraints for each item type
  - `start_time < end_time` when `end_time != 0`
- Acceptance criteria:
  - invalid orders are rejected before they become indexable `Created` orders

## Phase 3: Fulfillment and Settlement

### 3.1 Define ERC1155 fulfillment extension

- Keep `OrderFulfillment` with:
  - `order_hash`
  - `fulfiller`
  - `quantity`
  - `nonce`
- Acceptance criteria:
  - `quantity` is the only ERC1155-specific signed fulfillment addition
  - signed fulfillment remains close to ERC721 mental model

### 3.2 Rebuild transfer routing

- Restore a generic transfer helper similar to ERC721's `_transfer_item`
- Support:
  - `NATIVE`
  - `ERC20`
  - `ERC721`
  - `ERC1155`
- Acceptance criteria:
  - ERC1155 v2 uses generic transfer routing instead of a single-purpose settlement path
  - offer/consideration item validation is consistent with ERC721

### 3.3 Add partial fill settlement

- Compute sale value from:
  - listed amount
  - fill quantity
  - unit economics implied by the order
- Update `remaining_amount` before external transfers
- Acceptance criteria:
  - overfill is impossible
  - double-fill and re-entrant same-order fill attempts fail cleanly

### 3.4 Add royalty routing without losing recipient flexibility

- Royalty calculation should be an additive settlement step
- Payment destination for non-royalty value must remain `consideration.recipient`
- Acceptance criteria:
  - royalty receiver can be paid
  - signed recipient can still differ from offerer
  - royalty logic cannot silently erase future monetization patterns

### 3.5 Prepare settlement for future monetization

- Structure settlement so future layers can be added:
  - protocol fee
  - referral fee
  - creator split routing
- Acceptance criteria:
  - settlement logic is decomposed into helpers
  - future payout legs can be added without redesigning `OrderParameters` again

## Phase 4: Interface and Hashing

### 4.1 Normalize ABI naming

- Prefer:
  - `get_native_token_address`
- Keep:
  - `register_order`
  - `fulfill_order`
  - `cancel_order`
  - `get_order_details`
  - `get_order_hash`
  - `nonces`
- Acceptance criteria:
  - shared client logic between ERC721 and ERC1155 becomes simpler

### 4.2 Finalize type hashes

- Add updated SNIP-12 type hashes for v2
- Ensure the type strings match the final chosen structs exactly
- Acceptance criteria:
  - no hardcoded mystery constants
  - hash tests prove determinism and sensitivity to changed fields

### 4.3 Version signing clearly

- Update SNIP-12 metadata for the v2 choice
- Acceptance criteria:
  - no ambiguity between current ERC1155 signatures and v2 signatures
  - scripts and docs reflect the final domain/version

## Phase 5: Events and Indexing

### 5.1 Preserve event identity fields

- `OrderCreated` should keep:
  - `order_hash`
  - `offerer`
- `OrderFulfilled` should keep:
  - `order_hash`
  - `offerer`
  - `fulfiller`
- `OrderCancelled` should keep:
  - `order_hash`
  - `offerer`
- Acceptance criteria:
  - shared indexer logic can still anchor on the same event identity fields

### 5.2 Extend events for ERC1155 settlement detail

- Add non-indexed ERC1155 fulfillment details:
  - `quantity`
  - `remaining_amount`
  - `sale_amount`
  - `royalty_receiver`
  - `royalty_amount`
- Acceptance criteria:
  - indexers can reconstruct partial fills and payout flows from events

### 5.3 Avoid unnecessary event divergence

- Only add fields that improve indexing, settlement transparency, or future monetization support
- Acceptance criteria:
  - event model remains close to ERC721, not a separate product vocabulary

## Phase 6: Test Suite Parity

ERC1155 v2 should not ship until it has at least ERC721-equivalent coverage plus ERC1155-specific additions.

### 6.1 Core parity tests

- Add tests for:
  - valid register
  - valid fulfill
  - valid cancel
  - invalid register signature
  - invalid fulfill signature
  - invalid cancel signature
  - expired fulfill
  - not-yet-valid fulfill
  - duplicate registration rejection
  - double-fill rejection
  - cancel-after-fill rejection
  - wrong caller rejection
  - wrong offerer rejection

### 6.2 ERC1155-specific tests

- Add tests for:
  - partial fill success
  - full fill success
  - self-fill rejection
  - overfill rejection
  - royalty distribution success
  - zero-royalty success
  - zero-address native token alias flow
  - recipient different from offerer

### 6.3 Event tests

- Assert emitted payloads for:
  - order creation
  - full fill
  - partial fill
  - cancellation
  - royalty metadata

### 6.4 Hash tests

- Add deterministic tests for:
  - order hash
  - fulfillment hash
  - cancellation hash
- Add change-sensitivity tests for:
  - quantity
  - recipient
  - amount
  - token id
  - item type

## Phase 7: Docs and Tooling

### 7.1 README update

- Rewrite ERC1155 docs to describe:
  - shared Seaport-style order model
  - partial-fill extension
  - royalty extension
  - migration/versioning
- Acceptance criteria:
  - README no longer describes ERC1155 as a separate marketplace architecture

### 7.2 Signature/tooling scripts

- Update or add scripts to generate v2 signatures
- Acceptance criteria:
  - test signatures are reproducible
  - frontend/backend teams have a reference implementation

### 7.3 Deployment notes

- Document:
  - constructor arguments
  - typed-data domain/version
  - class hash / deployment workflow
  - migration notes for indexers
- Acceptance criteria:
  - deploy and integration steps are unambiguous

## Phase 8: Backend and Migration

### 8.1 Treat v2 as a new deployment

- Do not reuse the current ERC1155 contract interface as if it were equivalent
- Acceptance criteria:
  - legacy and v2 are handled explicitly

### 8.2 Backend/indexer support

- Update backend to support:
  - legacy ERC1155 historical events
  - ERC1155 v2 new event/data shape
- Acceptance criteria:
  - new listings can use v2 without breaking historical reads

### 8.3 Cutover plan

- Route all new ERC1155 listings to v2
- Keep legacy contract data queryable
- Acceptance criteria:
  - cutover does not require rewriting old on-chain history

## Suggested Execution Order

1. Freeze Phase 0 decisions.
2. Freeze supported trade shapes and validation rules.
3. Build v2 type system and hashing.
4. Rebuild storage and registration.
5. Rebuild fulfillment and settlement.
6. Finalize events and interface naming.
7. Bring test suite to parity.
8. Update docs and signing scripts.
9. Prepare backend/indexer cutover.

## Done Definition

ERC1155 v2 is ready when all of the following are true:

- order primitives are architecture-aligned with ERC721
- recipient flexibility is restored
- invalid orders are rejected at registration
- supported trade shapes are documented and tested
- partial fills work
- royalties work
- test coverage matches or exceeds ERC721 core coverage
- backend/indexer migration plan is documented
- docs clearly describe one marketplace architecture with ERC1155-specific extensions

## Recommended Immediate Next Step

Use the implementation map to begin the code refactor inside `contracts/Medialane-Protocol-ERC1155`:

- `types.cairo`
- `utils.cairo`
- `interface.cairo`
- `events.cairo`
- `medialane.cairo`
- `tests/tests.cairo`

The first concrete code step should be adding `errors.cairo`, then refactoring `types.cairo` to the shared marketplace vocabulary.
