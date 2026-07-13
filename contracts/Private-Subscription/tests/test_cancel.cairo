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
fn test_cancel_spends_nullifier() {
    let (c, id) = deploy_with_plan();
    c.subscribe(id, 0x1111, 0xAAAA);
    c.cancel(id, 0xdeadc1);
    assert!(c.is_nullifier_spent(0xdeadc1), "cancellation nullifier spent");
}

#[test]
#[should_panic(expected: 'Nullifier spent')]
fn test_double_cancel_reverts() {
    let (c, id) = deploy_with_plan();
    c.subscribe(id, 0x1111, 0xAAAA);
    c.cancel(id, 0xdeadc1);
    c.cancel(id, 0xdeadc1);
}
