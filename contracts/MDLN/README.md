# MDLN Token Contracts

Medialane governance token — Ethereum L1. Deployed mainnet 2026-04-07. Bridged to Starknet via StarkGate 2026-04-08.

---

## Deployed Addresses

### Ethereum Mainnet

| Contract | Address |
|---|---|
| MDLN Token | `0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15` |
| MDLNVesting | `0x912f61d5e6db656ec1a7be8db8957c5f1e345d58` |
| DAO Treasury (Gnosis Safe) | `0xA7603783edD8ee6FF4B085f90Af53341282d244C` |

### Starknet Mainnet (via StarkGate)

| Contract | Address |
|---|---|
| MDLN L2 Token | `0x6730d6a357690cebffad800219e9630e15b6f44d35526e0fc9ee52bdf7418e8` |
| StarkGate L1 Bridge | `0xF5b6Ee2CAEb6769659f6C091D209DfdCaF3F69Eb` |
| StarkGate Manager | `0x0c5aE94f8939182F2D06097025324D1E537d5B60` |
| StarkGate L2 Bridge | `0x0616757a151c21f9be8775098d591c2807316d992bbc3bb1a5c1821630589256` |

### Ethereum Sepolia (testnet)

| Contract | Address |
|---|---|
| MDLN Token | `0x3c64605Bd08A49032FaF44c4C71d5549cAee09Ef` |
| MDLNVesting | `0x77566634d13Fdf6ae292270eeB26d50De74faafA` |

---

## Tokenomics

| Tranche | Tokens | % | Mechanism |
|---|---|---|---|
| Operational runway | 2,100,000 | 10% | Immediately in Gnosis Safe |
| Vested treasury | 18,900,000 | 90% | MDLNVesting — 2.1M/year × 9 years |
| VC / team allocation | 0 | 0% | — |

- **Supply**: 21,000,000 MDLN (fixed, immutable — no minting function)
- **Standards**: ERC20Votes + ERC20Permit + ERC20Burnable (OpenZeppelin v5)
- **Governance**: Snapshot gasless voting at [medialane.eth](https://snapshot.org/#/s:medialane.eth)

---

## Stack

- Solidity 0.8.24
- OpenZeppelin v5
- Hardhat + hardhat-toolbox
- Node 22 LTS

---

## Setup

```bash
cd contracts/MDLN
cp .env.example .env
# Fill: DEPLOYER_PRIVATE_KEY, ETH_RPC_URL, ETH_SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
npm install
```

---

## Scripts

### Deploy

```bash
# Sepolia testnet
npx hardhat run scripts/deploy.js --network sepolia

# Mainnet
npx hardhat run scripts/deploy.js --network mainnet
```

### Enroll MDLN on StarkGate (one-time, already done on mainnet)

```bash
npx hardhat run scripts/enroll-starkgate.js --network mainnet
```

Estimates enrollment fee, calls `enrollTokenBridge(MDLN)` on the StarkGate manager, waits for L1→L2 message confirmation.

**Key detail**: `estimateEnrollmentFeeWei()` lives on the **bridge** (`0xF5b6Ee...`), not the manager. `enrollTokenBridge()` lives on the **manager** (`0x0c5aE94f...`).

### Bridge tokens L1 → L2

```bash
L2_RECIPIENT=0x<starknet_address> \
BRIDGE_AMOUNT=<amount> \
npx hardhat run scripts/bridge-to-starknet.js --network mainnet
```

Approves the bridge, calls `deposit()`, waits for confirmation. Tokens arrive on Starknet in ~5–15 minutes.

---

## Vesting

`MDLNVesting` is a trustless time-lock. Anyone can call `release()` once a tranche is due:

```bash
# Check vesting status
npx hardhat console --network mainnet
> const v = await ethers.getContractAt("MDLNVesting", "0x912f61d5e6db656ec1a7be8db8957c5f1e345d58")
> await v.tranchesDue()
> await v.nextReleaseAt()
> await v.lockedBalance()
```

---

## Verification

```bash
# Token
npx hardhat verify --network mainnet 0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15 "0xA7603783edD8ee6FF4B085f90Af53341282d244C"

# Vesting
npx hardhat verify --network mainnet 0x912f61d5e6db656ec1a7be8db8957c5f1e345d58 "0x0DC90d57F3Aa3E836Ffd6E777E543a43A487dB15" "0xA7603783edD8ee6FF4B085f90Af53341282d244C"
```
