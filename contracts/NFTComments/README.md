# NFTComments

An on-chain comment system for NFTs on Starknet. Comments are emitted as `CommentAdded` events and indexed by the Medialane backend — no comment content is stored in contract storage, keeping gas costs minimal.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `NFTComments` contract | `0x024f97eb5abe659fb650bf162b5fc16501f8f3863a7369901ce6099462e62799` |
| Mainnet | Class hash | `0x05d1d8762ef27818d94e30e07db88b7654d7c34cb68b3f5cd7129ba2e423c4c8` |

---

## How It Works

Any Starknet wallet can call `add_comment(nft_contract, token_id, content)`. The contract:

1. Validates inputs (non-zero contract, 1–1000 byte content).
2. Enforces a **60-second per-wallet rate limit per token** — keyed on `(nft_contract, token_id, caller)`.
3. Increments a global `total_comments` counter and assigns the next `comment_id`.
4. Emits `CommentAdded` with all fields as indexed keys.

No external calls are made to the NFT contract. The system is fully permissionless — any `nft_contract` address is accepted; the backend filters comments for non-existent token IDs off-chain.

## Interface

```cairo
fn add_comment(
    ref self: TContractState,
    nft_contract: ContractAddress,
    token_id: u256,
    content: ByteArray,  // 1–1000 bytes
);

fn comment_count(self: @TContractState) -> u64;
```

## Events

```cairo
struct CommentAdded {
    #[key] nft_contract: ContractAddress,
    #[key] token_id: u256,
    #[key] author: ContractAddress,
    #[key] comment_id: u64,
    content: ByteArray,
    timestamp: u64,
}
```

`comment_id` is a monotonically increasing global counter starting at 1. It provides a stable unique reference for each comment (e.g., for reporting/flagging in the backend).

## Rate Limit

The rate limit key is `(nft_contract, token_id, caller)`. A wallet must wait 60 seconds between comments **on the same token**. Comments on different tokens or from different wallets are independent.

## Security Properties

- **No external calls** — the contract makes no calls to `nft_contract` or any other address, eliminating all re-entrancy surfaces. Any address is accepted as `nft_contract`.
- **CEI order** — rate limit is read, checked, and written before emitting the event; no state mutation after the effects phase.
- **No on-chain storage of content** — content lives in events only; storage gas is O(1) per caller per token.
- **Immutable** — no owner, no admin, no upgrade function. Zero external dependencies (pure `starknet = "2.18.0"`). Past `CommentAdded` events are permanent and uncensorable.

## Build & Test

```bash
# Requires scarb 2.18.0+ and snforge 0.59.0
scarb build
PATH="$HOME/.asdf/shims:$PATH" snforge test
```

Tests cover: input validation, rate limit boundaries (59s rejected / 60s allowed), per-token / per-nft-contract / per-caller independence, `comment_count` view, `comment_id` in emitted events.

## Deploy Notes

Constructor takes no arguments — the contract is fully permissionless with no owner or configuration.
