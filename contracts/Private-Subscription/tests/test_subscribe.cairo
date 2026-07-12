use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use private_subscription::interface::{
    IPrivateSubscriptionDispatcher, IPrivateSubscriptionDispatcherTrait,
};

fn CREATOR() -> ContractAddress {
    'CREATOR'.try_into().unwrap()
}
fn TOKEN() -> ContractAddress {
    'TOKEN'.try_into().unwrap()
}

fn deploy_with_plan() -> (IPrivateSubscriptionDispatcher, u256) {
    let class = declare("PrivateSubscription").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    let c = IPrivateSubscriptionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, CREATOR());
    let id = c.create_plan(1000, 2592000, TOKEN(), CREATOR(), 'GOLD', "ipfs://p");
    stop_cheat_caller_address(addr);
    (c, id)
}

#[test]
fn test_subscribe_inserts_commitment_and_advances_root() {
    let (c, id) = deploy_with_plan();
    let root_before = c.current_root();
    c.subscribe(id, 0x1111, 0xAAAA);
    assert!(c.current_root() != root_before, "root advanced");
    assert!(c.is_known_root(c.current_root()), "root known");
    assert!(c.is_nullifier_spent(0xAAAA), "payment nullifier spent");
}

#[test]
#[should_panic(expected: 'Nullifier spent')]
fn test_subscribe_rejects_replayed_payment_nullifier() {
    let (c, id) = deploy_with_plan();
    c.subscribe(id, 0x1111, 0xAAAA);
    c.subscribe(id, 0x2222, 0xAAAA); // same payment nullifier
}

#[test]
#[should_panic(expected: 'Plan is inactive')]
fn test_subscribe_rejects_inactive_plan() {
    let (c, id) = deploy_with_plan();
    start_cheat_caller_address(c.contract_address, CREATOR());
    c.set_plan_active(id, false);
    stop_cheat_caller_address(c.contract_address);
    c.subscribe(id, 0x1111, 0xAAAA);
}

#[test]
#[should_panic(expected: 'Plan does not exist')]
fn test_subscribe_rejects_missing_plan() {
    let (c, _) = deploy_with_plan();
    c.subscribe(999, 0x1111, 0xAAAA);
}

#[test]
fn test_subscribe_counts_when_opted_in() {
    let (c, id) = deploy_with_plan();
    start_cheat_caller_address(c.contract_address, CREATOR());
    c.set_public_optin(id, true);
    stop_cheat_caller_address(c.contract_address);
    c.subscribe(id, 0x1111, 0xAAAA);
    assert!(c.plan_active_count(id) == 1, "counter incremented");
}
