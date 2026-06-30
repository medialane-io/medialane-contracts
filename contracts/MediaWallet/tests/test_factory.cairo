// SPDX-License-Identifier: GPL-3.0
use media_wallet::factory::{IMediaWalletFactoryDispatcher, IMediaWalletFactoryDispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};

fn deploy_factory(wallet_class_hash: felt252) -> IMediaWalletFactoryDispatcher {
    let contract = declare("MediaWalletFactory").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![wallet_class_hash];
    let (address, _) = contract.deploy(@calldata).unwrap();
    IMediaWalletFactoryDispatcher { contract_address: address }
}

#[test]
fn test_wallet_class_hash_is_fixed() {
    let mock_class_hash: felt252 = 0x5678;
    let factory = deploy_factory(mock_class_hash);
    assert(
        factory.wallet_class_hash() == mock_class_hash.try_into().unwrap(), 'class hash mismatch',
    );
}

#[test]
fn test_compute_address_matches_deploy() {
    // Declare the real MediaWallet contract to get its class hash
    let wallet_class = declare("MediaWallet").unwrap().contract_class();
    let wallet_class_hash: felt252 = (*wallet_class.class_hash).into();
    let factory = deploy_factory(wallet_class_hash);

    let owner_pubkey: felt252 = 0xdeadbeef;
    let salt: felt252 = 0x42;

    let predicted = factory.compute_address(owner_pubkey, salt);
    let deployed = factory.deploy_wallet(owner_pubkey, salt);

    assert(predicted == deployed, 'predicted address must match');
}

#[test]
fn test_deploy_wallet_different_salts_different_addresses() {
    let wallet_class = declare("MediaWallet").unwrap().contract_class();
    let wallet_class_hash: felt252 = (*wallet_class.class_hash).into();
    let factory = deploy_factory(wallet_class_hash);

    let owner_pubkey: felt252 = 0xabcdef;

    let address1 = factory.deploy_wallet(owner_pubkey, 0x1);
    let address2 = factory.deploy_wallet(owner_pubkey, 0x2);

    assert(address1 != address2, 'addresses must differ by salt');
}

#[test]
fn test_compute_address_deterministic_before_deploy() {
    let wallet_class = declare("MediaWallet").unwrap().contract_class();
    let wallet_class_hash: felt252 = (*wallet_class.class_hash).into();
    let factory = deploy_factory(wallet_class_hash);

    let owner_pubkey: felt252 = 0x1234;
    let salt: felt252 = 0x99;

    // compute_address should give same result regardless of whether wallet is deployed
    let predicted_before = factory.compute_address(owner_pubkey, salt);
    factory.deploy_wallet(owner_pubkey, salt);
    let predicted_after = factory.compute_address(owner_pubkey, salt);

    assert(predicted_before == predicted_after, 'address not deterministic');
}
