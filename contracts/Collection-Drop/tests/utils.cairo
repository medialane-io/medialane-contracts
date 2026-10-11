use collection_drop::interfaces::{
    IDropCollectionDispatcher, IDropFactoryDispatcher, IDropFactoryDispatcherTrait,
};
use collection_drop::types::SaleTerms;
use core::num::traits::Zero;
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
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

/// Root of the tree over [0x111, 0x222, 0x333] (same vector as Pop-Protocol).
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
pub fn NO_PROOF() -> Span<felt252> {
    array![].span()
}

pub const PRICE: u256 = 100;

pub fn base_uri() -> ByteArray {
    "ipfs://drop/"
}

pub fn free_terms() -> SaleTerms {
    SaleTerms { start_time: 0, end_time: 0, price: 0, payment_token: Zero::zero(), max_per_wallet: 0 }
}

pub fn paid_terms(token: ContractAddress) -> SaleTerms {
    SaleTerms { start_time: 0, end_time: 0, price: PRICE, payment_token: token, max_per_wallet: 0 }
}

pub fn deploy_factory() -> IDropFactoryDispatcher {
    let collection = declare("DropCollection").unwrap().contract_class();
    let factory = declare("DropFactory").unwrap().contract_class();
    let (address, _) = factory.deploy(@array![(*collection.class_hash).into()]).unwrap();
    IDropFactoryDispatcher { contract_address: address }
}

/// Creates a drop as ORGANIZER.
pub fn create_drop(
    factory: IDropFactoryDispatcher, max_supply: u256, terms: SaleTerms, root: felt252,
) -> IDropCollectionDispatcher {
    start_cheat_caller_address(factory.contract_address, ORGANIZER());
    let address = factory.create_drop("Drop", "DRP", base_uri(), max_supply, terms, root);
    stop_cheat_caller_address(factory.contract_address);
    IDropCollectionDispatcher { contract_address: address }
}

pub fn free_drop(max_supply: u256) -> IDropCollectionDispatcher {
    create_drop(deploy_factory(), max_supply, free_terms(), 0)
}

/// A token holding `amount` for `holder`.
pub fn deploy_token(holder: ContractAddress, amount: u256) -> IERC20Dispatcher {
    let token = declare("MockERC20").unwrap().contract_class();
    let mut calldata = array![holder.into()];
    amount.serialize(ref calldata);
    let (address, _) = token.deploy(@calldata).unwrap();
    IERC20Dispatcher { contract_address: address }
}

pub fn approve(token: IERC20Dispatcher, owner: ContractAddress, spender: ContractAddress, amount: u256) {
    start_cheat_caller_address(token.contract_address, owner);
    token.approve(spender, amount);
    stop_cheat_caller_address(token.contract_address);
}
