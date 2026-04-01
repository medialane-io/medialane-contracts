use snforge_std::{
    start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp,
    stop_cheat_block_timestamp,
};
use openzeppelin_token::erc721::interface::{IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait};
use pop_protocol::interfaces::IPOPCollection::IPOPCollectionDispatcherTrait;
use super::utils::{
    deploy_factory, create_test_collection, ADMIN, ORGANIZER, STUDENT1, STUDENT2, STUDENT3,
};

// ── Allowlist ─────────────────────────────────────────────────────────────────

#[test]
fn test_organizer_can_add_to_allowlist() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.is_eligible(STUDENT1()), 'Should be eligible');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_student_cannot_add_to_allowlist() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.add_to_allowlist(STUDENT2());
    stop_cheat_caller_address(collection.contract_address);
}

#[test]
fn test_batch_add_to_allowlist() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.batch_add_to_allowlist(array![STUDENT1(), STUDENT2(), STUDENT3()].span());
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.is_eligible(STUDENT1()), 'S1 not eligible');
    assert(collection.is_eligible(STUDENT2()), 'S2 not eligible');
    assert(collection.is_eligible(STUDENT3()), 'S3 not eligible');
}

#[test]
fn test_remove_from_allowlist() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    collection.remove_from_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    assert(!collection.is_eligible(STUDENT1()), 'Should not be eligible');
}

// ── Claim (whitelist-only) ────────────────────────────────────────────────────

#[test]
fn test_whitelisted_student_can_claim() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.has_claimed(STUDENT1()), 'Should be claimed');
    assert(collection.total_minted() == 1, 'Total should be 1');
}

#[test]
#[should_panic(expected: ('Not on allowlist',))]
fn test_non_whitelisted_cannot_claim() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    // STUDENT1 is NOT on the whitelist
    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();
    stop_cheat_caller_address(collection.contract_address);
}

#[test]
#[should_panic(expected: ('Already claimed',))]
fn test_cannot_claim_twice() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();
    collection.claim(); // second claim panics
    stop_cheat_caller_address(collection.contract_address);
}

#[test]
fn test_total_minted_reflects_claims() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.batch_add_to_allowlist(array![STUDENT1(), STUDENT2(), STUDENT3()].span());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT2());
    collection.claim();
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.total_minted() == 2, 'Total should be 2');
}

// ── Claim deadline ────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Claim window closed',))]
fn test_cannot_claim_after_deadline() {
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
    use pop_protocol::interfaces::IPOPCollection::IPOPCollectionDispatcher;
    use super::utils::ADMIN;

    let collection_class = declare("POPCollection").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    // Constructor: name, symbol, base_uri, collection_id, platform_admin, organizer, claim_end_time
    ("Timed Event", "POP-T", "ipfs://t/", 1_u256, ADMIN(), ADMIN(), 1000_u64)
        .serialize(ref calldata);
    let (addr, _) = collection_class.deploy(@calldata).unwrap();
    let collection = IPOPCollectionDispatcher { contract_address: addr };

    start_cheat_caller_address(addr, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(addr);

    start_cheat_block_timestamp(addr, 2000);
    start_cheat_caller_address(addr, STUDENT1());
    collection.claim(); // past deadline, must panic
    stop_cheat_caller_address(addr);
    stop_cheat_block_timestamp(addr);
}

// ── Pause ─────────────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Collection is paused',))]
fn test_cannot_claim_when_paused() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    collection.set_paused(true);
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();
    stop_cheat_caller_address(collection.contract_address);
}

#[test]
fn test_can_claim_after_unpause() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    collection.set_paused(true);
    collection.set_paused(false);
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.has_claimed(STUDENT1()), 'Should be claimed');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_organizer_cannot_pause() {
    let factory = deploy_factory();

    // Register ORGANIZER as a provider, create a collection as them
    start_cheat_caller_address(factory.contract_address, ADMIN());
    factory.register_provider(ORGANIZER(), "Test Org", "https://test.org");
    stop_cheat_caller_address(factory.contract_address);

    let collection = create_test_collection(factory, ORGANIZER());

    // ORGANIZER does NOT have DEFAULT_ADMIN_ROLE so cannot pause
    start_cheat_caller_address(collection.contract_address, ORGANIZER());
    collection.set_paused(true);
    stop_cheat_caller_address(collection.contract_address);
}

// ── Admin mint ────────────────────────────────────────────────────────────────

#[test]
fn test_admin_mint_bypasses_allowlist() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    // STUDENT1 is NOT on the allowlist
    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.admin_mint(STUDENT1(), "");
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.has_claimed(STUDENT1()), 'Should be claimed');
}

#[test]
fn test_admin_mint_with_custom_uri() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.admin_mint(STUDENT1(), "ipfs://QmMaxScore/");
    stop_cheat_caller_address(collection.contract_address);

    let meta = IERC721MetadataDispatcher { contract_address: collection.contract_address };
    assert(meta.token_uri(1) == "ipfs://QmMaxScore/", 'Custom URI mismatch');
}

#[test]
#[should_panic(expected: ('Already claimed',))]
fn test_admin_cannot_double_mint() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.admin_mint(STUDENT1(), "");
    collection.admin_mint(STUDENT1(), ""); // second mint panics
    stop_cheat_caller_address(collection.contract_address);
}

// ── Per-token URI ─────────────────────────────────────────────────────────────

#[test]
fn test_claim_uses_base_uri_fallback() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN()); // base_uri = "ipfs://QmDemo/"

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim(); // mints token_id 1
    stop_cheat_caller_address(collection.contract_address);

    // No per-token URI set → falls back to base_uri + token_id
    let meta = IERC721MetadataDispatcher { contract_address: collection.contract_address };
    assert(meta.token_uri(1) == "ipfs://QmDemo/1", 'Base URI fallback wrong');
}

#[test]
fn test_set_token_uri_overrides_base_uri() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim(); // mints token_id 1
    stop_cheat_caller_address(collection.contract_address);

    // Admin upgrades the token to the "max score" variant
    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.set_token_uri(1, "ipfs://QmMaxScore/");
    stop_cheat_caller_address(collection.contract_address);

    let meta = IERC721MetadataDispatcher { contract_address: collection.contract_address };
    assert(meta.token_uri(1) == "ipfs://QmMaxScore/", 'Per-token URI wrong');
}

#[test]
fn test_set_base_uri_updates_fallback() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim(); // token_id 1
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.set_base_uri("ipfs://QmUpdated/");
    stop_cheat_caller_address(collection.contract_address);

    let meta = IERC721MetadataDispatcher { contract_address: collection.contract_address };
    assert(meta.token_uri(1) == "ipfs://QmUpdated/1", 'Updated base URI wrong');
}

#[test]
fn test_per_token_uri_not_affected_by_base_uri_update() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.batch_add_to_allowlist(array![STUDENT1(), STUDENT2()].span());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim(); // token_id 1 — standard
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT2());
    collection.claim(); // token_id 2 — will get custom URI
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.set_token_uri(2, "ipfs://QmDistinction/");
    collection.set_base_uri("ipfs://QmUpdated/"); // update base URI
    stop_cheat_caller_address(collection.contract_address);

    let meta = IERC721MetadataDispatcher { contract_address: collection.contract_address };
    // token 1 uses new base URI
    assert(meta.token_uri(1) == "ipfs://QmUpdated/1", 'Token 1 URI wrong');
    // token 2 keeps its custom URI, unaffected by base URI change
    assert(meta.token_uri(2) == "ipfs://QmDistinction/", 'Token 2 URI wrong');
}
