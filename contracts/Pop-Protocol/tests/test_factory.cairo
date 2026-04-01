use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use pop_protocol::types::EventType;
use pop_protocol::interfaces::IPOPFactory::IPOPFactoryDispatcherTrait;
use super::utils::{deploy_factory, ADMIN, ORGANIZER, STUDENT1};

// ── Provider management ───────────────────────────────────────────────────────

#[test]
fn test_admin_can_register_provider() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_provider(ORGANIZER(), "Acme Corp", "https://acme.io");
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.is_active_provider(ORGANIZER()), 'Provider should be active');
    let record = factory.get_provider(ORGANIZER());
    assert(record.active, 'Record active flag wrong');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_non_admin_cannot_register_provider() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, STUDENT1());
    factory.register_provider(ORGANIZER(), "Rogue", "https://rogue.io");
    stop_cheat_caller_address(factory.contract_address);
}

#[test]
fn test_admin_can_revoke_provider() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_provider(ORGANIZER(), "Acme Corp", "https://acme.io");
    factory.revoke_provider(ORGANIZER());
    stop_cheat_caller_address(factory.contract_address);

    assert(!factory.is_active_provider(ORGANIZER()), 'Provider should be inactive');
}

// ── Collection creation ───────────────────────────────────────────────────────

#[test]
fn test_admin_can_create_collection() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    let addr = factory
        .create_collection(
            "Demo Bootcamp #1", "POP-DEMO", "ipfs://QmDemo/", EventType::Bootcamp, 0,
        );
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_last_collection_id() == 1, 'ID should be 1');
    assert(factory.get_collection_address(1) == addr, 'Address mismatch');
}

#[test]
fn test_collection_id_increments() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.create_collection("Event A", "POP-A", "ipfs://A/", EventType::Event, 0);
    factory.create_collection("Event B", "POP-B", "ipfs://B/", EventType::Event, 0);
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_last_collection_id() == 2, 'ID should be 2');
}

#[test]
fn test_registered_provider_can_create_collection() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_provider(ORGANIZER(), "Acme Corp", "https://acme.io");
    stop_cheat_caller_address(factory.contract_address);

    start_cheat_caller_address(factory.contract_address, ORGANIZER());
    let addr = factory
        .create_collection(
            "Org Bootcamp", "POP-ORG", "ipfs://org/", EventType::Bootcamp, 0,
        );
    stop_cheat_caller_address(factory.contract_address);

    let record = factory.get_collection(1);
    assert(record.organizer == ORGANIZER(), 'Wrong organizer');
    assert(record.collection_address == addr, 'Wrong address');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unregistered_address_cannot_create_collection() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, STUDENT1());
    factory.create_collection("Rogue Collection", "RGE", "ipfs://rogue/", EventType::Event, 0);
    stop_cheat_caller_address(factory.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_revoked_provider_cannot_create_collection() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_provider(ORGANIZER(), "Test Org", "https://test.org");
    factory.revoke_provider(ORGANIZER());
    stop_cheat_caller_address(factory.contract_address);

    start_cheat_caller_address(factory.contract_address, ORGANIZER());
    factory.create_collection("Ghost Event", "GHO", "ipfs://ghost/", EventType::Event, 0);
    stop_cheat_caller_address(factory.contract_address);
}

// ── Provider → collections index ─────────────────────────────────────────────

#[test]
fn test_provider_collection_count() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.create_collection("Event A", "POP-A", "ipfs://A/", EventType::Event, 0);
    factory.create_collection("Event B", "POP-B", "ipfs://B/", EventType::Class, 0);
    factory.create_collection("Event C", "POP-C", "ipfs://C/", EventType::Quest, 0);
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_provider_collection_count(ADMIN()) == 3, 'Count should be 3');
}

#[test]
fn test_provider_collection_ids_pagination() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.create_collection("Event A", "POP-A", "ipfs://A/", EventType::Event, 0);
    factory.create_collection("Event B", "POP-B", "ipfs://B/", EventType::Event, 0);
    factory.create_collection("Event C", "POP-C", "ipfs://C/", EventType::Event, 0);
    stop_cheat_caller_address(factory.contract_address);

    // First page: 2 items
    let page1 = factory.get_provider_collection_ids(ADMIN(), 0, 2);
    assert(page1.len() == 2, 'Page1 should have 2 items');
    assert(*page1.at(0) == 1, 'First ID wrong');
    assert(*page1.at(1) == 2, 'Second ID wrong');

    // Second page: remaining 1 item
    let page2 = factory.get_provider_collection_ids(ADMIN(), 2, 2);
    assert(page2.len() == 1, 'Page2 should have 1 item');
    assert(*page2.at(0) == 3, 'Third ID wrong');
}

#[test]
fn test_provider_collections_isolated_between_providers() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.create_collection("Admin Event", "POP-ADM", "ipfs://adm/", EventType::Event, 0);
    factory.register_provider(ORGANIZER(), "Acme Corp", "https://acme.io");
    stop_cheat_caller_address(factory.contract_address);

    start_cheat_caller_address(factory.contract_address, ORGANIZER());
    factory.create_collection("Org Class", "POP-ORG", "ipfs://org/", EventType::Class, 0);
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_provider_collection_count(ADMIN()) == 1, 'Admin should have 1');
    assert(factory.get_provider_collection_count(ORGANIZER()) == 1, 'Org should have 1');

    let org_ids = factory.get_provider_collection_ids(ORGANIZER(), 0, 10);
    assert(*org_ids.at(0) == 2, 'Org collection ID wrong');
}
