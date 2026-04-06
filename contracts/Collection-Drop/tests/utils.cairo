use snforge_std_deprecated::{declare, ContractClassTrait, DeclareResultTrait};
use snforge_std_deprecated::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use starknet::contract_address_const;

use collection_drop::interfaces::IDropFactory::{IDropFactoryDispatcher, IDropFactoryDispatcherTrait};
use collection_drop::interfaces::IDropCollection::{
    IDropCollectionDispatcher, IDropCollectionDispatcherTrait,
};
use collection_drop::types::ClaimConditions;
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

// ── Test addresses ────────────────────────────────────────────────────────────

pub fn ADMIN() -> ContractAddress {
    contract_address_const::<'ADMIN'>()
}
pub fn ORGANIZER() -> ContractAddress {
    contract_address_const::<'ORGANIZER'>()
}
pub fn MINTER1() -> ContractAddress {
    contract_address_const::<'MINTER1'>()
}
pub fn MINTER2() -> ContractAddress {
    contract_address_const::<'MINTER2'>()
}
pub fn MINTER3() -> ContractAddress {
    contract_address_const::<'MINTER3'>()
}

// ── Default helpers ───────────────────────────────────────────────────────────

pub fn free_conditions() -> ClaimConditions {
    ClaimConditions {
        start_time: 0,
        end_time: 0,
        price: 0,
        payment_token: contract_address_const::<0>(),
        max_quantity_per_wallet: 5,
    }
}

pub fn paid_conditions(payment_token: ContractAddress) -> ClaimConditions {
    ClaimConditions {
        start_time: 0,
        end_time: 0,
        price: 1000_u256,
        payment_token,
        max_quantity_per_wallet: 3,
    }
}

// ── Deployment helpers ────────────────────────────────────────────────────────

pub fn deploy_factory() -> IDropFactoryDispatcher {
    let collection_class = declare("DropCollection").unwrap().contract_class();
    let factory_class = declare("DropFactory").unwrap().contract_class();

    let mut calldata: Array<felt252> = array![];
    (ADMIN(), *collection_class.class_hash).serialize(ref calldata);

    let (factory_address, _) = factory_class.deploy(@calldata).unwrap();
    IDropFactoryDispatcher { contract_address: factory_address }
}

pub fn deploy_mock_erc20(recipient: ContractAddress, supply: u256) -> IERC20Dispatcher {
    let erc20_class = declare("MockERC20").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    (recipient, supply).serialize(ref calldata);
    let (addr, _) = erc20_class.deploy(@calldata).unwrap();
    IERC20Dispatcher { contract_address: addr }
}

/// Deploys a free drop via the factory as the given caller.
pub fn create_free_drop(
    factory: IDropFactoryDispatcher, caller: ContractAddress,
) -> IDropCollectionDispatcher {
    start_cheat_caller_address(factory.contract_address, caller);
    let addr = factory
        .create_drop("Limited Edition #1", "DROP1", "ipfs://QmDrop/", 100_u256, free_conditions());
    stop_cheat_caller_address(factory.contract_address);
    IDropCollectionDispatcher { contract_address: addr }
}

/// Deploys an open-edition (unlimited supply) free drop.
pub fn create_open_drop(
    factory: IDropFactoryDispatcher, caller: ContractAddress,
) -> IDropCollectionDispatcher {
    start_cheat_caller_address(factory.contract_address, caller);
    let addr = factory
        .create_drop("Open Edition", "OPEN", "ipfs://QmOpen/", 0_u256, free_conditions());
    stop_cheat_caller_address(factory.contract_address);
    IDropCollectionDispatcher { contract_address: addr }
}
