use snforge_std_deprecated::{start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp};
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin_token::erc721::interface::{IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait};
use openzeppelin_token::erc20::interface::IERC20DispatcherTrait;
use collection_drop::interfaces::IDropCollection::IDropCollectionDispatcherTrait;
use collection_drop::interfaces::IDropFactory::IDropFactoryDispatcherTrait;
use collection_drop::types::ClaimConditions;
use starknet::contract_address_const;
use super::utils::{
    deploy_factory, deploy_mock_erc20, create_free_drop, create_open_drop, free_conditions,
    paid_conditions, ADMIN, ORGANIZER, MINTER1, MINTER2, MINTER3,
};

// ── Basic mint ────────────────────────────────────────────────────────────────

#[test]
fn test_free_claim_mints_tokens() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());
    let erc721 = IERC721Dispatcher { contract_address: drop.contract_address };

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(2);
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.total_minted() == 2, 'Total minted wrong');
    assert(drop.minted_by_wallet(MINTER1()) == 2, 'Wallet minted wrong');
    assert(erc721.owner_of(1) == MINTER1(), 'Token 1 owner wrong');
    assert(erc721.owner_of(2) == MINTER1(), 'Token 2 owner wrong');
}

#[test]
fn test_token_uri_uses_base_uri() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());
    let meta = IERC721MetadataDispatcher { contract_address: drop.contract_address };

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(drop.contract_address);

    assert(meta.token_uri(1) == "ipfs://QmDrop/1", 'Token URI wrong');
}

#[test]
fn test_per_token_uri_override() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());
    let meta = IERC721MetadataDispatcher { contract_address: drop.contract_address };

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(drop.contract_address);

    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_token_uri(1, "ipfs://QmCustom/1");
    stop_cheat_caller_address(drop.contract_address);

    assert(meta.token_uri(1) == "ipfs://QmCustom/1", 'Custom URI wrong');
}

// ── Supply cap ────────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Exceeds max supply',))]
fn test_cannot_exceed_max_supply() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN()); // max_supply = 100

    // Mint 99 via admin
    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.admin_mint(MINTER2(), 99, "");
    stop_cheat_caller_address(drop.contract_address);

    // Try to mint 2 more — only 1 remaining
    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(2);
    stop_cheat_caller_address(drop.contract_address);
}

#[test]
fn test_remaining_supply_decrements() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN()); // max_supply = 100

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(3);
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.remaining_supply() == 97, 'Remaining supply wrong');
}

#[test]
fn test_open_edition_has_unlimited_supply() {
    let factory = deploy_factory();
    let drop = create_open_drop(factory, ADMIN()); // max_supply = 0

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(5);
    stop_cheat_caller_address(drop.contract_address);

    // remaining_supply returns sentinel value 0xffff... for open editions
    let remaining = drop.remaining_supply();
    assert(remaining > 1000000_u256, 'Should be unlimited');
}

// ── Per-wallet limit ──────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Exceeds wallet limit',))]
fn test_wallet_limit_enforced() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN()); // max_quantity_per_wallet = 5

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(5); // fine
    drop.claim(1); // exceeds limit
    stop_cheat_caller_address(drop.contract_address);
}

#[test]
fn test_different_wallets_can_mint_independently() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(5);
    stop_cheat_caller_address(drop.contract_address);

    start_cheat_caller_address(drop.contract_address, MINTER2());
    drop.claim(5);
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.total_minted() == 10, 'Total minted wrong');
}

// ── Time gates ────────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Drop has not started',))]
fn test_cannot_claim_before_start() {
    let factory = deploy_factory();

    let conditions = ClaimConditions {
        start_time: 1000,
        end_time: 0,
        price: 0,
        payment_token: contract_address_const::<0>(),
        max_quantity_per_wallet: 5,
    };

    start_cheat_caller_address(factory.contract_address, ADMIN());
    let addr = factory.create_drop("Timed Drop", "TD", "ipfs://TD/", 100_u256, conditions);
    stop_cheat_caller_address(factory.contract_address);

    let drop = collection_drop::interfaces::IDropCollection::IDropCollectionDispatcher {
        contract_address: addr,
    };

    start_cheat_block_timestamp(addr, 500); // before start_time 1000
    start_cheat_caller_address(addr, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(addr);
    stop_cheat_block_timestamp(addr);
}

#[test]
#[should_panic(expected: ('Drop has ended',))]
fn test_cannot_claim_after_end() {
    let factory = deploy_factory();

    let conditions = ClaimConditions {
        start_time: 0,
        end_time: 500,
        price: 0,
        payment_token: contract_address_const::<0>(),
        max_quantity_per_wallet: 5,
    };

    start_cheat_caller_address(factory.contract_address, ADMIN());
    let addr = factory.create_drop("Expired Drop", "EXP", "ipfs://EXP/", 100_u256, conditions);
    stop_cheat_caller_address(factory.contract_address);

    let drop = collection_drop::interfaces::IDropCollection::IDropCollectionDispatcher {
        contract_address: addr,
    };

    start_cheat_block_timestamp(addr, 1000); // after end_time 500
    start_cheat_caller_address(addr, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(addr);
    stop_cheat_block_timestamp(addr);
}

// ── Allowlist ─────────────────────────────────────────────────────────────────

#[test]
fn test_allowlist_gating() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    // Enable allowlist
    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_allowlist_enabled(true);
    drop.add_to_allowlist(MINTER1());
    stop_cheat_caller_address(drop.contract_address);

    // Allowlisted address can claim
    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.total_minted() == 1, 'Should be minted');
}

#[test]
#[should_panic(expected: ('Not on allowlist',))]
fn test_non_allowlisted_blocked() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_allowlist_enabled(true);
    stop_cheat_caller_address(drop.contract_address);

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(drop.contract_address);
}

#[test]
fn test_batch_allowlist() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_allowlist_enabled(true);
    drop.batch_add_to_allowlist(array![MINTER1(), MINTER2(), MINTER3()].span());
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.is_allowlisted(MINTER1()), 'MINTER1 not allowlisted');
    assert(drop.is_allowlisted(MINTER2()), 'MINTER2 not allowlisted');
    assert(drop.is_allowlisted(MINTER3()), 'MINTER3 not allowlisted');
}

// ── Paid drop ─────────────────────────────────────────────────────────────────

#[test]
fn test_paid_claim_transfers_tokens() {
    let factory = deploy_factory();
    let erc20 = deploy_mock_erc20(MINTER1(), 10000_u256);

    let conditions = paid_conditions(erc20.contract_address);
    start_cheat_caller_address(factory.contract_address, ADMIN());
    let addr = factory
        .create_drop("Paid Drop", "PAID", "ipfs://PAID/", 100_u256, conditions);
    stop_cheat_caller_address(factory.contract_address);

    let drop = collection_drop::interfaces::IDropCollection::IDropCollectionDispatcher {
        contract_address: addr,
    };

    // Approve and claim
    start_cheat_caller_address(erc20.contract_address, MINTER1());
    erc20.approve(addr, 3000_u256); // price=1000 × qty=3
    stop_cheat_caller_address(erc20.contract_address);

    start_cheat_caller_address(addr, MINTER1());
    drop.claim(3);
    stop_cheat_caller_address(addr);

    assert(drop.total_minted() == 3, 'Should have minted 3');
    assert(erc20.balance_of(addr) == 3000_u256, 'Contract should hold payment');
}

#[test]
fn test_organizer_can_withdraw_payments() {
    let factory = deploy_factory();
    let erc20 = deploy_mock_erc20(MINTER1(), 10000_u256);

    let conditions = paid_conditions(erc20.contract_address);
    start_cheat_caller_address(factory.contract_address, ADMIN());
    let addr = factory
        .create_drop("Paid Drop", "PAID", "ipfs://PAID/", 100_u256, conditions);
    stop_cheat_caller_address(factory.contract_address);

    let drop = collection_drop::interfaces::IDropCollection::IDropCollectionDispatcher {
        contract_address: addr,
    };

    start_cheat_caller_address(erc20.contract_address, MINTER1());
    erc20.approve(addr, 2000_u256);
    stop_cheat_caller_address(erc20.contract_address);

    start_cheat_caller_address(addr, MINTER1());
    drop.claim(2);
    stop_cheat_caller_address(addr);

    let admin_balance_before = erc20.balance_of(ADMIN());

    start_cheat_caller_address(addr, ADMIN());
    drop.withdraw_payments();
    stop_cheat_caller_address(addr);

    assert(erc20.balance_of(addr) == 0, 'Contract should be drained');
    assert(erc20.balance_of(ADMIN()) == admin_balance_before + 2000_u256, 'Admin balance wrong');
}

// ── Pause ─────────────────────────────────────────────────────────────────────

#[test]
#[should_panic(expected: ('Drop is paused',))]
fn test_claim_blocked_when_paused() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_paused(true);
    stop_cheat_caller_address(drop.contract_address);

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(drop.contract_address);
}

#[test]
fn test_unpause_allows_claim() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_paused(true);
    drop.set_paused(false);
    stop_cheat_caller_address(drop.contract_address);

    start_cheat_caller_address(drop.contract_address, MINTER1());
    drop.claim(1);
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.total_minted() == 1, 'Should mint after unpause');
}

// ── Admin mint ────────────────────────────────────────────────────────────────

#[test]
fn test_admin_mint_bypasses_conditions() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    // Enable allowlist — admin_mint should bypass it
    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_allowlist_enabled(true);
    drop.admin_mint(MINTER1(), 10, "");
    stop_cheat_caller_address(drop.contract_address);

    assert(drop.total_minted() == 10, 'Admin mint bypassed allowlist');
}

// ── Phase update ──────────────────────────────────────────────────────────────

#[test]
fn test_organizer_can_update_conditions() {
    let factory = deploy_factory();
    let drop = create_free_drop(factory, ADMIN());

    let new_conditions = ClaimConditions {
        start_time: 0,
        end_time: 0,
        price: 0,
        payment_token: contract_address_const::<0>(),
        max_quantity_per_wallet: 1, // tightened limit
    };

    start_cheat_caller_address(drop.contract_address, ADMIN());
    drop.set_claim_conditions(new_conditions);
    stop_cheat_caller_address(drop.contract_address);

    let conditions = drop.get_claim_conditions();
    assert(conditions.max_quantity_per_wallet == 1, 'Conditions not updated');
}
