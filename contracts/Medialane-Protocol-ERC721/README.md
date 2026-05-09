# Medialane Protocol (ERC-721)

The core Seaport-inspired marketplace contract for Medialane on Starknet.

This contract is the current architectural baseline for the Medialane marketplace family:

- generic item vocabulary
- off-chain SNIP-12 signed orders
- on-chain registration, fulfillment, and cancellation
- immutable deployment model

It is the parent design for the upcoming ERC1155 v2 marketplace refactor.

## Status

- Production status: deployed on mainnet
- Contract family role: ERC721 marketplace baseline
- Upgradeability: immutable
- Admin model: no owner, no role system, no upgrade hook

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `Medialane` contract | `0x00f8ccaae0bc811c79605974cc1dab769b9cea8877f033f8e3c17f30457caba6` |
| Mainnet | Class hash | `0x03dff4f34b976207246207954263be9a28b51390321702443291088dcdf4b2e6` |
| Mainnet | Native token (STRK) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |
| Mainnet | Declare tx | `0x052d5efd6ae351630adbcc57a37ecf429d58072640be96f9b6e50b29c76ca551` |
| Mainnet | Deploy tx | `0x00b7bf96fe2a9c533c16c1516fcc30820369afdd05b9933ed8c2558e6034bf67` |

## Marketplace Model

The contract uses a generic order vocabulary rather than a one-off ERC721 listing schema.

### Core types

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

This is the part of the current system we want to preserve across the Medialane marketplace family.

## Order Lifecycle

```text
Offerer signs OrderParameters off-chain
  -> register_order(order)
  -> fulfill_order(fulfillment_request)
  -> cancel_order(cancel_request)
```

### Lifecycle states

| State | Meaning |
|---|---|
| `None` | Order hash has never been registered |
| `Created` | Order is live |
| `Filled` | Order has been fulfilled |
| `Cancelled` | Order was cancelled by the offerer |

## Signed Data

### `OrderParameters`

| Field | Description |
|---|---|
| `offerer` | Seller / maker address |
| `offer` | Asset being offered |
| `consideration` | Asset expected in exchange |
| `start_time` | Order becomes fillable at this timestamp |
| `end_time` | Order expires at this timestamp (`0` = no expiry) |
| `salt` | Uniqueness salt |
| `nonce` | Offerer's current account nonce |

### `OrderFulfillment`

| Field | Description |
|---|---|
| `order_hash` | Hash of the order being filled |
| `fulfiller` | Address allowed to submit fulfillment |
| `nonce` | Fulfiller nonce |

### `OrderCancellation`

| Field | Description |
|---|---|
| `order_hash` | Hash of the order being cancelled |
| `offerer` | Original offerer |
| `nonce` | Offerer nonce |

## Security Properties

- Immutable contract surface. No `upgrade()`, no access control, no admin dependency after deployment.
- Offerer-only cancel. Cancellation signatures must come from the original offerer.
- Fulfiller-only fill. The caller must match the signed `fulfiller`.
- Replay protection. `NoncesComponent` consumes a nonce on each register, fulfill, and cancel action.
- Fixed-price only. `start_amount` must equal `end_amount` on both offer and consideration.
- CEI sequencing. Order status is written before external transfers.

## Current Architectural Notes

This contract remains the right baseline for ERC1155 v2, but it should be treated as a strong draft rather than a final shared core.

The Medialane audit work identified a few improvements we want to carry forward into future versions:

- Registration-time validation should be stricter.
  Current code now validates item types, fixed-price shape, token addresses, ignored identifiers, and consideration recipient at registration.
- Time-window validation should be improved.
  Orders with invalid future windows are rejected before storage, and orders may be registered after `start_time` as long as they have not expired.
- Supported trade shapes should be explicit.
  The generic type system is broader than the currently tested product surface.
- Named errors should replace repeated inline string literals.
- Test coverage should grow from a single happy-path family into a fuller behavior matrix.

Those improvements matter directly for the ERC1155 v2 design.

## SNIP-12 Domain

```text
name:    "Medialane"
version: 1
chainId: Starknet chain id
```

Type hashes are computed in [src/core/utils.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC721/src/core/utils.cairo).

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

## Item Transfer Semantics

| ItemType | Transfer path | Notes |
|---|---|---|
| `NATIVE` | `IERC20.transfer_from` on stored STRK address | `token` and `identifier_or_criteria` must be zero |
| `ERC20` | `IERC20.transfer_from` | token must be non-zero, `identifier_or_criteria` must be zero |
| `ERC721` | `IERC721.transfer_from` | amount must equal `1` |
| `ERC1155` | `IERC1155.safe_transfer_from` | amount must be positive |

## Events

### `OrderCreated`

- `order_hash`
- `offerer`

### `OrderFulfilled`

- `order_hash`
- `offerer`
- `fulfiller`

### `OrderCancelled`

- `order_hash`
- `offerer`

The current event model is intentionally minimal. For future versions, especially ERC1155 v2, Medialane plans to extend non-indexed settlement detail where it helps indexers and payout analytics.

## Build And Test

```bash
scarb build
PATH="$HOME/.asdf/shims:$PATH" snforge test
```

Repository note:

- `.tool-versions` in this package currently expects `scarb 2.18.0`
- `Scarb.toml` depends on Starknet `2.18.0`

## Relationship To ERC1155

ERC1155 v2 is being redesigned to inherit this order vocabulary and signing model, while adding:

- partial fills
- ERC-2981 royalty settlement
- stricter registration validation
- clearer supported launch trade shapes

The goal is one Medialane marketplace architecture, not two unrelated marketplace contracts.

## References

- Contract code: [src/core/medialane.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC721/src/core/medialane.cairo)
- Types: [src/core/types.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC721/src/core/types.cairo)
- Tests: [tests/tests.cairo](/Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC721/tests/tests.cairo)
- Audit: [ERC721_architecture_audit_report_2026-04-26.md](/Users/kalamaha/dev/medialane-contracts/ERC721_architecture_audit_report_2026-04-26.md)
