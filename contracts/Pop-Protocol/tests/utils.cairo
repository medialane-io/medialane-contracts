use pop_protocol::interfaces::{
    IPOPCollectionDispatcher, IPOPFactoryDispatcher, IPOPFactoryDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

pub fn ORGANIZER() -> ContractAddress {
    'ORGANIZER'.try_into().unwrap()
}
pub fn STRANGER() -> ContractAddress {
    'STRANGER'.try_into().unwrap()
}
pub fn ALICE() -> ContractAddress {
    0x111.try_into().unwrap()
}
pub fn BOB() -> ContractAddress {
    0x222.try_into().unwrap()
}
pub fn CAROL() -> ContractAddress {
    0x333.try_into().unwrap()
}

/// Root of the tree over [0x111, 0x222, 0x333].
pub const ROOT: felt252 = 0x055671b388a2640bb77a4a14b1650b4e2b08731a6e1bd966a642ddbaf2f150cb;
pub fn ALICE_PROOF() -> Span<felt252> {
    array![
        0x03b85dadc24bd0f247859d1bdbefd71e59ec8c554f586cb92aa90a1070d08abe,
        0x03f24a6254d5b5f354998d1ad80fc04404b404232d43c44f2b25420044a96366,
    ]
        .span()
}
pub fn BOB_PROOF() -> Span<felt252> {
    array![
        0x03387b5ce16ea370105dca95f7939d6a98cebad5a91577c6ff57e4c864563d0a,
        0x03f24a6254d5b5f354998d1ad80fc04404b404232d43c44f2b25420044a96366,
    ]
        .span()
}
pub fn CAROL_PROOF() -> Span<felt252> {
    array![0x077a4a0f02dd99ad227cbb952c3e9fc6d3ec8f3b247a605649eb55d95c8ce73b].span()
}

pub fn base_uri() -> ByteArray {
    "ipfs://event.json"
}

pub fn deploy_factory() -> IPOPFactoryDispatcher {
    let collection = declare("POPCollection").unwrap().contract_class();
    let factory = declare("POPFactory").unwrap().contract_class();
    let (address, _) = factory.deploy(@array![(*collection.class_hash).into()]).unwrap();
    IPOPFactoryDispatcher { contract_address: address }
}

/// Creates a collection as ORGANIZER.
pub fn create_collection(
    factory: IPOPFactoryDispatcher, claim_end_time: u64,
) -> IPOPCollectionDispatcher {
    start_cheat_caller_address(factory.contract_address, ORGANIZER());
    let address = factory.create_collection("Pilot", "PLT", base_uri(), claim_end_time);
    stop_cheat_caller_address(factory.contract_address);
    IPOPCollectionDispatcher { contract_address: address }
}

pub fn collection() -> IPOPCollectionDispatcher {
    create_collection(deploy_factory(), 0)
}
