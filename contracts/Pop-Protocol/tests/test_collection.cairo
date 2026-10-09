use core::num::traits::Zero;
use core::poseidon::poseidon_hash_span;
use openzeppelin_interfaces::erc721::{
    IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait,
};
use pop_protocol::events::{AllowlistRootSet, Locked, TokenURISet};
use pop_protocol::interfaces::{
    IERC5192Dispatcher, IERC5192DispatcherTrait, IPOPCollectionDispatcher,
    IPOPCollectionDispatcherTrait,
};
use pop_protocol::pop_collection::POPCollection;
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_block_timestamp, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use super::utils::{
    ALICE, ALICE_PROOF, BOB, BOB_PROOF, CAROL, CAROL_PROOF, ORGANIZER, ROOT, STRANGER, base_uri,
    collection, create_collection, deploy_factory,
};

fn as_organizer(c: IPOPCollectionDispatcher) {
    start_cheat_caller_address(c.contract_address, ORGANIZER());
}

fn set_root(c: IPOPCollectionDispatcher, root: felt252) {
    as_organizer(c);
    c.set_allowlist_root(root);
    stop_cheat_caller_address(c.contract_address);
}

fn claim_as(c: IPOPCollectionDispatcher, who: ContractAddress, proof: Span<felt252>) {
    start_cheat_caller_address(c.contract_address, who);
    c.claim(proof);
    stop_cheat_caller_address(c.contract_address);
}

fn leaf_of(address: felt252) -> felt252 {
    poseidon_hash_span(array![poseidon_hash_span(array![address].span())].span())
}

#[test]
fn organizer_is_the_creator_and_nothing_is_issued() {
    let c = collection();
    assert_eq!(c.organizer(), ORGANIZER());
    assert_eq!(c.total_issued(), 0);
    assert_eq!(c.allowlist_root(), 0);
    assert_eq!(c.version(), '1.0.0');
}

#[test]
fn issue_mints_a_locked_token_with_the_collection_uri() {
    let c = collection();
    let mut spy = spy_events();
    as_organizer(c);
    c.issue(ALICE(), "");
    assert!(c.has_claimed(ALICE()));
    assert_eq!(c.total_issued(), 1);
    let meta = IERC721MetadataDispatcher { contract_address: c.contract_address };
    assert_eq!(meta.token_uri(1), base_uri());
    assert!(IERC5192Dispatcher { contract_address: c.contract_address }.locked(1));
    spy
        .assert_emitted(
            @array![(c.contract_address, POPCollection::Event::Locked(Locked { token_id: 1 }))],
        );
}

#[test]
fn issue_with_a_token_uri_sets_it_and_emits() {
    let c = collection();
    let mut spy = spy_events();
    as_organizer(c);
    c.issue(ALICE(), "ipfs://distinction.json");
    let meta = IERC721MetadataDispatcher { contract_address: c.contract_address };
    assert_eq!(meta.token_uri(1), "ipfs://distinction.json");
    spy
        .assert_emitted(
            @array![
                (
                    c.contract_address,
                    POPCollection::Event::TokenURISet(
                        TokenURISet { token_id: 1, uri: "ipfs://distinction.json" },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'Caller is not the organizer')]
fn only_the_organizer_can_issue() {
    let c = collection();
    start_cheat_caller_address(c.contract_address, STRANGER());
    c.issue(ALICE(), "");
}

#[test]
#[should_panic(expected: 'Already issued')]
fn an_address_receives_at_most_one_token() {
    let c = collection();
    as_organizer(c);
    c.issue(ALICE(), "");
    c.issue(ALICE(), "");
}

#[test]
#[should_panic(expected: 'Invalid recipient')]
fn issue_rejects_the_zero_address() {
    let c = collection();
    as_organizer(c);
    c.issue(Zero::zero(), "");
}

#[test]
fn issue_ignores_the_claim_window_and_the_root() {
    let c = create_collection(deploy_factory(), 100);
    start_cheat_block_timestamp(c.contract_address, 101);
    as_organizer(c);
    c.issue(BOB(), "");
    assert!(c.has_claimed(BOB()));
}

#[test]
#[should_panic(expected: 'Caller is not the organizer')]
fn only_the_organizer_can_set_the_root() {
    let c = collection();
    start_cheat_caller_address(c.contract_address, STRANGER());
    c.set_allowlist_root(ROOT);
}

#[test]
fn setting_the_root_emits() {
    let c = collection();
    let mut spy = spy_events();
    set_root(c, ROOT);
    assert_eq!(c.allowlist_root(), ROOT);
    spy
        .assert_emitted(
            @array![
                (
                    c.contract_address,
                    POPCollection::Event::AllowlistRootSet(AllowlistRootSet { root: ROOT }),
                ),
            ],
        );
}

#[test]
fn every_listed_address_can_claim_with_its_proof() {
    let c = collection();
    set_root(c, ROOT);
    claim_as(c, ALICE(), ALICE_PROOF());
    claim_as(c, BOB(), BOB_PROOF());
    claim_as(c, CAROL(), CAROL_PROOF());
    assert_eq!(c.total_issued(), 3);
    assert!(c.has_claimed(CAROL()));
}

#[test]
#[should_panic(expected: 'Claims are closed')]
fn claim_fails_without_a_root() {
    let c = collection();
    claim_as(c, ALICE(), ALICE_PROOF());
}

#[test]
#[should_panic(expected: 'Not on allowlist')]
fn claim_fails_with_another_addresses_proof() {
    let c = collection();
    set_root(c, ROOT);
    claim_as(c, ALICE(), BOB_PROOF());
}

#[test]
#[should_panic(expected: 'Not on allowlist')]
fn claim_fails_for_an_unlisted_caller() {
    let c = collection();
    set_root(c, ROOT);
    claim_as(c, STRANGER(), ALICE_PROOF());
}

#[test]
#[should_panic(expected: 'Already issued')]
fn claim_twice_fails() {
    let c = collection();
    set_root(c, ROOT);
    claim_as(c, ALICE(), ALICE_PROOF());
    claim_as(c, ALICE(), ALICE_PROOF());
}

#[test]
fn claim_succeeds_at_the_deadline_second() {
    let c = create_collection(deploy_factory(), 100);
    set_root(c, ROOT);
    start_cheat_block_timestamp(c.contract_address, 100);
    claim_as(c, ALICE(), ALICE_PROOF());
    assert!(c.has_claimed(ALICE()));
}

#[test]
#[should_panic(expected: 'Claim window closed')]
fn claim_fails_after_the_deadline() {
    let c = create_collection(deploy_factory(), 100);
    set_root(c, ROOT);
    start_cheat_block_timestamp(c.contract_address, 101);
    claim_as(c, ALICE(), ALICE_PROOF());
}

#[test]
fn a_zero_deadline_never_closes() {
    let c = collection();
    set_root(c, ROOT);
    start_cheat_block_timestamp(c.contract_address, 0xffffffffffff);
    claim_as(c, ALICE(), ALICE_PROOF());
    assert!(c.has_claimed(ALICE()));
}

#[test]
fn claim_with_single_address_root_and_empty_proof() {
    // A one-leaf tree: the root is the leaf itself.
    let c = collection();
    set_root(c, leaf_of(0x111));
    claim_as(c, ALICE(), array![].span());
    assert!(c.has_claimed(ALICE()));
}

#[test]
fn replacing_root_keeps_issued_and_invalidates_old_proofs() {
    let c = collection();
    set_root(c, ROOT);
    claim_as(c, ALICE(), ALICE_PROOF());
    // The new list contains only CAROL: the root is CAROL's leaf.
    set_root(c, leaf_of(0x333));
    assert!(c.has_claimed(ALICE()));
    assert_eq!(c.total_issued(), 1);
    claim_as(c, CAROL(), array![].span());
    assert_eq!(c.total_issued(), 2);
}

#[test]
#[should_panic(expected: 'Not on allowlist')]
fn an_old_proof_fails_after_the_root_changes() {
    let c = collection();
    set_root(c, ROOT);
    set_root(c, 'another root');
    claim_as(c, BOB(), BOB_PROOF());
}

#[test]
#[should_panic(expected: 'ERC721: invalid token ID')]
fn token_uri_of_an_unminted_token_fails() {
    let c = collection();
    IERC721MetadataDispatcher { contract_address: c.contract_address }.token_uri(1);
}
