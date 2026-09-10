use crate::setup::wallet_account_setup::ITestMediaWalletDispatcherTrait;
use crate::wallet_account::test_wallet_account::{NEW_OWNER, VALID_UNTIL};
use crate::{OWNER, TX_HASH, initialize_account_without_guardian, to_starknet_signatures};
use core::num::traits::Zero;
use media_wallet::signer::signer_signature::{SignerTraitImpl, starknet_signer_from_pubkey};
use snforge_std::{start_cheat_caller_address_global, start_cheat_signature_global, start_cheat_transaction_hash_global};
use starknet::account::Call;

const NEW_OWNER_PUBKEY: felt252 = 0x999;

fn old_owner_guid() -> felt252 {
    starknet_signer_from_pubkey(OWNER().pubkey).into_guid()
}

fn validate_change_owners(calldata: Span<felt252>) {
    let account = initialize_account_without_guardian();
    start_cheat_caller_address_global(Zero::zero());
    start_cheat_transaction_hash_global(TX_HASH);
    start_cheat_signature_global(to_starknet_signatures(array![OWNER()]).span());
    let call = Call {
        selector: selector!("change_owners"), to: account.contract_address, calldata,
    };
    account.__validate__(array![call]);
}

#[test]
#[should_panic(expected: ('wallet/missing-owner-alive',))]
fn handoff_without_owner_alive_is_rejected() {
    validate_change_owners(
        array![0x1, old_owner_guid(), 0x1, 0x0, NEW_OWNER_PUBKEY, 0x1].span(),
    );
}

#[test]
fn handoff_with_owner_alive_is_accepted() {
    let (new_owner, alive) = NEW_OWNER();
    let mut calldata = array![];
    (array![old_owner_guid()], array![new_owner], Option::Some(alive)).serialize(ref calldata);
    validate_change_owners(calldata.span());
}

#[test]
fn owner_alive_serialises_as_some_then_signature_then_expiry() {
    let (_, alive) = NEW_OWNER();
    let mut out = array![];
    Option::Some(alive).serialize(ref out);

    assert_eq!(*out.at(0), 0);
    assert_eq!(*out.at(1), 0);
    assert_eq!(out.len(), 6);
    assert_eq!(*out.at(5), VALID_UNTIL.into());
}
