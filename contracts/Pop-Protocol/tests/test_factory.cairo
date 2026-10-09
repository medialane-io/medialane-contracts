use pop_protocol::events::CollectionCreated;
use pop_protocol::interfaces::{
    IPOPCollectionDispatcher, IPOPCollectionDispatcherTrait, IPOPFactoryDispatcherTrait,
};
use pop_protocol::pop_factory::POPFactory;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address,
};
use super::utils::{ORGANIZER, STRANGER, base_uri, create_collection, deploy_factory};

#[test]
fn anyone_can_create_and_becomes_organizer() {
    let factory = deploy_factory();
    start_cheat_caller_address(factory.contract_address, STRANGER());
    let address = factory.create_collection("Meetup", "MTP", base_uri(), 0);
    let c = IPOPCollectionDispatcher { contract_address: address };
    assert_eq!(c.organizer(), STRANGER());
    assert_eq!(factory.get_last_collection_id(), 1);
    assert_eq!(factory.get_collection_address(1), address);
}

#[test]
fn ids_increase_and_addresses_differ() {
    let factory = deploy_factory();
    let a = create_collection(factory, 0);
    let b = create_collection(factory, 0);
    assert_eq!(factory.get_last_collection_id(), 2);
    assert!(a.contract_address != b.contract_address);
}

#[test]
fn create_emits_everything_needed_to_rebuild() {
    let factory = deploy_factory();
    let mut spy = spy_events();
    let c = create_collection(factory, 1234);
    spy
        .assert_emitted(
            @array![
                (
                    factory.contract_address,
                    POPFactory::Event::CollectionCreated(
                        CollectionCreated {
                            collection_id: 1,
                            organizer: ORGANIZER(),
                            collection_address: c.contract_address,
                            name: "Pilot",
                            symbol: "PLT",
                            base_uri: base_uri(),
                            claim_end_time: 1234,
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'Name is required')]
fn create_requires_a_name() {
    let factory = deploy_factory();
    factory.create_collection("", "X", base_uri(), 0);
}

#[test]
fn a_zero_class_hash_cannot_be_deployed() {
    let factory = declare("POPFactory").unwrap().contract_class();
    assert!(factory.deploy(@array![0]).is_err());
}

#[test]
fn version_is_set() {
    assert_eq!(deploy_factory().version(), '1.0.0');
}
