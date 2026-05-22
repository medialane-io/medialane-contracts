//! Marketplace constants.
//!
//! The marketplace protocol is zero-fee (`medialane-core` architecture
//! `00-principles.md §12`): the immutable contract takes no cut and embeds no
//! Medialane-specific address. The only constant it needs is the interface id
//! used to detect creator royalties on traded collections.

/// SRC-5 interface id of ERC-2981 (the NFT royalty standard). Used to detect,
/// best-effort, whether a traded collection declares on-chain royalties.
pub const IERC2981_ID: felt252 =
    0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b;
