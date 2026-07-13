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
fn OTHER() -> ContractAddress {
    'OTHER'.try_into().unwrap()
}
fn TOKEN() -> ContractAddress {
    'TOKEN'.try_into().unwrap()
}

fn deploy() -> IPrivateSubscriptionDispatcher {
    let class = declare("PrivateSubscription").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    IPrivateSubscriptionDispatcher { contract_address: addr }
}

#[test]
fn test_create_plan_is_permissionless_and_monotonic() {
    let c = deploy();
    start_cheat_caller_address(c.contract_address, CREATOR());
    let id1 = c.create_plan(1000, 2592000, TOKEN(), CREATOR(), 'GOLD', "ipfs://plan1");
    let id2 = c.create_plan(0, 2592000, 0.try_into().unwrap(), CREATOR(), 'FREE', "ar://plan2");
    stop_cheat_caller_address(c.contract_address);
    assert!(id1 == 1 && id2 == 2, "monotonic ids");
    let p = c.get_plan(1);
    assert!(p.price == 1000 && p.active, "stored");
}

#[test]
#[should_panic(expected: 'URI must be ipfs or ar')]
fn test_create_plan_rejects_bad_uri() {
    let c = deploy();
    start_cheat_caller_address(c.contract_address, CREATOR());
    c.create_plan(1000, 2592000, TOKEN(), CREATOR(), 'GOLD', "https://x");
    stop_cheat_caller_address(c.contract_address);
}

#[test]
#[should_panic(expected: 'Paid plan requires token')]
fn test_paid_plan_requires_token() {
    let c = deploy();
    start_cheat_caller_address(c.contract_address, CREATOR());
    c.create_plan(1000, 2592000, 0.try_into().unwrap(), CREATOR(), 'GOLD', "ipfs://x");
    stop_cheat_caller_address(c.contract_address);
}

#[test]
#[should_panic(expected: 'Only plan creator')]
fn test_only_creator_can_toggle() {
    let c = deploy();
    start_cheat_caller_address(c.contract_address, CREATOR());
    c.create_plan(1000, 2592000, TOKEN(), CREATOR(), 'GOLD', "ipfs://x");
    stop_cheat_caller_address(c.contract_address);
    start_cheat_caller_address(c.contract_address, OTHER());
    c.set_plan_active(1, false);
    stop_cheat_caller_address(c.contract_address);
}

#[test]
fn test_reference_build_markers() {
    let c = deploy();
    assert!(c.is_reference_build(), "reference build");
    assert!(c.contract_version() == '0.1.0-ref', "version");
}
