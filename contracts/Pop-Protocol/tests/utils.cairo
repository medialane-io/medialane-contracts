use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use starknet::contract_address_const;

use pop_protocol::interfaces::IPOPFactory::{
    IPOPFactoryDispatcher, IPOPFactoryDispatcherTrait,
};
use pop_protocol::interfaces::IPOPCollection::{
    IPOPCollectionDispatcher, IPOPCollectionDispatcherTrait,
};
use pop_protocol::types::EventType;

// ── Test addresses ────────────────────────────────────────────────────────────

pub fn ADMIN() -> ContractAddress {
    contract_address_const::<'ADMIN'>()
}
pub fn ORGANIZER() -> ContractAddress {
    contract_address_const::<'ORGANIZER'>()
}
pub fn STUDENT1() -> ContractAddress {
    contract_address_const::<'STUDENT1'>()
}
pub fn STUDENT2() -> ContractAddress {
    contract_address_const::<'STUDENT2'>()
}
pub fn STUDENT3() -> ContractAddress {
    contract_address_const::<'STUDENT3'>()
}

// ── Deployment helpers ────────────────────────────────────────────────────────

pub fn deploy_factory() -> IPOPFactoryDispatcher {
    let collection_class = declare("POPCollection").unwrap().contract_class();
    let factory_class = declare("POPFactory").unwrap().contract_class();

    let mut calldata: Array<felt252> = array![];
    (ADMIN(), *collection_class.class_hash).serialize(ref calldata);

    let (factory_address, _) = factory_class.deploy(@calldata).unwrap();
    IPOPFactoryDispatcher { contract_address: factory_address }
}

/// Creates a standard Bootcamp collection via the factory as the given caller.
pub fn create_test_collection(
    factory: IPOPFactoryDispatcher, caller: ContractAddress,
) -> IPOPCollectionDispatcher {
    start_cheat_caller_address(factory.contract_address, caller);
    let addr = factory
        .create_collection(
            "Demo Bootcamp #1",
            "POP-DEMO",
            "ipfs://QmDemo/",
            EventType::Bootcamp,
            0,
        );
    stop_cheat_caller_address(factory.contract_address);

    IPOPCollectionDispatcher { contract_address: addr }
}
