//! Shared settlement math for the Medialane marketplace contracts.
//!
//! Both the ERC-721 and ERC-1155 marketplaces import this module so the fee and
//! royalty split can never diverge between them.

use crate::constants::{FEE_BPS, FEE_DENOMINATOR};

/// Returns the marketplace fee owed on a gross sale amount.
///
/// Integer division truncates — the rounding remainder stays with the seller
/// (see `compute_split`), so no value is lost.
pub fn compute_fee(sale_amount: u256) -> u256 {
    sale_amount * FEE_BPS / FEE_DENOMINATOR
}

/// Splits a gross sale amount into `(marketplace_fee, seller_proceeds)` given the
/// royalty already computed for the sale.
///
/// Reverts with a clean reason if `fee + royalty` would exceed the sale amount
/// (e.g. a collection reporting an abusive royalty) — without the guard the bare
/// `u256` subtraction would underflow-panic with an opaque message.
pub fn compute_split(sale_amount: u256, royalty_amount: u256) -> (u256, u256) {
    let fee = compute_fee(sale_amount);
    assert(fee + royalty_amount <= sale_amount, 'fee+royalty exceeds sale');
    let seller_amount = sale_amount - fee - royalty_amount;
    (fee, seller_amount)
}
