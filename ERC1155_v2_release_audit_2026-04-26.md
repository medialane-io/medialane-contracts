# Medialane ERC1155 V2 Release Audit

Date: 2026-04-26

Scope:
- `contracts/Medialane-Protocol-ERC1155`

Release:
- Contract: `Medialane1155V2`
- Interface: `IMedialane1155V2`
- Toolchain: `scarb 2.18.0`, `snforge 0.59.0`
- Class hash: `0x03e1b84f1058dd5c9c766634e638d02756b59910080492983a5168c99856efd0`
- Mainnet contract: `0x04a0a65bd13e1ec9a2ce92c36115578486331e941b395f97d49fe488baac8309`
- Declare tx: `0x0685d29dec774934809842310d0696aa86127f9fa7f4942570b4f09cc05a99d3`
- Deploy tx: `0x06e9e5c15345e313e929807e45501715c9f42b0e16c8368e25a7170a145674b2`

## Verdict

Approved and deployed as the immutable ERC1155 v2 mainnet release.

The contract now follows the same marketplace vocabulary as the audited ERC721 release while preserving the ERC1155-specific behavior that matters: partial fills, remaining-amount accounting, ERC-2981 royalty overlay, and CEI before external transfers.

## Architecture Changes

- Replaced the legacy narrow order fields with `ItemType`, `OfferItem`, `ConsiderationItem`, and ERC721-style `OrderParameters`.
- Changed SNIP-12 domain to `Medialane`, version `2`, separating v2 signatures from legacy ERC1155 and ERC721.
- Renamed the contract surface to `Medialane1155V2` / `IMedialane1155V2`.
- Added `get_native_token_address`, matching the ERC721 getter naming.
- Kept `quantity` in `OrderFulfillment`, because ERC1155 partial fills are fulfillment-specific.
- Removed single stored `fulfiller`; many fulfillers can partially fill the same order.

## Security Properties Reviewed

- Immutable contract surface: no owner, no admin role, no upgrade hook.
- Offerer-only cancellation.
- Fulfiller-only fill: caller must match the signed fulfillment.
- Self-fill rejected.
- Replay protection through `NoncesComponent`.
- Partial fill state is updated before external token transfers.
- Registration allowed any time before expiry, while fulfillment remains active-window gated.
- Invalid `start_time >= end_time` windows rejected before storage.
- Unsupported launch trade shapes rejected before signature validation.
- ERC20/NATIVE canonical payment fields enforced before order storage.
- ERC-2981 royalty probing degrades gracefully for non-royalty ERC1155 contracts.

## Launch Trade Shapes

Supported in v2:

- `ERC1155` offer for `ERC20` consideration
- `ERC1155` offer for `NATIVE` consideration

Not enabled in this release:

- bid flow, such as `ERC20` or `NATIVE` offer for `ERC1155` consideration
- multi-consideration split payouts

Those are product extensions, not blockers for this v2 listing release.

## Verification

Commands run:

```bash
SCARB_CACHE=/tmp/scarb-cache-erc1155-v2 scarb build
SCARB_CACHE=/tmp/snforge-erc1155-v2 PATH="$HOME/.asdf/shims:$HOME/.cargo/bin:$PATH" snforge test
SCARB_CACHE=/tmp/scarb-cache-erc1155-v2 sncast utils class-hash --contract-name Medialane1155V2
SCARB_CACHE=/tmp/scarb-cache-erc1155-v2 sncast --profile medialane-deployer --wait declare --contract-name Medialane1155V2
sncast --profile medialane-deployer --wait deploy --class-hash 0x03e1b84f1058dd5c9c766634e638d02756b59910080492983a5168c99856efd0 --arguments 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
sncast call --url https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/tOTwt1ug3YNOsaPjinDvS --contract-address 0x04a0a65bd13e1ec9a2ce92c36115578486331e941b395f97d49fe488baac8309 --function get_native_token_address
```

Results:

- `scarb build`: passed
- `snforge test`: 40 passed, 0 failed
- Class hash: `0x03e1b84f1058dd5c9c766634e638d02756b59910080492983a5168c99856efd0`
- Mainnet declaration: accepted
- Mainnet deployment: accepted
- On-chain constructor check: `get_native_token_address()` returns STRK (`0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`)

## Remaining Non-Blocking Caveat

No contract-level blocker remains from this review. Product rollout should still explicitly gate which order shapes the frontend and indexer create, because bid flow and multi-recipient consideration are intentionally not part of this release.

## Deployment Record

Mainnet declaration and deployment used:

- profile: `medialane-deployer`
- account: `0x06acfcef048dcaac4a11fab313507d53145ed2a468f2a6188527918f1b12d935`
- native token constructor arg: `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`
- contract address: `0x04a0a65bd13e1ec9a2ce92c36115578486331e941b395f97d49fe488baac8309`
