use collection_drop::drop_collection::DropCollection;
use collection_drop::events::Issued;
use collection_drop::interfaces::{IDropCollectionDispatcher, IDropCollectionDispatcherTrait};
use collection_drop::types::SaleTerms;
use openzeppelin_interfaces::erc721::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait, IERC721_ID, IERC721_METADATA_ID,
};
use openzeppelin_interfaces::introspection::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_block_timestamp, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use super::utils::{
    ALICE, BOB, NO_PROOF, ORGANIZER, ROOT, STRANGER, create_drop, deploy_factory, free_drop,
    free_terms,
};

fn issue_as_organizer(d: IDropCollectionDispatcher, to: starknet::ContractAddress, quantity: u256) {
    start_cheat_caller_address(d.contract_address, ORGANIZER());
    d.issue(to, quantity);
    stop_cheat_caller_address(d.contract_address);
}

#[test]
fn the_organizer_issues_free_tokens() {
    let d = free_drop(10);
    let mut spy = spy_events();
    issue_as_organizer(d, BOB(), 2);
    assert_eq!(IERC721Dispatcher { contract_address: d.contract_address }.balance_of(BOB()), 2);
    assert_eq!(d.total_minted(), 2);
    spy
        .assert_emitted(
            @array![
                (
                    d.contract_address,
                    DropCollection::Event::Issued(Issued { recipient: BOB(), quantity: 2, first_token_id: 1 }),
                ),
            ],
        );
}

#[test]
fn issue_does_not_use_the_recipients_claim_limit() {
    let terms = SaleTerms { max_per_wallet: 1, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, 0);
    issue_as_organizer(d, ALICE(), 3);
    assert_eq!(d.claimed_by(ALICE()), 0);
    start_cheat_caller_address(d.contract_address, ALICE());
    d.claim(1, NO_PROOF());
    assert_eq!(d.claimed_by(ALICE()), 1);
}

#[test]
fn issue_ignores_the_window_and_the_allowlist() {
    let terms = SaleTerms { start_time: 100, end_time: 200, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, ROOT);
    start_cheat_block_timestamp(d.contract_address, 500);
    issue_as_organizer(d, STRANGER(), 1);
    assert_eq!(d.total_minted(), 1);
}

#[test]
#[should_panic(expected: 'Exceeds max supply')]
fn issue_respects_the_supply_cap() {
    let d = free_drop(2);
    issue_as_organizer(d, BOB(), 3);
}

#[test]
#[should_panic(expected: 'Caller is not the organizer')]
fn only_the_organizer_issues() {
    let d = free_drop(10);
    start_cheat_caller_address(d.contract_address, STRANGER());
    d.issue(STRANGER(), 1);
}

#[test]
#[should_panic(expected: 'Invalid recipient')]
fn issue_rejects_the_zero_address() {
    issue_as_organizer(free_drop(10), core::num::traits::Zero::zero(), 1);
}

#[test]
#[should_panic(expected: 'Quantity must be positive')]
fn issue_rejects_zero_quantity() {
    issue_as_organizer(free_drop(10), BOB(), 0);
}

#[test]
fn token_uri_is_base_uri_plus_id() {
    let d = free_drop(20);
    issue_as_organizer(d, BOB(), 12);
    let meta = IERC721MetadataDispatcher { contract_address: d.contract_address };
    assert_eq!(meta.token_uri(1), "ipfs://drop/1");
    assert_eq!(meta.token_uri(12), "ipfs://drop/12");
    assert_eq!(meta.name(), "Drop");
    assert_eq!(meta.symbol(), "DRP");
}

#[test]
#[should_panic(expected: 'ERC721: invalid token ID')]
fn token_uri_of_an_unminted_token_fails() {
    IERC721MetadataDispatcher { contract_address: free_drop(10).contract_address }.token_uri(1);
}

#[test]
fn reports_erc721_and_metadata_support() {
    let src5 = ISRC5Dispatcher { contract_address: free_drop(10).contract_address };
    assert!(src5.supports_interface(IERC721_ID));
    assert!(src5.supports_interface(IERC721_METADATA_ID));
}

#[test]
fn reads_reflect_creation() {
    let d = create_drop(deploy_factory(), 7, free_terms(), ROOT);
    assert_eq!(d.organizer(), ORGANIZER());
    assert_eq!(d.max_supply(), 7);
    assert_eq!(d.allowlist_root(), ROOT);
    assert_eq!(d.terms(), free_terms());
    assert_eq!(d.version(), '1.0.0');
}
