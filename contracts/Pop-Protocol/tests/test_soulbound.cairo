use core::num::traits::Zero;
use openzeppelin_interfaces::introspection::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin_interfaces::erc721::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721_ID, IERC721_METADATA_ID,
};
use pop_protocol::interfaces::{
    IERC5192_ID, IPOPCollectionDispatcher, IPOPCollectionDispatcherTrait,
};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use super::utils::{ALICE, BOB, ORGANIZER, collection};

fn issued() -> (IPOPCollectionDispatcher, IERC721Dispatcher) {
    let c = collection();
    start_cheat_caller_address(c.contract_address, ORGANIZER());
    c.issue(ALICE(), "");
    stop_cheat_caller_address(c.contract_address);
    (c, IERC721Dispatcher { contract_address: c.contract_address })
}

#[test]
fn owner_and_balance_are_readable() {
    let (_, nft) = issued();
    assert_eq!(nft.owner_of(1), ALICE());
    assert_eq!(nft.balance_of(ALICE()), 1);
    assert!(nft.get_approved(1).is_zero());
    assert!(!nft.is_approved_for_all(ALICE(), BOB()));
}

#[test]
#[should_panic(expected: 'SOULBOUND')]
fn transfer_from_reverts() {
    let (c, nft) = issued();
    start_cheat_caller_address(c.contract_address, ALICE());
    nft.transfer_from(ALICE(), BOB(), 1);
}

#[test]
#[should_panic(expected: 'SOULBOUND')]
fn safe_transfer_from_reverts() {
    let (c, nft) = issued();
    start_cheat_caller_address(c.contract_address, ALICE());
    nft.safe_transfer_from(ALICE(), BOB(), 1, array![].span());
}

#[test]
#[should_panic(expected: 'SOULBOUND')]
fn approve_reverts() {
    let (c, nft) = issued();
    start_cheat_caller_address(c.contract_address, ALICE());
    nft.approve(BOB(), 1);
}

#[test]
#[should_panic(expected: 'SOULBOUND')]
fn set_approval_for_all_reverts() {
    let (c, nft) = issued();
    start_cheat_caller_address(c.contract_address, ALICE());
    nft.set_approval_for_all(BOB(), true);
}

#[test]
fn supports_erc721_metadata_and_erc5192() {
    let c = collection();
    let src5 = ISRC5Dispatcher { contract_address: c.contract_address };
    assert!(src5.supports_interface(IERC721_ID));
    assert!(src5.supports_interface(IERC721_METADATA_ID));
    assert!(src5.supports_interface(IERC5192_ID));
}
