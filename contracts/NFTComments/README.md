# NFTComments

An on-chain comment system for NFTs on Starknet. Comments are emitted as `CommentAdded` events and indexed by the Medialane backend — no comment content is stored in contract storage, keeping gas costs minimal.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `NFTComments` | `0x070edbfa68a870e8a69736db58906391dcd8fcf848ac80a72ac1bf9192d8e232` |
| Mainnet | Owner | `0x05f9f8d300601199297b7ecd92928e1444a2556aa84c8544b8b513d2a18a65a2` |

---

## How It Works

Any Starknet wallet can call `add_comment(nft_contract, token_id, content)`. The contract:

1. Validates inputs (non-zero contract, 1–1000 byte content).
2. Detects whether the NFT is ERC-721 via SRC5 `supports_interface`. If yes, calls `owner_of(token_id)` to verify the token exists (panics if token does not exist).
3. Enforces a **60-second per-wallet rate limit per token** — preventing spam across all token IDs simultaneously.
4. Emits `CommentAdded` with `nft_contract`, `token_id`, `author`, `content`, and `timestamp` as indexed keys.

## Interface

```cairo
fn add_comment(
    ref self: TContractState,
    nft_contract: ContractAddress,
    token_id: u256,
    content: ByteArray,  // max 1000 bytes
);
```

## Events

```cairo
struct CommentAdded {
    #[key] nft_contract: ContractAddress,
    #[key] token_id: u256,
    #[key] author: ContractAddress,
    content: ByteArray,
    timestamp: u64,
}
```

## Rate Limit

The rate limit key is `(nft_contract, token_id, caller)`. A wallet must wait 60 seconds between comments **on the same token**. Comments on different tokens are independent.

## ERC-1155 Support

ERC-1155 contracts do not implement `owner_of`. The contract uses SRC5 `supports_interface(IERC721_ID)` to detect ERC-721 contracts and skips the ownership check for all others — including ERC-1155. Off-chain filtering removes comments on non-existent ERC-1155 token IDs.

## Security Properties

- **No on-chain storage of content** — content lives in events only; storage gas is O(1) per caller per token.
- **CEI order** — rate limit is read then written before emitting the event; no reentrancy surface.
- **Immutable** — contract owner can upgrade via `UpgradeableComponent`, but no privileged functions can censor or delete comments.

## Build & Test

```bash
# Requires scarb 2.18.0+ and snforge 0.59.0
scarb build
snforge test
```

## Upgrade Workflow

1. Modify the contract and rebuild: `scarb build`
2. Declare the new class: `sncast --profile nftcomments-mainnet declare --contract-name NFTComments`
3. Call `upgrade(new_class_hash)` as the contract owner via Voyager "Write Contract" or sncast invoke.
