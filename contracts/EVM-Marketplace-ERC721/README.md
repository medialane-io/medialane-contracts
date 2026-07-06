# Medialane Marketplace ERC-721 — EVM

Immutable ERC-721 marketplace venue for EIP-712 signed orders on EVM chains
(Ethereum, Base). Register (signed) → fulfill (unsigned, caller pays) → cancel;
per-offerer bulk-cancel counter; ERC-2981 royalties capped at the seller-signed
maximum; zero protocol fees; no owner, admin, upgrade, or pause.

Same protocol semantics as the Starknet `Medialane-Protocol-ERC721` venue,
expressed idiomatically for the EVM.

## Build & test

    forge build
    forge test
