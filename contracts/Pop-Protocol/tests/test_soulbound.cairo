use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use openzeppelin_token::erc721::interface::{IERC721DispatcherTrait, IERC721Dispatcher};
use super::utils::{deploy_factory, create_test_collection, ADMIN, STUDENT1, STUDENT2};

#[test]
#[should_panic(expected: ('SOULBOUND_TOKEN',))]
fn test_transfer_after_claim_reverts() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();

    let erc721 = IERC721Dispatcher { contract_address: collection.contract_address };
    erc721.transfer_from(STUDENT1(), STUDENT2(), 1); // must panic
    stop_cheat_caller_address(collection.contract_address);
}

#[test]
#[should_panic(expected: ('SOULBOUND_TOKEN',))]
fn test_safe_transfer_reverts() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim();

    let erc721 = IERC721Dispatcher { contract_address: collection.contract_address };
    erc721.safe_transfer_from(STUDENT1(), STUDENT2(), 1, array![].span());
    stop_cheat_caller_address(collection.contract_address);
}

#[test]
fn test_mint_succeeds() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.add_to_allowlist(STUDENT1());
    stop_cheat_caller_address(collection.contract_address);

    start_cheat_caller_address(collection.contract_address, STUDENT1());
    collection.claim(); // must not panic
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.total_minted() == 1, 'Mint should succeed');
}

#[test]
fn test_admin_mint_succeeds() {
    let factory = deploy_factory();
    let collection = create_test_collection(factory, ADMIN());

    start_cheat_caller_address(collection.contract_address, ADMIN());
    collection.admin_mint(STUDENT1(), "");
    stop_cheat_caller_address(collection.contract_address);

    assert(collection.total_minted() == 1, 'Admin mint should succeed');
}
