use snforge_std_deprecated::{start_cheat_caller_address, stop_cheat_caller_address};
use collection_drop::interfaces::IDropFactory::IDropFactoryDispatcherTrait;
use collection_drop::types::ClaimConditions;
use starknet::contract_address_const;
use super::utils::{deploy_factory, free_conditions, ADMIN, ORGANIZER, MINTER1};

// ── Organizer management ──────────────────────────────────────────────────────

#[test]
fn test_admin_can_register_organizer() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_organizer(ORGANIZER(), "Acme Corp");
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.is_active_organizer(ORGANIZER()), 'Should be active');
    let record = factory.get_organizer(ORGANIZER());
    assert(record.active, 'Record active wrong');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_non_admin_cannot_register_organizer() {
    let factory = deploy_factory();
    start_cheat_caller_address(factory.contract_address, MINTER1());
    factory.register_organizer(ORGANIZER(), "Rogue");
    stop_cheat_caller_address(factory.contract_address);
}

#[test]
fn test_admin_can_revoke_organizer() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_organizer(ORGANIZER(), "Acme Corp");
    factory.revoke_organizer(ORGANIZER());
    stop_cheat_caller_address(factory.contract_address);

    assert(!factory.is_active_organizer(ORGANIZER()), 'Should be inactive');
}

// ── Drop creation ─────────────────────────────────────────────────────────────

#[test]
fn test_admin_can_create_drop() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    let addr = factory
        .create_drop("Limited Edition #1", "DROP1", "ipfs://QmTest/", 100_u256, free_conditions());
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_last_drop_id() == 1, 'ID should be 1');
    assert(factory.get_drop_address(1) == addr, 'Address mismatch');

    let record = factory.get_drop(1);
    assert(record.max_supply == 100, 'Max supply mismatch');
    assert(record.organizer == ADMIN(), 'Organizer mismatch');
}

#[test]
fn test_registered_organizer_can_create_drop() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_organizer(ORGANIZER(), "Acme Corp");
    stop_cheat_caller_address(factory.contract_address);

    start_cheat_caller_address(factory.contract_address, ORGANIZER());
    factory
        .create_drop("Acme Drop", "ACME", "ipfs://QmAcme/", 500_u256, free_conditions());
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_last_drop_id() == 1, 'ID should be 1');
    let count = factory.get_organizer_drop_count(ORGANIZER());
    assert(count == 1, 'Drop count should be 1');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unregistered_cannot_create_drop() {
    let factory = deploy_factory();
    start_cheat_caller_address(factory.contract_address, MINTER1());
    factory.create_drop("Rogue Drop", "RGE", "ipfs://QmRogue/", 10_u256, free_conditions());
    stop_cheat_caller_address(factory.contract_address);
}

#[test]
fn test_multiple_drops_indexed_per_organizer() {
    let factory = deploy_factory();

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.create_drop("Drop A", "DA", "ipfs://A/", 100_u256, free_conditions());
    factory.create_drop("Drop B", "DB", "ipfs://B/", 200_u256, free_conditions());
    factory.create_drop("Drop C", "DC", "ipfs://C/", 300_u256, free_conditions());
    stop_cheat_caller_address(factory.contract_address);

    assert(factory.get_last_drop_id() == 3, 'Should have 3 drops');
    let count = factory.get_organizer_drop_count(ADMIN());
    assert(count == 3, 'Organizer count wrong');

    let ids = factory.get_organizer_drop_ids(ADMIN(), 0, 3);
    assert(*ids.at(0) == 1, 'First ID wrong');
    assert(*ids.at(1) == 2, 'Second ID wrong');
    assert(*ids.at(2) == 3, 'Third ID wrong');
}

#[test]
#[should_panic(expected: ('Payment token required',))]
fn test_paid_drop_requires_payment_token() {
    let factory = deploy_factory();

    let bad_conditions = ClaimConditions {
        start_time: 0,
        end_time: 0,
        price: 1000_u256,
        payment_token: contract_address_const::<0>(),
        max_quantity_per_wallet: 5,
    };

    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.create_drop("Bad Drop", "BAD", "ipfs://Bad/", 100_u256, bad_conditions);
    stop_cheat_caller_address(factory.contract_address);
}
