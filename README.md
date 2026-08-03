# Medialane Contracts

Open-source smart contracts for [Medialane](https://medialane.io), a creator IP
platform on Starknet. This repository holds the on-chain protocol — the source
of truth for assets, marketplaces, wallets, and creator services. Each contract
is self-contained with its own build, tests, and (where applicable) audit
records — there is no shared root workspace or toolchain.

**Current on-chain addresses and class hashes are read from
[`@medialane/sdk`](https://www.npmjs.com/package/@medialane/sdk)'s chain
registry (`chains.ts`)** — the single source of truth every app in the
platform reads from. This README intentionally does not hardcode addresses,
since a redeploy makes any hardcoded copy stale.

## Contracts

| Contract | Chain / stack | Standard | What it is | Status |
|---|---|---|---|---|
| [`Medialane-Protocol-ERC721`](contracts/Medialane-Protocol-ERC721) | Starknet (Cairo) | ERC-721 | Immutable marketplace venue for signed orders: fixed-price listings and bids, EIP-2981 royalties, bulk cancel. | Live |
| [`Medialane-Protocol-ERC1155`](contracts/Medialane-Protocol-ERC1155) | Starknet (Cairo) | ERC-1155 | Immutable marketplace venue with partial fills and per-unit pricing; same order model as the ERC-721 venue. | Live |
| [`MediaWallet`](contracts/MediaWallet) | Starknet (Cairo) | Account | Self-sovereign smart-wallet account contract — single Stark-curve owner, optional guardian recovery, session keys, SNIP-9 outside execution. Fork of Argent's ChainSecurity-audited baseline. | Live |
| [`Collection-Drop`](contracts/Collection-Drop) | Starknet (Cairo) | ERC-721 | Multi-tenant timed NFT drops — a factory deploys per-drop collections with claim windows and allowlists. | Live |
| [`Pop-Protocol`](contracts/Pop-Protocol) | Starknet (Cairo) | ERC-721 (soulbound) | Proof-of-participation credentials — a factory deploys per-event, non-transferable collections. | Live |
| [`Creator-Coin`](contracts/Creator-Coin) | Starknet (Cairo) | ERC-20 | Permissionless launchpad for fixed-supply creator coins with a fixed Ekubo LP launch. Fork of Keep Starknet Strange's audited launchpad framework. | Live |
| [`NFTComments`](contracts/NFTComments) | Starknet (Cairo) | — | On-chain NFT comments emitted as events, with per-address rate limiting. | Live |
| [`MDLN`](contracts/MDLN) | Ethereum (Solidity) | ERC-20 | Governance/utility token and vesting for the Medialane DAO, bridged to Starknet via StarkGate. | Live |
| [`EVM-Marketplace-ERC721`](contracts/EVM-Marketplace-ERC721) | Ethereum + Base (Solidity) | ERC-721 | EVM port of the marketplace venue protocol — EIP-712 signed orders, ERC-2981 royalties, zero fees. | Built, not yet deployed |
| [`EVM-Marketplace-ERC1155`](contracts/EVM-Marketplace-ERC1155) | Ethereum + Base (Solidity) | ERC-1155 | EVM port with partial fills and per-unit pricing. | Built, not yet deployed |
| [`Solana-Marketplace`](contracts/Solana-Marketplace) | Solana (Rust/Anchor) | Metaplex Core | Solana port of the marketplace venue protocol, settling via Core's transfer-delegate and royalties plugins. | Built, not yet deployed |
| [`Soroban-Marketplace`](contracts/Soroban-Marketplace) | Stellar (Soroban) | — | Soroban port of the marketplace venue protocol; any SEP-41 token including native XLM. | Built, not yet deployed |

## Marketplace protocol

The marketplace venues share one design across every chain they're deployed
to, differing only in the token standard and chain-native signing scheme:

- **Off-chain signed orders.** Makers sign orders off-chain (SNIP-12 on
  Starknet, EIP-712 on EVM chains); anyone can register and fulfil them
  on-chain. The venues never take custody — payment is pulled and the asset
  delivered atomically at fulfilment.
- **Listings and bids.** Both directions are supported: offer an asset for
  payment, or offer payment for an asset.
- **Capped royalties.** Royalties are read live from the collection (EIP-2981
  on Starknet/EVM, the Metaplex Core royalties plugin on Solana, a
  `royalty_info` call on Soroban) and paid to the creator, never above a
  seller-signed cap; collections with no royalty configuration are handled
  gracefully rather than blocking sales.
- **Bulk cancel.** Each maker has a cancel epoch (a counter); one call
  invalidates all of their outstanding orders.
- **Immutable & non-custodial.** No owner, admin, upgrade, or pause on any
  venue. Each deployment exposes its release via an on-chain version call, and
  orders are bound to their marketplace address so signatures cannot be
  replayed across deployments.
- **Hardened settlement.** Reentrancy guard with a checks-effects-interactions
  ordering (payment before delivery) across every order-lifecycle entrypoint.

The 1155-standard venues (Starknet, EVM, and the underlying model ported to
Solana/Soroban) add **partial fills** (fill part of an order, leaving the
remainder open) and **per-unit pricing** (`sale = price_per_unit × quantity`,
overflow-checked).

## MediaWallet

A self-sovereign Starknet account contract — a faithful fork of
[`argentlabs/argent-contracts-starknet`](https://github.com/argentlabs/argent-contracts-starknet)
at its ChainSecurity-audited baseline, with WebAuthn/P256, EIP-191, and the
multisig module removed and everything renamed end to end. The full delta from
the audited baseline is documented in `contracts/MediaWallet/AUDIT.md`, and the
exact baseline commit + vendored audit reports are in `contracts/MediaWallet/FORK.md`.

`MediaWalletFactory` is permissionless and immutable (no owner, admin, fee, or
upgrade path): a wallet's address depends only on class hash + salt + owner
public key, never on the factory, so it can be predicted before deployment.

## Creator-Coin

A permissionless launchpad for fixed-supply creator coins, forked verbatim
from [Keep Starknet Strange's `unruggable.meme`](https://github.com/keep-starknet-strange/unruggable.meme)
launchpad framework (MIT licensed — see `contracts/Creator-Coin/LICENSE`).
Protocol mechanics are preserved exactly; only naming is Medialane's. A coin is
created in two steps — permissionless ERC-20 deployment via the factory, then
an owner-only, one-time Ekubo launch — after which the coin's ownership is
renounced and the principal LP position is held permanently by the launcher
contract (no code path withdraws it; only pool fees are withdrawable).

## Build & test

Each contract is self-contained with its own toolchain — there is no shared
root workspace, so pin/install per contract as documented in its directory.

**Cairo (Starknet) contracts** — [Scarb](https://docs.swmansion.com/scarb/) +
[Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/):

```bash
cd contracts/<contract>
scarb build
snforge test
```

**Solidity (Ethereum/Base) contracts** — [Foundry](https://book.getfoundry.sh/):

```bash
cd contracts/<contract>
forge build
forge test
```

**Solana contract** — [Anchor](https://www.anchor-lang.com/):

```bash
cd contracts/Solana-Marketplace
anchor build
cargo test
```

**Stellar (Soroban) contract**:

```bash
cd contracts/Soroban-Marketplace
cargo build --target wasm32v1-none --release
cargo test
```

**MDLN (Ethereum L1)** — [Hardhat](https://hardhat.org/):

```bash
cd contracts/MDLN
npm install
npx hardhat test
```

## License

Open source. See individual contract directories for details — most Cairo and
EVM contracts are MIT or GPL-3.0 (`LICENSE` per directory); forked contracts
additionally document their upstream license and audit provenance in that
directory's `FORK.md`/`AUDIT.md`.
