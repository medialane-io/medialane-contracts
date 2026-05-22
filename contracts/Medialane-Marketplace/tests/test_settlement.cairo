use medialane_marketplace::settlement::seller_proceeds;

#[test]
fn seller_gets_sale_minus_royalty() {
    // Zero-fee protocol: the only deduction from a sale is the creator royalty.
    assert!(seller_proceeds(10_000, 500) == 9_500, "seller gets sale minus royalty");
}

#[test]
fn seller_gets_full_sale_when_no_royalty() {
    assert!(seller_proceeds(10_000, 0) == 10_000, "no royalty: seller gets the whole sale");
}

#[test]
#[should_panic(expected: 'royalty exceeds sale')]
fn seller_proceeds_rejects_royalty_over_sale() {
    seller_proceeds(10_000, 10_001);
}
