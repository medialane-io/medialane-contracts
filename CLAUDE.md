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

### Collection-Drop (`contracts/Collection-Drop/`)

Multi-tenant timed NFT drop service. Factory + collection pattern: platform deploys one DropFactory; organizers call `create_drop()` to deploy per-drop DropCollection instances (transferable ERC-721).

- **DropFactory address**: `0x03587f42e29daee1b193f6cf83bf8627908ed6632d0d83fcb26225c50547d800`
- **DropFactory class hash**: `0x072b3f26370b2a125732165dd07491e808a0de67ab9e0f95e5ab9013b15a3383`
- **DropCollection class hash**: `0x00092e72cdb63067521e803aaf7d4101c3e3ce026ae6bc045ec4228027e58282`
- **Admin (DEFAULT_ADMIN_ROLE + ORGANIZER_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Deploy tx**: `0x058fb5762389cd23e6e7e36089bff5dc7546c03f7fd34673504564fc34614696`
- **Deployer account**: `mediolanoprotocol` (in `~/.starknet_accounts/starknet_open_zeppelin_accounts.json`)
- **snfoundry.toml profile**: `drop-mainnet` (in `contracts/Collection-Drop/snfoundry.toml`)

**Build + declare workflow:**
```bash
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile drop-mainnet declare --contract-name DropCollection
PATH="..." sncast --profile drop-mainnet declare --contract-name DropFactory
PATH="..." sncast --profile drop-mainnet deploy \
  --class-hash <factory_class_hash> \
  --arguments '<admin>, <drop_collection_class_hash>'
```

**Gas note**: DropCollection declaration costs ~59 STRK (large contract). The `mediolanoprotocol` account needs ~200+ STRK balance before declaring — sncast sets max bounds at ~2.25x estimated fee. If declare fails with "Resources bounds exceed balance", top up the account.

**Upgrading DropCollection class (new features):**
1. Modify contract, `scarb build`, declare new DropCollection → new class hash
2. Call `set_drop_collection_class_hash(new_class_hash)` on the factory as admin
3. All new `create_drop()` calls will deploy the updated class

**Test runner:**
```bash
PATH="...snforge 0.48.1 bin..." snforge test
# Uses snforge_std_deprecated = "0.48.1" in Scarb.toml (required for Scarb < 2.12.0)
```

**Backend env vars (to add):**
```
DROP_FACTORY_ADDRESS=0x03587f42e29daee1b193f6cf83bf8627908ed6632d0d83fcb26225c50547d800
DROP_START_BLOCK=8341335
```

**Key events indexed by backend:**
- `DropFactory::DropCreated` → registers Collection with `source: COLLECTION_DROP`
- `DropCollection::TokensClaimed` → updates mint counts

---

### Medialane-Protocol (`contracts/Medialane-Protocol/`)

Core marketplace contracts (order registration, fulfillment, cancellation). Audited and redeployed 2026-04-05.

- **Contract address**: `0x0234f4e8838801ebf01d7f4166d42aed9a55bc67c1301162decf9e2040e05f16`
- **Class hash**: `0x06e45fbc001580e52948d528e236002cd35a226b557a81400e0fb77ddbaa7727`
- **Deploy tx**: `0x0272a9d748dc4a589f19c1445474ff6833f50bc6cb2c09a20295fcf0e4ccbc31`
- **Manager (DEFAULT_ADMIN_ROLE)**: `mediolanoprotocol` (`0x4cc6df27c62aa4bf3dcfc8fe8c02a8473bd08a96ee7013c06fb8f4f847d5d7b`)
- **Native token**: STRK (`0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`)
- **snfoundry.toml profile**: `medialane-mainnet` (in `contracts/Medialane-Protocol/snfoundry.toml`)

**Previous deployment**: `0x04299b51289aa700de4ce19cc77bcea8430bfd1aef04193efab09d60a3a7ee0f` (superseded — security fixes applied)

**Key security fixes in this deployment (2026-04-05):**
- M-03: `cancel_order` now verifies signer is the order's offerer
- M-02: `fulfill_order` now verifies caller == fulfiller (prevents front-running)
- M-04: `end_amount` must equal `start_amount` (fixed price enforced)
- M-01: Immediate-validity orders (`start_time == now`) now registerable
- M-05: CEI pattern — order marked Filled before ERC-1155 external call
- M-06/07/08/09: input validation hardened throughout

**Build + declare + deploy workflow:**
```bash
PATH="/Users/kalamaha/.cargo/bin:/Users/kalamaha/.asdf/installs/scarb/2.11.4/bin:/Users/kalamaha/.local/bin:$PATH" \
UNIVERSAL_SIERRA_COMPILER=/Users/kalamaha/.local/bin/universal-sierra-compiler \
  scarb build

PATH="..." sncast --profile medialane-mainnet declare --contract-name Medialane
PATH="..." sncast --profile medialane-mainnet deploy \
  --class-hash <new_class_hash> \
  --arguments '<manager_address>, <native_token_address>'
```

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

[sncast.drop-mainnet]
account = "mediolanoprotocol"
accounts-file = "/Users/medialane/.starknet_accounts/starknet_open_zeppelin_accounts.json"
url = "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/tOTwt1ug3YNOsaPjinDvS"
wait-params = { timeout = 300, retry-interval = 10 }
```

**Accounts file location**: The `starknet_open_zeppelin_accounts.json` was originally at `/Users/kalamaha/.starknet_accounts/` (old username) and has been copied to `/Users/medialane/.starknet_accounts/`. Both paths work.

Add new profiles here for additional contracts/accounts.

---

### MDLN Token (`contracts/MDLN/`) — Ethereum L1 (Solidity)

Governance and utility token for the Medialane DAO. Deployed on Ethereum mainnet; bridged to Starknet via StarkGate.

- **Stack**: Solidity 0.8.24 + OpenZeppelin v5 + Hardhat
- **Token contract**: `medialane.sol` → `MedialaneToken`
- **Vesting contract**: `MDLNVesting.sol`
- **Status**: Deployed and verified on Ethereum mainnet (2026-04-07)
- **MDLN Token (mainnet)**: `0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15`
- **MDLNVesting (mainnet)**: `0x912f61d5e6db656ec1a7be8db8957c5f1e345d58`
- **Gnosis Safe (DAO treasury)**: `0xA7603783edD8ee6FF4B085f90Af53341282d244C` (Ethereum mainnet)
- **Sepolia MDLN**: `0x3c64605Bd08A49032FaF44c4C71d5549cAee09Ef`
- **Sepolia Vesting**: `0x77566634d13Fdf6ae292270eeB26d50De74faafA`

**Tokenomics:**
- Supply: 21,000,000 MDLN (fixed, no minting)
- 100% minted to Gnosis Safe at deploy
- Safe transfers 18.9M to `MDLNVesting` → unlocks 2.1M/year for 9 years
- Safe retains 2.1M as operational runway
- No team allocation, no VCs — community enters via LP
- Initial LP seeding: Starknet Foundation grant (in progress)

**Key design:**
- `ERC20Votes` — native Snapshot + future on-chain Governor support
- `ERC20Permit` — gasless approvals, required by StarkGate
- `ERC20Burnable` — fee-burn mechanics via DAO vote
- Fully immutable — no owner, no admin, no upgrade
- Custom errors: `MDLN_ZeroAddress`, `MDLN_TreasuryNotContract`
- Treasury must be a contract (rejects EOA deploy)

**Vesting contract (`MDLNVesting`):**
- Holds 18.9M MDLN, releases 2.1M/year to Gnosis Safe
- Permissionless `release()` — anyone can trigger once tranche is due
- Catch-up safe — multiple elapsed tranches released in one call
- Views: `tranchesDue()`, `nextReleaseAt()`, `lockedBalance()`

**Build & test (requires Node 22 LTS):**
```bash
# Install Node 22 via Homebrew if needed:
# brew install node@22

cd contracts/MDLN
cp .env.example .env   # fill DEPLOYER_PRIVATE_KEY, ETH_RPC_URL, ETHERSCAN_API_KEY
npm install
npx hardhat test

# Deploy to Sepolia (testnet)
npx hardhat run scripts/deploy.js --network sepolia

# Deploy to mainnet
npx hardhat run scripts/deploy.js --network mainnet
npx hardhat verify --network mainnet <token_address> "0xA7603783edD8ee6FF4B085f90Af53341282d244C"
npx hardhat verify --network mainnet <vesting_address> "<token_address>" "0xA7603783edD8ee6FF4B085f90Af53341282d244C"
```

**Post-deploy checklist:**
1. From Gnosis Safe: transfer 18,900,000 MDLN to vesting contract
2. Verify both contracts on Etherscan
3. Register MDLN on StarkGate for L2 bridging
4. Create Snapshot space pointing at MDLN token address
5. Seed Uniswap LP (after Starknet Foundation grant lands)
