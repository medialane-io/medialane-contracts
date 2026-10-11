use collection_drop::drop_factory::DropFactory;
use collection_drop::events::DropCreated;
use collection_drop::interfaces::{
    IDropCollectionDispatcher, IDropCollectionDispatcherTrait, IDropFactoryDispatcherTrait,
};
use collection_drop::types::SaleTerms;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address,
};
use super::utils::{
    ORGANIZER, PRICE, ROOT, STRANGER, base_uri, create_drop, deploy_factory, free_terms,
};

#[test]
fn anyone_can_create_and_becomes_organizer() {
    let factory = deploy_factory();
    start_cheat_caller_address(factory.contract_address, STRANGER());
    let address = factory.create_drop("Mine", "MINE", base_uri(), 5, free_terms(), 0);
    let d = IDropCollectionDispatcher { contract_address: address };
    assert_eq!(d.organizer(), STRANGER());
    assert_eq!(factory.get_last_drop_id(), 1);
    assert_eq!(factory.get_drop_address(1), address);
}

#[test]
fn ids_increase_and_addresses_differ() {
    let factory = deploy_factory();
    let a = create_drop(factory, 5, free_terms(), 0);
    let b = create_drop(factory, 5, free_terms(), 0);
    assert_eq!(factory.get_last_drop_id(), 2);
    assert!(a.contract_address != b.contract_address);
}

#[test]
fn create_emits_every_creation_fact() {
    let factory = deploy_factory();
    let token: starknet::ContractAddress = 'TOKEN'.try_into().unwrap();
    let terms = SaleTerms { start_time: 10, end_time: 20, price: PRICE, payment_token: token, max_per_wallet: 2 };
    let mut spy = spy_events();
    let d = create_drop(factory, 50, terms, ROOT);
    spy
        .assert_emitted(
            @array![
                (
                    factory.contract_address,
                    DropFactory::Event::DropCreated(
                        DropCreated {
                            drop_id: 1,
                            organizer: ORGANIZER(),
                            collection_address: d.contract_address,
                            name: "Drop",
                            symbol: "DRP",
                            base_uri: base_uri(),
                            max_supply: 50,
                            terms,
                            allowlist_root: ROOT,
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'Name is required')]
fn create_requires_a_name() {
    deploy_factory().create_drop("", "X", base_uri(), 5, free_terms(), 0);
}

#[test]
#[should_panic(expected: 'Payment token required')]
fn a_paid_drop_needs_a_token() {
    let terms = SaleTerms { price: PRICE, ..free_terms() };
    deploy_factory().create_drop("Drop", "DRP", base_uri(), 5, terms, 0);
}

#[test]
#[should_panic(expected: 'Free drop names no token')]
fn a_free_drop_names_no_token() {
    let terms = SaleTerms { payment_token: 'TOKEN'.try_into().unwrap(), ..free_terms() };
    deploy_factory().create_drop("Drop", "DRP", base_uri(), 5, terms, 0);
}

#[test]
#[should_panic(expected: 'Invalid sale window')]
fn the_end_must_come_after_the_start() {
    let terms = SaleTerms { start_time: 20, end_time: 20, ..free_terms() };
    deploy_factory().create_drop("Drop", "DRP", base_uri(), 5, terms, 0);
}

#[test]
fn an_end_with_no_start_is_valid() {
    let terms = SaleTerms { start_time: 0, end_time: 20, ..free_terms() };
    let factory = deploy_factory();
    factory.create_drop("Drop", "DRP", base_uri(), 5, terms, 0);
    assert_eq!(factory.get_last_drop_id(), 1);
}

#[test]
fn a_zero_class_hash_cannot_be_deployed() {
    let factory = declare("DropFactory").unwrap().contract_class();
    assert!(factory.deploy(@array![0]).is_err());
}

#[test]
fn version_is_set() {
    assert_eq!(deploy_factory().version(), '1.0.0');
}
