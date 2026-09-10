use crate::initialize_account_without_guardian;
use crate::setup::wallet_account_setup::ITestMediaWalletDispatcherTrait;
use starknet::SyscallResultTrait;
use starknet::syscalls::call_contract_syscall;

const NEW_OWNER_PUBKEY: felt252 = 0x999;

fn add_owner_calldata() -> Array<felt252> {
    array![0x0, 0x1, 0x0, NEW_OWNER_PUBKEY, 0x1]
}

fn remove_owner_calldata(guid: felt252) -> Array<felt252> {
    array![0x1, guid, 0x0, 0x1]
}

#[test]
fn sdk_add_owner_calldata_is_accepted() {
    let account = initialize_account_without_guardian();

    call_contract_syscall(
        account.contract_address, selector!("change_owners"), add_owner_calldata().span(),
    )
        .unwrap_syscall();

    assert_eq!(account.get_owners_info().len(), 2);
}

#[test]
fn sdk_remove_owner_calldata_is_accepted() {
    let account = initialize_account_without_guardian();
    let original_owner_guid = account.get_owner_guid();

    call_contract_syscall(
        account.contract_address, selector!("change_owners"), add_owner_calldata().span(),
    )
        .unwrap_syscall();
    call_contract_syscall(
        account.contract_address,
        selector!("change_owners"),
        remove_owner_calldata(original_owner_guid).span(),
    )
        .unwrap_syscall();

    assert_eq!(account.get_owners_info().len(), 1);
}
