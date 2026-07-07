# Medialane Marketplace — Stellar (Soroban)

Immutable marketplace venue for NFT collections on Stellar. Orders live in
contract storage keyed (offerer, salt) with the protocol's lifecycle:
register (offerer-authorized) → fulfill (anyone, caller pays) → cancel;
per-offerer bulk-cancel counter; royalties read via the collection's
royalty_info interface and capped at the seller-signed maximum; settlement via
standard token/NFT approvals — both directions work in any SEP-41 token
including native XLM (the native Stellar Asset Contract). Zero protocol fees;
no admin functions.

Same protocol semantics as the Starknet, EVM, and Solana Medialane venues,
expressed idiomatically for Soroban.

## Build & test

    SOROBAN_SDK_BUILD_SYSTEM_SUPPORTS_SPEC_SHAKING_V2=true cargo test
    SOROBAN_SDK_BUILD_SYSTEM_SUPPORTS_SPEC_SHAKING_V2=true cargo build --target wasm32v1-none --release
