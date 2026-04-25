# Medialane Protocol (ERC-721)

The core ERC-721 marketplace contract for Medialane on Starknet. Sellers sign `OrderParameters` off-chain (SNIP-12 typed data), register orders on-chain, and buyers fulfill them in a single transaction.

**Immutable** — no owner, no admin role, no upgrade function. Deployed once, permanent.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `Medialane` contract | `0x004387e58d469f19332dd5d20846b10339ddc49ef208025ec7d5bef294a8daf3` |
| Mainnet | Class hash | `0x079225381275ff71a723f560419bbe4e69dad324622226fc6593298577b824bc` |
| Mainnet | Native token (STRK) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |

---

## Order Lifecycle

```
Offerer signs OrderParameters (SNIP-12 typed data, off-chain)
  → register_order(order)       — stores order hash, status = Created
  → fulfill_order(fulfillment)  — transfers NFT to buyer, ERC-20 to seller
  → cancel_order(cancellation)  — only the original offerer can cancel
```

## Order Parameters

| Field | Description |
|---|---|
| `offerer` | Seller's address |
| `offer.item_type` | `ERC721` (or `ERC1155` / `NATIVE` / `ERC20`) |
| `offer.token` | NFT contract address |
| `offer.identifier_or_criteria` | Token ID |
| `offer.start_amount` | Must equal `end_amount` (fixed price only) |
| `consideration.item_type` | `ERC20` or `NATIVE` (payment token type) |
| `consideration.token` | Payment token contract (0 for NATIVE/STRK) |
| `consideration.start_amount` | Price in payment token |
| `consideration.recipient` | Who receives the payment (usually the offerer) |
| `start_time` | Unix timestamp when listing becomes active |
| `end_time` | Unix timestamp when listing expires (0 = no expiry) |
| `salt` | Uniqueness salt |
| `nonce` | Offerer's current account nonce |

## Security Properties

- **Immutable** — no `upgrade()`, no `DEFAULT_ADMIN_ROLE`, no `AccessControl`. The constructor takes only `native_token_address` (STRK). Zero external admin dependencies.
- **Offerer-only cancel** — `cancel_order` verifies `cancelation.offerer == order.offerer`. The signed cancellation struct prevents any other party from cancelling.
- **Fulfiller-only fill** — `fulfill_order` verifies `caller == fulfillment.fulfiller`. Prevents mempool front-running.
- **Fixed price** — `end_amount` must equal `start_amount` at registration. Dutch auctions are not supported.
- **CEI order** — order status is set to `Filled` before the external token transfers.
- **Replay protection** — `NoncesComponent` ensures each signed message can only be used once per account.
- **Item type validation** — offer and consideration item types are validated at registration (not only at fulfillment).
- **Zero-address checks** — offerer, token contracts, and consideration recipient must be non-zero.

## SNIP-12 Domain

```
name:    "Medialane"
version: 1
chainId: (contract's chain)
```

All three type hashes (`ORDER_PARAMETERS_TYPE_HASH`, `FULFILLMENT_TYPE_HASH`, `CANCELATION_TYPE_HASH`, `OFFER_ITEM_TYPE_HASH`, `CONSIDERATION_ITEM_TYPE_HASH`) are computed via `selector!()` in `src/core/utils.cairo` — not hardcoded hex literals.

## Interface

```cairo
fn register_order(ref self, order: Order);
fn fulfill_order(ref self, fulfillment_request: FulfillmentRequest);
fn cancel_order(ref self, cancel_request: CancelRequest);
fn get_order_details(self: @, order_hash: felt252) -> OrderDetails;
fn get_order_hash(self: @, parameters: OrderParameters, signer: ContractAddress) -> felt252;
fn get_native_token_address(self: @) -> ContractAddress;
fn nonces(self: @, account: ContractAddress) -> felt252;
```

## Item Types

| ItemType | Transfers via | Notes |
|---|---|---|
| `NATIVE` | `IERC20.transfer_from` on stored STRK address | `offer.token` field is ignored |
| `ERC20` | `IERC20.transfer_from` | token must be non-zero |
| `ERC721` | `IERC721.transfer_from` | amount must be exactly 1 |
| `ERC1155` | `IERC1155.safe_transfer_from` | any amount ≥ 1 |

## Build & Test

```bash
# Requires scarb 2.18.0 and snforge 0.59.0
scarb build
PATH="$HOME/.asdf/shims:$PATH" snforge test
```

Tests cover: register, fulfill, cancel, invalid signatures, expired orders, not-yet-valid orders, double-fill prevention, cancel-after-fill prevention. Pre-computed SNIP-12 signatures are used (see test header comment for regeneration instructions).

## Deploy Notes

Constructor takes a single argument: `native_token_address` (STRK on mainnet: `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`).

When using `sncast`, always pass `--nonce` explicitly if a prior transaction failed — sncast increments its local nonce cache on submission regardless of whether the transaction landed on-chain.
