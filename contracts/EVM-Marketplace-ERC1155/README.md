# Medialane Marketplace ERC-1155 — EVM

Immutable ERC-1155 marketplace venue for EIP-712 signed orders on EVM chains
(Ethereum, Base), with partial fills and per-unit pricing
(sale = price-per-unit × quantity). Register (signed) → fulfill quantity
(unsigned, caller pays) → cancel; per-offerer bulk-cancel counter; ERC-2981
royalties capped at the seller-signed maximum; zero protocol fees; no owner,
admin, upgrade, or pause.

Same protocol semantics as the Starknet `Medialane-Protocol-ERC1155` venue,
expressed idiomatically for the EVM.

## Build & test

    forge build
    forge test
