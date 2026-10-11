use collection_drop::drop_collection::DropCollection;
use collection_drop::events::{AllowlistRootSet, Claimed};
use collection_drop::interfaces::{IDropCollectionDispatcher, IDropCollectionDispatcherTrait};
use collection_drop::types::SaleTerms;
use openzeppelin_interfaces::erc20::IERC20DispatcherTrait;
use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use super::utils::{
    ALICE, ALICE_PROOF, BOB, BOB_PROOF, CAROL, NO_PROOF, ORGANIZER, PRICE, ROOT, STRANGER,
    approve, create_drop, deploy_factory, deploy_token, free_drop, free_terms, paid_terms,
};

fn claim_as(d: IDropCollectionDispatcher, who: ContractAddress, quantity: u256, proof: Span<felt252>) {
    start_cheat_caller_address(d.contract_address, who);
    d.claim(quantity, proof);
    stop_cheat_caller_address(d.contract_address);
}

fn set_root(d: IDropCollectionDispatcher, root: felt252) {
    start_cheat_caller_address(d.contract_address, ORGANIZER());
    d.set_allowlist_root(root);
    stop_cheat_caller_address(d.contract_address);
}

fn nft(d: IDropCollectionDispatcher) -> IERC721Dispatcher {
    IERC721Dispatcher { contract_address: d.contract_address }
}

#[test]
fn a_free_claim_mints_sequential_tokens() {
    let d = free_drop(10);
    let mut spy = spy_events();
    claim_as(d, ALICE(), 2, NO_PROOF());
    assert_eq!(nft(d).owner_of(1), ALICE());
    assert_eq!(nft(d).owner_of(2), ALICE());
    assert_eq!(d.total_minted(), 2);
    assert_eq!(d.claimed_by(ALICE()), 2);
    spy
        .assert_emitted(
            @array![
                (
                    d.contract_address,
                    DropCollection::Event::Claimed(
                        Claimed { claimer: ALICE(), quantity: 2, first_token_id: 1, total_paid: 0 },
                    ),
                ),
            ],
        );
}

#[test]
fn a_paid_claim_pays_the_organizer_and_holds_nothing() {
    let token = deploy_token(ALICE(), 1000);
    let d = create_drop(deploy_factory(), 10, paid_terms(token.contract_address), 0);
    approve(token, ALICE(), d.contract_address, 300);
    claim_as(d, ALICE(), 3, NO_PROOF());
    assert_eq!(token.balance_of(ORGANIZER()), 3 * PRICE);
    assert_eq!(token.balance_of(ALICE()), 1000 - 3 * PRICE);
    assert_eq!(token.balance_of(d.contract_address), 0);
    assert_eq!(nft(d).balance_of(ALICE()), 3);
}

#[test]
#[should_panic(expected: 'ERC20: insufficient allowance')]
fn claim_without_enough_allowance_mints_nothing() {
    let token = deploy_token(ALICE(), 1000);
    let d = create_drop(deploy_factory(), 10, paid_terms(token.contract_address), 0);
    approve(token, ALICE(), d.contract_address, PRICE);
    claim_as(d, ALICE(), 2, NO_PROOF());
}

#[test]
#[should_panic(expected: 'Payment failed')]
fn a_token_that_returns_false_fails_the_claim() {
    let false_token = declare("FalseERC20").unwrap().contract_class();
    let (token, _) = false_token.deploy(@array![]).unwrap();
    let d = create_drop(deploy_factory(), 10, paid_terms(token), 0);
    claim_as(d, ALICE(), 1, NO_PROOF());
}

#[test]
fn the_organizer_can_claim_their_own_paid_drop() {
    let token = deploy_token(ORGANIZER(), 1000);
    let d = create_drop(deploy_factory(), 10, paid_terms(token.contract_address), 0);
    approve(token, ORGANIZER(), d.contract_address, PRICE);
    claim_as(d, ORGANIZER(), 1, NO_PROOF());
    assert_eq!(nft(d).owner_of(1), ORGANIZER());
    assert_eq!(token.balance_of(ORGANIZER()), 1000);
}

#[test]
#[should_panic(expected: 'Quantity must be positive')]
fn a_zero_quantity_claim_fails() {
    claim_as(free_drop(10), ALICE(), 0, NO_PROOF());
}

#[test]
#[should_panic(expected: 'Drop has not started')]
fn claim_before_the_start_fails() {
    let terms = SaleTerms { start_time: 100, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, 0);
    start_cheat_block_timestamp(d.contract_address, 99);
    claim_as(d, ALICE(), 1, NO_PROOF());
}

#[test]
fn claim_works_at_the_start_and_end_seconds() {
    let terms = SaleTerms { start_time: 100, end_time: 200, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, 0);
    start_cheat_block_timestamp(d.contract_address, 100);
    claim_as(d, ALICE(), 1, NO_PROOF());
    start_cheat_block_timestamp(d.contract_address, 200);
    claim_as(d, BOB(), 1, NO_PROOF());
    assert_eq!(d.total_minted(), 2);
}

#[test]
#[should_panic(expected: 'Drop has ended')]
fn claim_after_the_end_fails() {
    let terms = SaleTerms { start_time: 100, end_time: 200, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, 0);
    start_cheat_block_timestamp(d.contract_address, 201);
    claim_as(d, ALICE(), 1, NO_PROOF());
}

#[test]
fn a_listed_wallet_claims_with_its_proof() {
    let d = create_drop(deploy_factory(), 10, free_terms(), ROOT);
    claim_as(d, ALICE(), 1, ALICE_PROOF());
    claim_as(d, BOB(), 1, BOB_PROOF());
    assert_eq!(d.total_minted(), 2);
}

#[test]
#[should_panic(expected: 'Not on allowlist')]
fn a_wrong_proof_fails() {
    let d = create_drop(deploy_factory(), 10, free_terms(), ROOT);
    claim_as(d, ALICE(), 1, BOB_PROOF());
}

#[test]
#[should_panic(expected: 'Not on allowlist')]
fn an_unlisted_wallet_fails() {
    let d = create_drop(deploy_factory(), 10, free_terms(), ROOT);
    claim_as(d, STRANGER(), 1, ALICE_PROOF());
}

#[test]
fn a_one_address_root_takes_an_empty_proof() {
    let leaf = core::poseidon::poseidon_hash_span(
        array![core::poseidon::poseidon_hash_span(array![0x111].span())].span(),
    );
    let d = create_drop(deploy_factory(), 10, free_terms(), leaf);
    claim_as(d, ALICE(), 1, NO_PROOF());
    assert_eq!(d.total_minted(), 1);
}

#[test]
fn root_zero_is_open_to_everyone_and_ignores_the_proof() {
    let d = free_drop(10);
    claim_as(d, STRANGER(), 1, BOB_PROOF());
    assert_eq!(d.total_minted(), 1);
}

#[test]
fn the_organizer_can_open_an_allowlisted_drop() {
    let d = create_drop(deploy_factory(), 10, free_terms(), ROOT);
    let mut spy = spy_events();
    set_root(d, 0);
    claim_as(d, STRANGER(), 1, NO_PROOF());
    spy
        .assert_emitted(
            @array![
                (
                    d.contract_address,
                    DropCollection::Event::AllowlistRootSet(AllowlistRootSet { root: 0 }),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'Caller is not the organizer')]
fn only_the_organizer_sets_the_root() {
    let d = free_drop(10);
    start_cheat_caller_address(d.contract_address, STRANGER());
    d.set_allowlist_root(ROOT);
}

#[test]
fn replacing_the_root_keeps_claims_and_limits() {
    let terms = SaleTerms { max_per_wallet: 1, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, ROOT);
    claim_as(d, ALICE(), 1, ALICE_PROOF());
    let carol_leaf = core::poseidon::poseidon_hash_span(
        array![core::poseidon::poseidon_hash_span(array![0x333].span())].span(),
    );
    set_root(d, carol_leaf);
    claim_as(d, CAROL(), 1, NO_PROOF());
    assert_eq!(d.claimed_by(ALICE()), 1);
    assert_eq!(d.total_minted(), 2);
}

#[test]
#[should_panic(expected: 'Exceeds wallet limit')]
fn the_wallet_limit_counts_every_claim() {
    let terms = SaleTerms { max_per_wallet: 3, ..free_terms() };
    let d = create_drop(deploy_factory(), 10, terms, 0);
    claim_as(d, ALICE(), 2, NO_PROOF());
    claim_as(d, ALICE(), 2, NO_PROOF());
}

#[test]
fn the_supply_cap_can_be_reached_exactly() {
    let d = free_drop(3);
    claim_as(d, ALICE(), 3, NO_PROOF());
    assert_eq!(d.total_minted(), 3);
}

#[test]
#[should_panic(expected: 'Exceeds max supply')]
fn the_supply_cap_cannot_be_exceeded() {
    let d = free_drop(3);
    claim_as(d, ALICE(), 2, NO_PROOF());
    claim_as(d, BOB(), 2, NO_PROOF());
}

#[test]
fn open_edition_without_limit_keeps_minting() {
    let d = free_drop(0);
    claim_as(d, ALICE(), 5, NO_PROOF());
    claim_as(d, ALICE(), 5, NO_PROOF());
    assert_eq!(d.total_minted(), 10);
    assert_eq!(d.claimed_by(ALICE()), 10);
    assert_eq!(nft(d).owner_of(10), ALICE());
}

#[test]
fn tokens_transfer_like_any_erc721() {
    let d = free_drop(10);
    claim_as(d, ALICE(), 1, NO_PROOF());
    start_cheat_caller_address(d.contract_address, ALICE());
    nft(d).transfer_from(ALICE(), BOB(), 1);
    assert_eq!(nft(d).owner_of(1), BOB());
}
