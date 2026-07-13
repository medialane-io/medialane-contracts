use crate::common::*;
use crate::test_fulfill_sol::{fulfill_sol_ix, increment_counter_ix};
use anchor_lang::{AccountDeserialize, InstructionData, ToAccountMetas};
use medialane_marketplace::{Order, OrderStatus, Side};
use solana_sdk::{
    clock::Clock,
    instruction::Instruction,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
};

fn now(svm: &litesvm::LiteSVM) -> i64 {
    svm.get_sysvar::<Clock>().unix_timestamp
}

fn cancel_ix(offerer: &Pubkey, salt: u64, signer: &Pubkey) -> Instruction {
    Instruction {
        program_id: program_id(),
        accounts: medialane_marketplace::accounts::CancelOrder {
            signer: *signer,
            order: order_pda(offerer, salt),
        }
        .to_account_metas(None),
        data: medialane_marketplace::instruction::CancelOrder {}.data(),
    }
}

fn close_ix(offerer: &Pubkey, salt: u64) -> Instruction {
    Instruction {
        program_id: program_id(),
        accounts: medialane_marketplace::accounts::CloseOrder {
            offerer: *offerer,
            order: order_pda(offerer, salt),
        }
        .to_account_metas(None),
        data: medialane_marketplace::instruction::CloseOrder {}.data(),
    }
}

struct Listed {
    svm: litesvm::LiteSVM,
    seller: Keypair,
    buyer: Keypair,
    rc: Keypair,
    collection: Pubkey,
    asset: Pubkey,
}

fn listed() -> Listed {
    let mut svm = setup();
    let seller = Keypair::new();
    let buyer = Keypair::new();
    let rc = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&buyer.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) = create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 500);
    let t = now(&svm);
    let ix = register_ix(
        &seller.pubkey(), &asset, &collection, 1, Side::Listing, None,
        1_000_000_000, 1000, t, 0, 0,
    );
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();
    Listed { svm, seller, buyer, rc, collection, asset }
}

fn order_status(svm: &litesvm::LiteSVM, offerer: &Pubkey, salt: u64) -> OrderStatus {
    Order::try_deserialize(&mut svm.get_account(&order_pda(offerer, salt)).unwrap().data.as_slice())
        .unwrap()
        .status
}

#[test]
fn cancel_by_offerer_blocks_fill() {
    let mut s = listed();
    let seller = s.seller.insecure_clone();
    send(&mut s.svm, &seller, &[&seller], &[cancel_ix(&s.seller.pubkey(), 1, &s.seller.pubkey())]).unwrap();
    assert_eq!(order_status(&s.svm, &s.seller.pubkey(), 1), OrderStatus::Cancelled);
    let fill = fulfill_sol_ix(&s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection, &[s.rc.pubkey()]);
    let err = send(&mut s.svm, &s.buyer, &[&s.buyer], &[fill]).unwrap_err();
    assert!(err.contains("Custom(6008)"), "expected OrderCancelledError, got {err}");
}

#[test]
fn cancel_by_other_rejected() {
    let mut s = listed();
    let err = send(&mut s.svm, &s.buyer, &[&s.buyer], &[cancel_ix(&s.seller.pubkey(), 1, &s.buyer.pubkey())]).unwrap_err();
    assert!(err.contains("Custom(6009)"), "expected CallerNotOfferer, got {err}");
}

#[test]
fn cancel_after_fill_rejected() {
    let mut s = listed();
    let fill = fulfill_sol_ix(&s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection, &[s.rc.pubkey()]);
    send(&mut s.svm, &s.buyer, &[&s.buyer], &[fill]).unwrap();
    let seller = s.seller.insecure_clone();
    let err = send(&mut s.svm, &seller, &[&seller], &[cancel_ix(&s.seller.pubkey(), 1, &s.seller.pubkey())]).unwrap_err();
    assert!(err.contains("Custom(6007)"), "expected OrderAlreadyFilled, got {err}");
}

#[test]
fn counter_bump_blocks_stale_registration() {
    let mut s = listed();
    let seller = s.seller.insecure_clone();
    send(&mut s.svm, &seller, &[&seller], &[increment_counter_ix(&s.seller.pubkey())]).unwrap();
    let t = now(&s.svm);
    // stale counter (0) after bump
    let ix = register_ix(&s.seller.pubkey(), &s.asset, &s.collection, 2, Side::Listing, None, 1, 0, t, 0, 0);
    let err = send(&mut s.svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6001)"), "expected InvalidCounter, got {err}");
    // fresh counter (1) works
    let ix = register_ix(&s.seller.pubkey(), &s.asset, &s.collection, 2, Side::Listing, None, 1, 0, t, 0, 1);
    send(&mut s.svm, &seller, &[&seller], &[ix]).unwrap();
}

#[test]
fn close_reclaims_rent_on_terminal_only() {
    let mut s = listed();
    let seller = s.seller.insecure_clone();
    // Created → close rejected
    let err = send(&mut s.svm, &seller, &[&seller], &[close_ix(&s.seller.pubkey(), 1)]).unwrap_err();
    assert!(err.contains("Custom(6012)"), "expected OrderNotTerminal, got {err}");
    // Cancel, then close returns rent
    send(&mut s.svm, &seller, &[&seller], &[cancel_ix(&s.seller.pubkey(), 1, &s.seller.pubkey())]).unwrap();
    let before = s.svm.get_account(&s.seller.pubkey()).unwrap().lamports;
    s.svm.expire_blockhash();
    send(&mut s.svm, &seller, &[&seller], &[close_ix(&s.seller.pubkey(), 1)]).unwrap();
    let after = s.svm.get_account(&s.seller.pubkey()).unwrap().lamports;
    assert!(after > before, "rent must return to the offerer");
    assert!(s.svm.get_account(&order_pda(&s.seller.pubkey(), 1)).map(|a| a.data.is_empty()).unwrap_or(true));
}

#[test]
fn delegate_revoked_before_fill_fails_atomically() {
    let mut s = listed();
    // Owner revokes the transfer delegate directly on mpl-core.
    let revoke = mpl_core::instructions::RevokePluginAuthorityV1Builder::new()
        .asset(s.asset)
        .collection(Some(s.collection))
        .authority(Some(s.seller.pubkey()))
        .payer(s.seller.pubkey())
        .plugin_type(mpl_core::types::PluginType::TransferDelegate)
        .instruction();
    let seller = s.seller.insecure_clone();
    send(&mut s.svm, &seller, &[&seller], &[revoke]).unwrap();

    let fill = fulfill_sol_ix(&s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection, &[s.rc.pubkey()]);
    let err = send(&mut s.svm, &s.buyer, &[&s.buyer], &[fill]).unwrap_err();
    assert!(!err.is_empty());
    // Atomic revert: order still open, asset unmoved, no payment happened.
    assert_eq!(order_status(&s.svm, &s.seller.pubkey(), 1), OrderStatus::Created);
    let parsed = mpl_core::Asset::from_bytes(&s.svm.get_account(&s.asset).unwrap().data).unwrap();
    assert_eq!(parsed.base.owner, s.seller.pubkey());
}
