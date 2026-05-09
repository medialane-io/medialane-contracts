# Medialane ERC721 Final Release Audit

Date: 2026-04-26

Scope:
- `contracts/Medialane-Protocol-ERC721`

Release candidate:
- Contract: `Medialane`
- Toolchain: `scarb 2.18.0`, `snforge 0.59.0`
- Local class hash: `0x03dff4f34b976207246207954263be9a28b51390321702443291088dcdf4b2e6`

## Verdict

Approved for mainnet declaration from a contract-security and architecture perspective, with one non-blocking product-surface caveat.

The contract now has a cleaner registration boundary and stronger canonical order validation than the previous deployed ERC721 version. The immutable/no-admin design remains intact.

## Release-Gate Fixes Applied

- Registration no longer rejects orders merely because `start_time` has passed. Orders can be registered any time before expiry, while fulfillment remains gated by the active window.
- Registration rejects invalid windows where `end_time != 0` and `start_time >= end_time`.
- Registration validates token addresses and consideration recipient before storing or emitting `OrderCreated`.
- `NATIVE` items must use zero `token` and zero `identifier_or_criteria`, matching transfer semantics.
- `ERC20` items must use zero `identifier_or_criteria`, matching transfer semantics.
- Fulfillment rejects a zero `fulfiller` before attempting account signature validation.

## Security Properties Reviewed

- Immutable deployment model: no owner, no access-control component, no upgrade hook.
- Signature authorization: order registration, fulfillment, and cancellation each require a SNIP-12/SRC-6 signature from the relevant signer.
- Replay protection: `NoncesComponent` consumes account nonces for registration, fulfillment, and cancellation.
- Mempool replay resistance: `fulfill_order` requires `caller == fulfillment.fulfiller`.
- Offerer-bound cancellation: cancellation intent must name the original offerer.
- CEI settlement: order state is marked `Filled` before external token transfers.
- Registration validation: malformed order data is rejected before storage/indexing.

## Verification

Commands run:

```bash
SCARB_CACHE=/tmp/scarb-cache-erc721-218 scarb build
SCARB_CACHE=/tmp/snforge-erc721-218 PATH="$HOME/.asdf/shims:$HOME/.cargo/bin:$PATH" snforge test
SCARB_CACHE=/tmp/scarb-cache-erc721-218 sncast utils class-hash --contract-name Medialane
```

Results:

- `scarb build`: passed
- `snforge test`: 23 passed, 0 failed
- Class hash: `0x03dff4f34b976207246207954263be9a28b51390321702443291088dcdf4b2e6`

## Remaining Non-Blocking Caveat

The contract intentionally keeps a Seaport-style generic item vocabulary (`NATIVE`, `ERC20`, `ERC721`, `ERC1155`). The tested end-to-end product path is still primarily ERC721-for-ERC20 marketplace flow plus the new validation/security regressions.

Before broad product enablement of every possible pair, Medialane should explicitly document or test each supported trade shape. This is not a blocker for declaring the contract if the frontend/backend only create the intended ERC721 marketplace orders.

## Deployment Recommendation

Declare this class only after confirming the deployment flow will use:

- profile: `medialane-deployer`
- account: `0x06acfcef048dcaac4a11fab313507d53145ed2a468f2a6188527918f1b12d935`
- native token constructor arg: `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`

