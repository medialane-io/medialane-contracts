use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use medialane_marketplace::settlement::get_royalty;

fn deploy(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    address
}

#[test]
fn royalty_fetched_from_erc2981_collection() {
    let collection = deploy("MockRoyaltyCollection");
    let (receiver, amount) = get_royalty(collection, 1, 10_000);

    let expected: ContractAddress = 0x999.try_into().unwrap();
    assert!(receiver == expected, "royalty receiver from the collection");
    assert!(amount == 500, "5% royalty of 10_000");
}

#[test]
fn no_royalty_from_non_erc2981_collection() {
    // A collection that does not declare ERC-2981 must never block a trade —
    // get_royalty resolves to (0, 0) so settlement just pays seller + fee.
    let collection = deploy("MockPlainCollection");
    let (receiver, amount) = get_royalty(collection, 1, 10_000);

    let zero: ContractAddress = 0.try_into().unwrap();
    assert!(receiver == zero, "no royalty receiver");
    assert!(amount == 0, "no royalty amount");
}
