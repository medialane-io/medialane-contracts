//! Immutable marketplace constants.
//!
//! Every value here is fixed at compile time. Changing any of them produces a
//! different class hash and requires a fresh deployment — by design. The class
//! hash is the guarantee: it fully describes the fee and its destination, with
//! no constructor parameter or setter that could make two instances differ.

/// Marketplace fee in basis points. 100 = 1%.
pub const FEE_BPS: u256 = 100;

/// Basis-point denominator. fee = sale_amount * FEE_BPS / FEE_DENOMINATOR.
pub const FEE_DENOMINATOR: u256 = 10_000;

/// SRC-5 interface id of ERC-2981 (the NFT royalty standard). Used to detect,
/// best-effort, whether a traded collection declares on-chain royalties.
pub const IERC2981_ID: felt252 =
    0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b;
