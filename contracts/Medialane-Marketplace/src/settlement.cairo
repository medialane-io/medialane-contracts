//! Shared settlement math for the Medialane marketplace contracts.
//!
//! Both the ERC-721 and ERC-1155 marketplaces import this module so the royalty
//! handling can never diverge between them.
//!
//! The marketplace is zero-fee — there is no platform cut anywhere here. The
//! only deduction from a sale is the creator's ERC-2981 royalty, which is the
//! creator's money, not a marketplace fee.

use starknet::ContractAddress;
use starknet::syscalls::call_contract_syscall;
use core::num::traits::Zero;
use crate::constants::IERC2981_ID;

/// Returns the seller's proceeds for a sale: the gross amount minus the creator
/// royalty. Reverts with a clean reason if the royalty would exceed the sale
/// amount (e.g. a collection reporting an abusive royalty) — without the guard
/// the bare `u256` subtraction would underflow-panic with an opaque message.
pub fn seller_proceeds(sale_amount: u256, royalty_amount: u256) -> u256 {
    assert(royalty_amount <= sale_amount, 'royalty exceeds sale');
    sale_amount - royalty_amount
}

/// Best-effort ERC-2981 royalty lookup for a traded collection.
///
/// Returns `(receiver, amount)` if the collection declares ERC-2981 and reports
/// a non-zero royalty; otherwise `(0, 0)`. Every failure mode — missing
/// interface, missing entrypoint, malformed return — resolves to `(0, 0)` so an
/// uncooperative external collection can never block a trade.
pub fn get_royalty(
    nft_contract: ContractAddress, token_id: u256, sale_price: u256,
) -> (ContractAddress, u256) {
    let zero: ContractAddress = 0.try_into().unwrap();

    // 1. Does the collection declare ERC-2981 at all?
    let supports = match call_contract_syscall(
        nft_contract, selector!("supports_interface"), array![IERC2981_ID].span(),
    ) {
        Result::Ok(ret) => ret.len() > 0 && *ret.at(0) != 0,
        Result::Err(_) => false,
    };
    if !supports {
        return (zero, 0);
    }

    // 2. Ask for the royalty. Any malformed response resolves to no royalty.
    let calldata = array![
        token_id.low.into(), token_id.high.into(),
        sale_price.low.into(), sale_price.high.into(),
    ];
    match call_contract_syscall(nft_contract, selector!("royalty_info"), calldata.span()) {
        Result::Ok(ret) => {
            if ret.len() < 3 {
                return (zero, 0);
            }
            let receiver: Option<ContractAddress> = (*ret.at(0)).try_into();
            let low: Option<u128> = (*ret.at(1)).try_into();
            let high: Option<u128> = (*ret.at(2)).try_into();
            match (receiver, low, high) {
                (Option::Some(addr), Option::Some(l), Option::Some(h)) => {
                    let royalty = u256 { low: l, high: h };
                    if addr.is_zero() || royalty == 0 {
                        (zero, 0)
                    } else {
                        (addr, royalty)
                    }
                },
                _ => (zero, 0),
            }
        },
        Result::Err(_) => (zero, 0),
    }
}
