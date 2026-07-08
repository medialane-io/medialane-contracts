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

fn deploy() -> IPrivateSubscriptionDispatcher {
    let class = declare("PrivateSubscription").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    IPrivateSubscriptionDispatcher { contract_address: addr }
}

#[test]
fn test_full_lifecycle_two_subscribers_independent_commitments() {
    let c = deploy();
    start_cheat_caller_address(c.contract_address, CREATOR());
    let id = c.create_plan(1000, 2592000, TOKEN(), CREATOR(), 'GOLD', "ipfs://p");
    stop_cheat_caller_address(c.contract_address);

    c.subscribe(id, 0x1111, 0xA1);
    let r1 = c.current_root();
    c.subscribe(id, 0x2222, 0xA2);
    let r2 = c.current_root();
    assert!(r1 != r2, "each subscription advances the root");
    assert!(c.is_known_root(r1) && c.is_known_root(r2), "both roots in window");

    c.renew(id, 0xB1, 0x3333, 0xA3);
    c.cancel(id, 0xB2);
    assert!(c.is_nullifier_spent(0xB2), "cancel recorded");
}

#[test]
fn test_free_plan_zero_price_no_token() {
    let c = deploy();
    start_cheat_caller_address(c.contract_address, CREATOR());
    let id = c.create_plan(0, 2592000, 0.try_into().unwrap(), CREATOR(), 'FREE', "ipfs://free");
    stop_cheat_caller_address(c.contract_address);
    c.subscribe(id, 0x9999, 0xF1);
    assert!(c.is_nullifier_spent(0xF1), "free subscribe still consumes a nullifier");
}
