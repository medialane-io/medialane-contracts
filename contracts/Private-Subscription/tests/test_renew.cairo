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
fn test_renew_spends_old_and_inserts_new() {
    let (c, id) = deploy_with_plan();
    c.subscribe(id, 0x1111, 0xAAAA);
    let old_nullifier = 0xdead01;
    c.renew(id, old_nullifier, 0x2222, 0xBBBB);
    assert!(c.is_nullifier_spent(old_nullifier), "old subscription nullifier spent");
    assert!(c.is_nullifier_spent(0xBBBB), "renew payment nullifier spent");
}

#[test]
#[should_panic(expected: 'Nullifier spent')]
fn test_renew_rejects_replayed_old_nullifier() {
    let (c, id) = deploy_with_plan();
    c.subscribe(id, 0x1111, 0xAAAA);
    c.renew(id, 0xdead02, 0x2222, 0xBBBB);
    c.renew(id, 0xdead02, 0x3333, 0xCCCC); // same old_nullifier
}

#[test]
#[should_panic(expected: 'Plan is inactive')]
fn test_renew_rejects_inactive_plan() {
    let (c, id) = deploy_with_plan();
    c.subscribe(id, 0x1111, 0xAAAA);
    start_cheat_caller_address(c.contract_address, CREATOR());
    c.set_plan_active(id, false);
    stop_cheat_caller_address(c.contract_address);
    c.renew(id, 0xdead03, 0x2222, 0xBBBB);
}
