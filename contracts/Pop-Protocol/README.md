# Pop Protocol

Soulbound proof-of-participation (POP) credentials on Starknet. Organizers deploy `POPFactory` once; event hosts call `create_collection()` to spin up `POPCollection` instances — non-transferable ERC-721 badges for on-chain proof that a wallet attended or participated in an event.

## Deployments

| Network | Item | Address |
|---|---|---|
| Mainnet | `POPFactory` | `0x00b32c34b427d8f346b5843ada6a37bd3368d879fc752cd52b68a87287f60111` |
| Mainnet | Admin (`DEFAULT_ADMIN_ROLE` + `ORGANIZER_ROLE`) | `0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b` |
| Mainnet | Deploy block | `8328934` |

## Architecture

```
POPFactory (singleton)
  └─ create_collection() → deploys a POPCollection via deploy_syscall
       POPCollection (one per event, soulbound ERC-721)
         ├─ mint(recipient)         — ORGANIZER_ROLE only
         ├─ admin_mint(recipient, quantity)  — batch mint, no supply cap
         └─ allowlist / conditions  — optional gates (same as Collection-Drop)
```

## Soulbound Behaviour

`POPCollection` overrides ERC-721 transfer hooks to revert on any `transfer_from` or `safe_transfer_from` call. Tokens are permanently bound to the recipient address at mint time. `approve` and `set_approval_for_all` are similarly blocked.

## `admin_mint` — Unlimited by Design

`admin_mint(recipient, quantity)` bypasses all claim conditions and has **no supply cap**. This is intentional: organizers need to be able to gift credentials to wallets that couldn't claim in time, or batch-distribute to a long list. The factory admin (Medialane platform) is the only address with this permission.

## Roles

| Role | Holder | Permissions |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Platform admin | Emergency pause, set new POPCollection class |
| `ORGANIZER_ROLE` | Platform admin + event host | `admin_mint`, allowlist, conditions |

## Build & Test

```bash
scarb build
SCARB_IGNORE_CAIRO_VERSION=true snforge test
```

## Upgrade Workflow (POPCollection class)

1. Modify `pop_collection.cairo` and `scarb build`
2. Declare: `sncast --profile pop-mainnet declare --contract-name POPCollection`
3. Update factory: `sncast --profile pop-mainnet invoke --contract-address <factory> --function set_pop_collection_class_hash --calldata <new_class_hash>`

Existing collections are immutable — only future `create_collection()` calls deploy the new class.
