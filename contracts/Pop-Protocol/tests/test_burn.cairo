use core::num::traits::Zero;
use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin_token::erc721::ERC721Component;
use pop_protocol::interfaces::{IPOPCollectionDispatcher, IPOPCollectionDispatcherTrait};
use pop_protocol::pop_collection::POPCollection;
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_caller_address, stop_cheat_caller_address,
};
use super::utils::{ALICE, ALICE_PROOF, ORGANIZER, ROOT, STRANGER, collection};

fn issued() -> (IPOPCollectionDispatcher, IERC721Dispatcher) {
    let c = collection();
    start_cheat_caller_address(c.contract_address, ORGANIZER());
    c.issue(ALICE(), "");
    stop_cheat_caller_address(c.contract_address);
    (c, IERC721Dispatcher { contract_address: c.contract_address })
}

fn burn_as(c: IPOPCollectionDispatcher, who: starknet::ContractAddress, token_id: u256) {
    start_cheat_caller_address(c.contract_address, who);
    c.burn(token_id);
    stop_cheat_caller_address(c.contract_address);
}

#[test]
fn the_holder_can_burn_their_credential() {
    let (c, nft) = issued();
    let mut spy = spy_events();
    burn_as(c, ALICE(), 1);
    assert_eq!(nft.balance_of(ALICE()), 0);
    assert_eq!(c.total_issued(), 1);
    spy
        .assert_emitted(
            @array![
                (
                    c.contract_address,
                    POPCollection::Event::ERC721Event(
                        ERC721Component::Event::Transfer(
                            ERC721Component::Transfer {
                                from: ALICE(), to: Zero::zero(), token_id: 1,
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'ERC721: invalid token ID')]
fn a_burned_credential_no_longer_exists() {
    let (c, nft) = issued();
    burn_as(c, ALICE(), 1);
    nft.owner_of(1);
}

#[test]
#[should_panic(expected: 'Caller is not the holder')]
fn a_stranger_cannot_burn() {
    let (c, _) = issued();
    burn_as(c, STRANGER(), 1);
}

#[test]
#[should_panic(expected: 'Caller is not the holder')]
fn the_organizer_cannot_burn_a_holders_credential() {
    let (c, _) = issued();
    burn_as(c, ORGANIZER(), 1);
}

#[test]
#[should_panic(expected: 'ERC721: invalid token ID')]
fn burning_a_token_that_does_not_exist_fails() {
    let c = collection();
    burn_as(c, ALICE(), 1);
}

#[test]
#[should_panic(expected: 'Already issued')]
fn a_burned_holder_cannot_claim_again() {
    let (c, _) = issued();
    burn_as(c, ALICE(), 1);
    start_cheat_caller_address(c.contract_address, ORGANIZER());
    c.set_allowlist_root(ROOT);
    stop_cheat_caller_address(c.contract_address);
    start_cheat_caller_address(c.contract_address, ALICE());
    c.claim(ALICE_PROOF());
}
