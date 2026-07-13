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

fn deploy_with_sub() -> (IPrivateSubscriptionDispatcher, felt252) {
    let class = declare("PrivateSubscription").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    let c = IPrivateSubscriptionDispatcher { contract_address: addr };
    start_cheat_caller_address(addr, CREATOR());
    let id = c.create_plan(1000, 2592000, TOKEN(), CREATOR(), 'GOLD', "ipfs://p");
    stop_cheat_caller_address(addr);
    c.subscribe(id, 0x1111, 0xAAAA);
    (c, c.current_root())
}

#[test]
fn test_verify_tier_passes_on_known_root() {
    let (c, root) = deploy_with_sub();
    // Reference build: proof_verified is permissive; known-root gate is real.
    assert!(c.verify_tier('GOLD', root, 0), "known root should pass");
}

#[test]
#[should_panic(expected: 'Unknown merkle root')]
fn test_verify_tier_rejects_unknown_root() {
    let (c, _root) = deploy_with_sub();
    c.verify_tier('GOLD', 0x1234dead, 0);
}
