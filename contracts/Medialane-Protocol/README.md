# Medialane Protocol

The core ERC-721 marketplace contract for Medialane on Starknet. Sellers sign `OrderParameters` off-chain (SNIP-12), register orders on-chain, and buyers fulfill them in a single transaction with automatic ERC-2981 royalty distribution.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `Medialane` v2 (current) | `0x0234f4e8838801ebf01d7f4166d42aed9a55bc67c1301162decf9e2040e05f16` |
| Mainnet | `Medialane` v1 (deprecated) | `0x04299b51289aa700de4ce19cc77bcea8430bfd1aef04193efab09d60a3a7ee0f` |
| Mainnet | Manager (`DEFAULT_ADMIN_ROLE`) | `0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b` |
| Mainnet | Native token (STRK) | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |

---

## Order Lifecycle

```
Offerer signs OrderParameters (SNIP-12 typed data)
  → register_order(order)       — stores order hash, status = Created
  → fulfill_order(fulfillment)  — transfers NFT to buyer, ERC-20 to seller (minus royalty)
  → cancel_order(cancellation)  — only the original offerer can cancel
```

## Order Parameters

| Field | Description |
|---|---|
| `offerer` | Seller's address |
| `nft_contract` | ERC-721 contract address |
| `token_id` | Token to sell |
| `payment_token` | ERC-20 for payment (or zero for native STRK) |
| `start_amount` | Listing price (must equal `end_amount` — fixed price only) |
| `end_amount` | Same as `start_amount` |
| `start_time` | Unix timestamp when listing becomes active |
| `end_time` | Unix timestamp when listing expires |
| `salt` | Nonce / uniqueness salt |

## Security Properties (v2 fixes)

- **Offerer-only cancel** — `cancel_order` verifies `caller == order.offerer` via the signed `OrderCancellation` struct.
- **Fulfiller-only fill** — `fulfill_order` verifies `caller == fulfillment.fulfiller`.
- **Fixed price** — `end_amount` must equal `start_amount`; partial fills and Dutch auctions are not supported.
- **Immediate orders** — orders with `start_time == now` are accepted at registration.
- **CEI order** — order status is set to `Filled` before the ERC-721 `safe_transfer_from` call.
- **Input validation** — zero-address checks on `offerer`, `nft_contract`, and `payment_token`; zero-amount check on `start_amount`.

## Royalties

If the NFT contract implements ERC-2981 (`royaltyInfo`), the royalty amount is deducted from the payment and sent directly to the royalty receiver before the remainder goes to the seller.

## SNIP-12 Domain

```
name:    "Medialane"
version: 1
chainId: mainnet
```

The `ORDER_TYPE_HASH` and `FULFILLMENT_TYPE_HASH` are computed from the Starknet typed-data spec. See `src/core/utils.cairo` for the full definitions.

## Build & Test

```bash
scarb build
SCARB_IGNORE_CAIRO_VERSION=true snforge test
```

Tests use pre-computed SNIP-12 signatures (see `tests/tests.cairo` header) computed with StarknetJS. Update signatures if domain or type strings change.
