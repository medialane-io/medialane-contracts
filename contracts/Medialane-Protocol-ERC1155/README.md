# Medialane Protocol (ERC-1155)

The ERC1155 marketplace contract for Medialane on Starknet.

This package contains `Medialane1155V2`, the immutable ERC1155 marketplace aligned with the ERC721 marketplace architecture.

It supports:

- ERC721-style `OfferItem` / `ConsiderationItem` order vocabulary
- fixed-price ERC1155 sell listings for ERC20 or STRK-style consideration
- partial fills
- ERC-2981 royalty routing
- SNIP-12 signed order registration, fulfillment, and cancellation
- configurable primary-sale recipient through `consideration.recipient`

## Status

- Production status: v2 deployed on Starknet mainnet
- Contract family role: ERC1155 marketplace aligned with ERC721
- Upgradeability: immutable
- Current architecture: shared marketplace vocabulary with ERC1155 settlement extensions
- Verified class hash: `0x03e1b84f1058dd5c9c766634e638d02756b59910080492983a5168c99856efd0`

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `Medialane1155V2` contract | `0x04a0a65bd13e1ec9a2ce92c36115578486331e941b395f97d49fe488baac8309` |
| Mainnet | Class hash | `0x03e1b84f1058dd5c9c766634e638d02756b59910080492983a5168c99856efd0` |
| Mainnet | Native token (STRK) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |
| Mainnet | Declare tx | `0x0685d29dec774934809842310d0696aa86127f9fa7f4942570b4f09cc05a99d3` |
| Mainnet | Deploy tx | `0x06e9e5c15345e313e929807e45501715c9f42b0e16c8368e25a7170a145674b2` |

Previous ERC1155 deployments are superseded by `Medialane1155V2`:

- `0x035836932ba1d219e00b8e42cd9a433fb2b211a08edcaa8bae40232f335f777d` (`Medialane1155`, legacy architecture)
- `0x03aab04e806542cd88bfd0c5bb2a37334fd742d477a2e0f97af09aa4a36137ca` (2026-04-20 partial-fill redesign)
- `0x042005e9b85536072bfa260b95aa6aaef07f48e622031657384d2375195d7123` (broken deployment, no `OrderCreated` events)

## V2 Contract Model

V2 uses the same generic marketplace order model as the ERC721 contract.

### `OrderParameters`

| Field | Description |
|---|---|
| `offerer` | Seller / maker address |
| `offer` | ERC1155 asset being offered |
| `consideration` | ERC20 or NATIVE unit price and recipient |
| `start_time` | Fill start timestamp |
| `end_time` | Fill expiry timestamp (`0` = no expiry) |
| `salt` | Uniqueness salt |
| `nonce` | Seller nonce |

### `OfferItem`

| Field | Description |
|---|---|
| `item_type` | Must be `ERC1155` for v2 launch listings |
| `token` | ERC1155 collection address |
| `identifier_or_criteria` | ERC1155 token id |
| `start_amount` | Total listed quantity |
| `end_amount` | Must equal `start_amount` |

### `ConsiderationItem`

| Field | Description |
|---|---|
| `item_type` | `ERC20` or `NATIVE` |
| `token` | ERC20 token address, or zero for `NATIVE` |
| `identifier_or_criteria` | Must be zero |
| `start_amount` | Unit price |
| `end_amount` | Must equal `start_amount` |
| `recipient` | Primary proceeds recipient after royalties |

### `OrderFulfillment`

| Field | Description |
|---|---|
| `order_hash` | Hash of the order being filled |
| `fulfiller` | Buyer address |
| `quantity` | Units to purchase |
| `nonce` | Buyer nonce |

## Lifecycle

```text
Seller signs OrderParameters
  -> register_order(order)
Buyer signs OrderFulfillment
  -> fulfill_order(fulfillment_request)
Seller signs OrderCancellation
  -> cancel_order(cancel_request)
```

### Lifecycle states

| State | Meaning |
|---|---|
| `None` | Order hash has never been registered |
| `Created` | Order is live, including partially filled orders |
| `Filled` | `remaining_amount == 0` |
| `Cancelled` | Order was cancelled by the seller |

## Fulfillment Semantics

When a fill succeeds, the contract:

1. Validates caller, signature, quantity, and active time window.
2. Decrements `remaining_amount`.
3. Marks the order `Filled` only when no units remain.
4. Transfers ERC1155 units from seller to buyer.
5. Queries ERC-2981 royalties on the actual sale value for the fill.
6. Pays royalty first, then pays the remaining proceeds.

This preserves the important ERC1155 behavior while sharing the ERC721 order vocabulary.

## Security Properties

- Immutable contract surface. No owner, no role system, no upgrade hook.
- Offerer-only cancel.
- Fulfiller-only fill.
- Partial fills protected by pre-transfer state update.
- Replay protection through `NoncesComponent`.
- Registration allowed any time before expiry.
- Invalid `start_time >= end_time` windows rejected before storage when expiry is set.
- Unsupported trade shapes rejected before signature validation.
- Canonical payment fields enforced for ERC20 and NATIVE consideration.

## SNIP-12 Domain

```text
name:    "Medialane"
version: 2
chainId: Starknet chain id
```

## Interface

```cairo
fn register_order(ref self, order: Order);
fn fulfill_order(ref self, fulfillment_request: FulfillmentRequest);
fn cancel_order(ref self, cancel_request: CancelRequest);
fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails;
fn get_order_hash(self: @ContractState, parameters: OrderParameters, signer: ContractAddress) -> felt252;
fn get_native_token_address(self: @ContractState) -> ContractAddress;
fn nonces(self: @ContractState, account: ContractAddress) -> felt252;
```

## Events

### `OrderCreated`

- `order_hash`
- `offerer`

### `OrderFulfilled`

- `order_hash`
- `offerer`
- `fulfiller`
- `quantity`
- `remaining_amount`
- `sale_amount`
- `royalty_receiver`
- `royalty_amount`

### `OrderCancelled`

- `order_hash`
- `offerer`

## V2 Launch Scope

- Contract name: `Medialane1155V2`
- Interface name: `IMedialane1155V2`
- Domain name: `Medialane`
- Domain version: `2`
- Launch trade shapes:
  - `ERC1155` offer for `ERC20` consideration
  - `ERC1155` offer for `NATIVE` consideration
- One signed `ConsiderationItem` plus royalty overlay

## V2 Storage

- `offerer`
- `offer`
- `consideration`
- `start_time`
- `end_time`
- `order_status`
- `total_amount`
- `remaining_amount`

That change gives Medialane one marketplace architecture rather than two unrelated order models.

## Build And Test

```bash
scarb build
PATH="$HOME/.asdf/shims:$PATH" snforge test
```

Repository note:

- `.tool-versions` in this package currently expects `scarb 2.18.0`
- `Scarb.toml` is pinned to Starknet / Scarb-era dependencies for this package
- Current v2 verification: `40` tests passing
- Mainnet constructor verification: `get_native_token_address()` returns STRK

## Relationship To ERC721

The ERC721 marketplace is now treated as the architectural parent for the marketplace family.

That means ERC1155 v2 is implemented as:

- ERC721 marketplace vocabulary
- plus ERC1155 partial-fill settlement
- plus ERC-2981 royalty settlement

This is the core Medialane marketplace strategy going forward.

## References

- Contract code: [src/core/medialane.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo)
- Types: [src/core/types.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC1155/src/core/types.cairo)
- Tests: [tests/tests.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC1155/tests/tests.cairo)
- ERC1155 parity spec: [ERC1155_parity_architecture_spec_2026-04-26.md](/Users/kalamaha/dev/medialane-contracts/ERC1155_parity_architecture_spec_2026-04-26.md)
- ERC1155 implementation map: [ERC1155_v2_implementation_map_2026-04-26.md](/Users/kalamaha/dev/medialane-contracts/ERC1155_v2_implementation_map_2026-04-26.md)
