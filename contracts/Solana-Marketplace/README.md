# Medialane Marketplace — Solana

Immutable marketplace venue for Metaplex Core assets on Solana. Orders are
offerer-signed instructions stored in PDAs with the protocol's lifecycle:
register → fulfill (anyone, caller pays) → cancel; per-offerer bulk-cancel
counter; royalties read live from the Core Royalties plugin and capped at the
seller-signed maximum; settlement via a Core transfer delegate approved at
registration (listings) or an SPL token delegate (bids). Zero protocol fees;
no admin instructions.

Same protocol semantics as the Starknet and EVM Medialane venues, expressed
idiomatically for Solana, with one deliberate simplification: orders carry no
separate recipient — a listing's payment goes to the offerer and a bid's asset
goes to the offerer, and a fill delivers to the fulfiller. The
route-to-a-chosen-recipient option of the other venues is dropped. Lifecycle
mutations cannot run inside a fill's settlement window because the Solana
runtime itself prohibits reentrant cross-program invocation.

## Build & test

    anchor build
    cargo test
