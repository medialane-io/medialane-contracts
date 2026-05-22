use medialane_marketplace::settlement::{compute_fee, compute_split};

#[test]
fn fee_is_one_percent_of_sale() {
    // 1% of 10_000 is 100.
    assert!(compute_fee(10_000) == 100, "expected 1% fee of 100");
}

#[test]
fn split_deducts_fee_and_royalty_from_seller_proceeds() {
    let (fee, seller) = compute_split(10_000, 500);
    assert!(fee == 100, "fee should be 1%");
    assert!(seller == 9_400, "seller gets sale minus fee minus royalty");
}

#[test]
fn split_leaves_truncated_dust_with_the_seller() {
    // 1% of 199 truncates to 1; the seller keeps the 0.99 remainder.
    let (fee, seller) = compute_split(199, 0);
    assert!(fee == 1, "fee truncates down");
    assert!(seller == 198, "seller keeps the rounding dust");
}

#[test]
#[should_panic(expected: 'fee+royalty exceeds sale')]
fn split_rejects_fee_plus_royalty_over_sale() {
    // fee (1% of 10_000 = 100) + royalty 9_950 = 10_050 > 10_000.
    compute_split(10_000, 9_950);
}
