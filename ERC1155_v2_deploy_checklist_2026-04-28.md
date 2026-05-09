# ERC1155 Marketplace V2 Deploy Checklist - 2026-04-28

## Scope

This checklist covers the ERC1155 marketplace protocol update that adds parity with the ERC721 marketplace for bid-shaped orders:

- Listings: `ERC1155 -> ERC20/NATIVE`
- Offers/bids: `ERC20/NATIVE -> ERC1155`
- Partial fills remain supported for ERC1155 quantities.
- ERC2981 royalty payout is applied to both listing purchases and accepted bids.

No backend, SDK, UI, production environment, or deployment changes should be made until the contract deployment is explicitly approved.

## Current Verified Artifact

- Contract package: `contracts/Medialane-Protocol-ERC1155`
- Contract name: `Medialane1155V2`
- Constructor argument: Starknet STRK token address
- Mainnet STRK token address: `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`
- Current computed class hash: `0x01b674aad934be85abc7c1970265cbf7e9bc7d586a90f0a67112c201636dbdd3`
- Declared class hash: `0x01b674aad934be85abc7c1970265cbf7e9bc7d586a90f0a67112c201636dbdd3`
- Declare transaction hash: `0x079603be9ec8861a3450e1557fb1353c3b8428b9759582644c4520591426a356`
- Declaration status: accepted
- Deployed contract address: `0x02bfa521c25461a09d735889b469418608d7d92f8b26e3d37ef174a4c2e22f99`
- Deploy transaction hash: `0x02d42585c5d9f767b6be932c67b8e368c94ae91b6ea557b0e43997ea1684ccba`
- Deployment block number: `9260304`
- Deployment status: accepted
- Post-deploy native token read: `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`

Recompute the class hash immediately before declare/deploy. If it changes, stop and review the source diff before continuing.

## Security Gates

- Order shape must be exactly one ERC1155 side and one payment side.
- Payment side must be only `ERC20` or `NATIVE`.
- ERC1155 side must use a nonzero token address and nonzero amount.
- Payment side must use identifier `0`; `NATIVE` must use zero token field.
- Order amount accounting must track ERC1155 quantity, not payment amount.
- Fulfillment must update order state before external token transfers.
- ERC1155 accepted bids must transfer payment from bidder to seller/royalty receiver and ERC1155 from seller to bidder recipient.
- Listing purchases must transfer ERC1155 from seller to buyer and payment from buyer to seller/royalty receiver.
- Nonces must be consumed for order registration, fulfillment, and cancellation.
- `fulfiller == caller` must hold to prevent third-party execution surprises.
- Self-fill must remain rejected.
- Royalties must never exceed sale amount.

## Pre-Deploy Verification

Run from:

```sh
cd /Users/kalamaha/dev/medialane-contracts/contracts/Medialane-Protocol-ERC1155
```

Run tests:

```sh
/bin/zsh -lc 'SCARB_CACHE=/tmp/snforge-erc1155-parity PATH="/Users/kalamaha/.asdf/installs/scarb/2.17.0/bin:/Users/kalamaha/.asdf/shims:/Users/kalamaha/.cargo/bin:$PATH" snforge test'
```

Expected result:

```text
Tests: 49 passed, 0 failed, 0 ignored, 0 filtered out
```

Run build:

```sh
/bin/zsh -lc 'SCARB_CACHE=/tmp/scarb-cache-erc1155-v2 ~/.asdf/shims/scarb build'
```

Run class hash:

```sh
/bin/zsh -lc 'SCARB_CACHE=/tmp/scarb-cache-erc1155-v2 ~/.asdf/shims/sncast utils class-hash --contract-name Medialane1155V2'
```

Expected class hash:

```text
0x01b674aad934be85abc7c1970265cbf7e9bc7d586a90f0a67112c201636dbdd3
```

Run diff hygiene:

```sh
git -C /Users/kalamaha/dev/medialane-contracts diff --check -- contracts/Medialane-Protocol-ERC1155/src/core/medialane.cairo contracts/Medialane-Protocol-ERC1155/tests/tests.cairo contracts/Medialane-Protocol-ERC1155/scripts/compute_signatures.mjs
```

## Declare/Deploy Plan

Only proceed after explicit approval.

Declare:

```sh
/bin/zsh -lc 'SCARB_CACHE=/tmp/scarb-cache-erc1155-v2 ~/.asdf/shims/sncast --profile medialane-deployer --wait declare --contract-name Medialane1155V2'
```

Deploy:

```sh
~/.asdf/shims/sncast --profile medialane-deployer --wait deploy --class-hash <DECLARED_CLASS_HASH> --arguments 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
```

Record:

- Declared class hash
- Deploy transaction hash
- New ERC1155 marketplace contract address
- Deployment block number

## Post-Deploy Read Checks

Confirm constructor state:

```sh
~/.asdf/shims/sncast call --url <MAINNET_RPC_URL> --contract-address <NEW_ERC1155_MARKETPLACE_ADDRESS> --function get_native_token_address
```

Expected:

```text
0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
```

Confirm class hash on explorer/RPC matches the declared class hash.

## Platform Follow-Up After Deployment

Backend:

- Update `MARKETPLACE_1155_CONTRACT_MAINNET` to the new ERC1155 marketplace address.
- Keep `MARKETPLACE_721_CONTRACT_MAINNET` unchanged.
- Set ERC1155 marketplace start block to the new deployment block if the backend uses a protocol-specific start block.
- Restart Railway and verify health.

SDK:

- Update ERC1155 marketplace address/constants and typed-data domain/version if exposed.
- Ensure accepted ERC1155 bids use the ERC1155 marketplace, not the ERC721 marketplace.

UI:

- Update production Vercel env if the ERC1155 marketplace address is exposed client-side.
- Verify listing, cancel listing, buy listing, make offer, cancel offer, and accept offer for both ERC721 and ERC1155.
- Keep marketplace debug visible until the full production test matrix passes.

## Production Test Matrix

ERC721:

- Create listing
- Cancel listing
- Buy listing
- Make offer
- Cancel offer
- Accept offer

ERC1155:

- Create listing
- Cancel listing
- Buy listing
- Make ERC20 offer
- Make native/STRK offer
- Accept ERC20 offer
- Accept native/STRK offer
- Partial quantity listing purchase
- Partial quantity bid acceptance, if exposed in UI

Portfolio/indexing:

- Seller balances update after listing sale.
- Buyer portfolio shows purchased ERC1155 edition.
- ERC1155 owners count updates after transfer.
- Marketplace listing/offer status clears after cancel/fill.

## Rollback Boundary

The contract is immutable and non-upgradable. A bad deployment cannot be patched in place.

Safe rollback is platform-level only:

- Repoint backend/UI env vars back to the previous ERC1155 marketplace address.
- Stop indexing from the new contract.
- Leave the new contract unused.

Do not deploy if any pre-deploy verification or post-deploy read check is ambiguous.
