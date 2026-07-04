# Medialane Contracts

Open-source Cairo smart contracts for [Medialane](https://medialane.io), a
creator IP platform on Starknet. This repository holds the on-chain protocol —
the source of truth for assets, marketplaces, and creator services. Each contract
is self-contained with its own README, tests, and build.

## Contracts

| Contract | Standard | What it is |
|---|---|---|
| [`Medialane-Protocol-ERC721`](contracts/Medialane-Protocol-ERC721) | ERC-721 | Immutable marketplace venue for signed orders: fixed-price listings and bids, EIP-2981 royalties, bulk cancel. **v0.4.0** |
| [`Medialane-Protocol-ERC1155`](contracts/Medialane-Protocol-ERC1155) | ERC-1155 | Immutable marketplace venue with partial fills and per-unit pricing; same order model as the ERC-721 venue. **v0.3.0** |
| [`Collection-Drop`](contracts/Collection-Drop) | ERC-721 | Multi-tenant timed NFT drops — a factory deploys per-drop collections with claim windows and allowlists. |
| [`Pop-Protocol`](contracts/Pop-Protocol) | ERC-721 (soulbound) | Proof-of-participation credentials — a factory deploys per-event, non-transferable collections. |
| [`NFTComments`](contracts/NFTComments) | — | On-chain NFT comments emitted as events, with per-address rate limiting. |
| [`MDLN`](contracts/MDLN) | ERC-20 (L1) | Governance/utility token and vesting on Ethereum, bridged to Starknet via StarkGate. |

## Marketplace protocol

The two marketplace venues share one design and differ only in the token standard
they trade:

- **Off-chain signed orders (SNIP-12).** Makers sign orders off-chain; anyone can
  register and fulfil them on-chain. The venues never take custody — payment is
  pulled and the asset delivered atomically at fulfilment.
- **Listings and bids.** Both directions are supported: offer an asset for
  payment, or offer payment for an asset. Payment is native STRK or any ERC-20.
- **Capped EIP-2981 royalties.** Royalties are read live from the collection and
  paid to the creator, never above a seller-signed cap; non-royalty collections
  are handled gracefully rather than blocking sales.
- **Bulk cancel.** Each maker has a cancel epoch (`counter`); one call invalidates
  all of their outstanding orders.
- **Immutable & non-custodial.** No owner, admin, upgrade, or pause. Each
  deployment exposes its release via `contract_version()`, and orders are bound to
  their marketplace address so signatures cannot be replayed across deployments.
- **Hardened settlement.** Reentrancy guard with a checks-effects-interactions
  ordering (payment before delivery) across every order-lifecycle entrypoint.

The ERC-1155 venue adds **partial fills** (fill part of an order, leaving the
remainder open) and **per-unit pricing** (`sale = price_per_unit × quantity`,
overflow-checked).

## Build & test

Each contract builds and tests independently with [Scarb](https://docs.swmansion.com/scarb/)
and [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/):

```bash
cd contracts/<contract>
scarb build
snforge test
```

## License

Open source. See individual contract directories for details.
