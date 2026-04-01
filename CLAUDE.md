# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Overview

Cairo smart contracts for the Medialane platform on Starknet mainnet.

## Toolchain

- **sncast** (Starknet Foundry) — deploy, declare, invoke, call. Version: 0.55.0+
- **scarb** — Cairo build tool
- **snfoundry.toml** — named network + account profiles

```bash
# Build
scarb build

# Declare (publish class)
sncast --profile nftcomments-mainnet declare --contract-name <ContractName>

# Invoke (call a write method)
sncast --profile nftcomments-mainnet invoke \
  --contract-address <address> \
  --function <fn_name> \
  --calldata <felts>
```

**Important sncast 0.55.0 notes:**
- `--fee-token` flag is NOT supported — omit it entirely (fee paid in ETH by default)
- Account name in snfoundry.toml: `nftcomments-deployer` (not `deployer`)
- If upgrade fails with "Caller is not the owner" — contract owner may be a different wallet than `nftcomments-deployer`. Use Starkscan "Write Contract" UI as the owner wallet instead.

---

## Contracts

### NFTComments (`contracts/NFTComments/`)

Stores on-chain NFT comments as events. No comment storage on-chain — comments live in `CommentAdded` events, indexed by the backend.

- **Mainnet address**: `0x070edbfa68a870e8a69736db58906391dcd8fcf848ac80a72ac1bf9192d8e232`
- **Class hash (after 2026-03-22 upgrade)**: `0x1edbebcd184c3ea65c19f59f2cbc11ef8b3a2883b4fe97db1caf0b29c6ea0dd`
- **Owner**: `0x05f9f8d300601199297b7ecd92928e1444a2556aa84c8544b8b513d2a18a65a2` (personal wallet)
- **Upgrade tx**: `0x1aaeebe7d63e3090b725393a4eb09375f05063440e0f97ce0ce6b659a60329f`
- **Deployer account**: `nftcomments-deployer` (in `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`)

**Key features:**
- `add_comment(nft_contract, token_id, content)` — emits `CommentAdded` event
- 60s per-address rate limit: `last_comment_time: Map<ContractAddress, u64>` + `assert!(now >= last_time + 60_u64, ...)`
- Max comment length: 1000 bytes (enforced on-chain)
- Content stored as Cairo `ByteArray`
- Upgradeable (OZ UpgradeableComponent) + Ownable (OZ OwnableComponent)

**`CommentAdded` event:**
```cairo
struct CommentAdded {
    #[key] nft_contract: ContractAddress,
    #[key] token_id: u256,
    #[key] author: ContractAddress,
    content: ByteArray,
    timestamp: u64,
}
```

**Upgrade workflow:**
1. `scarb build` in `contracts/NFTComments/`
2. `sncast --profile nftcomments-mainnet declare --contract-name NFTComments` → get new class hash
3. Invoke `upgrade(new_class_hash)` as the **owner wallet** (not `nftcomments-deployer` unless they match)
4. If ownership mismatch: use Starkscan "Write Contract" → connect owner wallet → call `upgrade`

**Storage import pitfall**: `Map<K, V>` read/write requires explicit trait imports:
```cairo
use starknet::storage::{StorageMapReadAccess, StorageMapWriteAccess};
```

### Pop-Protocol (`contracts/Pop-Protocol/`)

Soulbound proof-of-participation credentials. Factory + collection pattern: platform deploys one POPFactory; organizers call `create_collection()` to deploy per-event POPCollection instances.

- **POPFactory address**: `0x00b32c34b427d8f346b5843ada6a37bd3368d879fc752cd52b68a87287f60111`
- **POPFactory class hash**: `0x0785b924853826513482486707bb3acee462e5a465a0c917267aad4f0ecc3bae`
- **POPCollection class hash**: `0x077c421686f10851872561953ea16898d933364b7f8937a5d7e2b1ba0a36263f`
- **Deploy block**: `8328934`
- **Admin (DEFAULT_ADMIN_ROLE + ORGANIZER_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Deploy tx**: `0x0093f80504b888511bef39f7a5cc20e0c8b99ebdff16908d937efe9a38d06799`
- **Deployer account**: `mediolanoprotocol` (in `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`)
- **snfoundry.toml profile**: `pop-mainnet` (in `contracts/Pop-Protocol/snfoundry.toml`)

**Build + declare workflow:**
```bash
# Full PATH required (scarb + cargo + universal-sierra-compiler all from kalamaha user)
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile pop-mainnet declare --contract-name POPCollection
PATH="..." sncast --profile pop-mainnet declare --contract-name POPFactory
PATH="..." sncast --profile pop-mainnet deploy \
  --class-hash <factory_class_hash> \
  --arguments '<admin>, <pop_collection_class_hash>'
```

**Upgrading POPCollection class (new features):**
1. Modify contract, `scarb build`, declare new POPCollection → new class hash
2. Call `set_pop_collection_class_hash(new_class_hash)` on the factory as admin
3. All new `create_collection()` calls will deploy the updated class
4. Existing deployed collections are unaffected (immutable once deployed)

**Backend env vars:**
```
POP_FACTORY_ADDRESS=0x00b32c34b427d8f346b5843ada6a37bd3368d879fc752cd52b68a87287f60111
POP_START_BLOCK=8328934
```

**Key events indexed by backend:**
- `POPFactory::CollectionCreated` → registers Collection with `source: POP_PROTOCOL`
- `POPCollection::AllowlistUpdated` → syncs PopAllowlist table (slow-poll per collection)

### Medialane-Protocol (`contracts/Medialane-Protocol/`)

Core marketplace and collection registry contracts. Not actively modified — see medialane-backend CLAUDE.md for contract addresses and ABI notes.

---

## Network Config (`snfoundry.toml`)

```toml
[sncast.nftcomments-mainnet]
account = "nftcomments-deployer"
accounts-file = "/Users/kalamaha/.starknet_accounts/starknet_open_zeppelin_accounts.json"
network = "mainnet"

[sncast.pop-mainnet]
account = "mediolanoprotocol"
accounts-file = "/Users/medialane/.starknet_accounts/starknet_open_zeppelin_accounts.json"
url = "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/tOTwt1ug3YNOsaPjinDvS"
wait-params = { timeout = 300, retry-interval = 10 }
```

**Accounts file location**: The `starknet_open_zeppelin_accounts.json` was originally at `/Users/kalamaha/.starknet_accounts/` (old username) and has been copied to `/Users/medialane/.starknet_accounts/`. Both paths work.

Add new profiles here for additional contracts/accounts.
