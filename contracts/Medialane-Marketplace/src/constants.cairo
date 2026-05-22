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
