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

- **No external calls** — the contract makes no calls to `nft_contract` or any other address, eliminating all re-entrancy surfaces. Any compliant or non-compliant NFT contract is accepted.
- **CEI order** — rate limit is read, checked, and written before emitting the event; no state mutation after the effects phase.
- **No on-chain storage of content** — content lives in events only; storage gas is O(1) per caller per token.
- **Immutable comment history** — events are permanent on Starknet; the owner can upgrade contract logic but cannot delete or censor past `CommentAdded` events.

## Build & Test

```bash
# Requires scarb 2.18.0+ and snforge 0.59.0
scarb build
PATH="$HOME/.asdf/shims:$PATH" snforge test
```

Tests cover: input validation, rate limit boundaries (59s rejected / 60s allowed), per-token / per-nft-contract / per-caller independence, `comment_count` view, `comment_id` in emitted events.

## Upgrade Workflow

1. Modify the contract and rebuild: `scarb build`
2. Declare the new class: `sncast --profile medialane-deployer declare --contract-name NFTComments`
3. Call `upgrade(new_class_hash)` as the contract owner via Voyager "Write Contract" or:
   ```bash
   sncast --profile medialane-deployer invoke \
     --contract-address 0x070edbfa68a870e8a69736db58906391dcd8fcf848ac80a72ac1bf9192d8e232 \
     --function upgrade \
     --calldata <new_class_hash>
   ```
