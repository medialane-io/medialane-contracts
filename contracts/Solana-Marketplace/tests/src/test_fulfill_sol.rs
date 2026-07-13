use crate::common::*;
use anchor_lang::{AccountDeserialize, InstructionData, ToAccountMetas};
use medialane_marketplace::{Order, OrderStatus, Side};
use mpl_core::programs::MPL_CORE_ID;
use solana_sdk::{
    clock::Clock,
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::{Keypair, Signer},
};

fn now(svm: &litesvm::LiteSVM) -> i64 {
    svm.get_sysvar::<Clock>().unix_timestamp
}

pub fn fulfill_sol_ix(
    fulfiller: &Pubkey,
    offerer: &Pubkey,
    salt: u64,
    asset: &Pubkey,
    core_collection: &Pubkey,
    creators: &[Pubkey],
) -> Instruction {
    let mut accounts = medialane_marketplace::accounts::FulfillOrder {
        fulfiller: *fulfiller,
        order: order_pda(offerer, salt),
        offerer: *offerer,
        cancel_counter: counter_pda(offerer),
        settlement_authority: settlement_pda(),
        asset: *asset,
        core_collection: *core_collection,
        mpl_core_program: MPL_CORE_ID,
        system_program: anchor_lang::system_program::ID,
    }
    .to_account_metas(None);
    for creator in creators {
        accounts.push(AccountMeta::new(*creator, false));
    }
    Instruction {
        program_id: program_id(),
        accounts,
        data: medialane_marketplace::instruction::FulfillOrder {}.data(),
    }
}

pub fn increment_counter_ix(offerer: &Pubkey) -> Instruction {
    Instruction {
        program_id: program_id(),
        accounts: medialane_marketplace::accounts::IncrementCounter {
            offerer: *offerer,
            cancel_counter: counter_pda(offerer),
            system_program: anchor_lang::system_program::ID,
        }
        .to_account_metas(None),
        data: medialane_marketplace::instruction::IncrementCounter {}.data(),
    }
}

struct Scenario {
    svm: litesvm::LiteSVM,
    seller: Keypair,
    buyer: Keypair,
    royalty_creator: Keypair,
    collection: Pubkey,
    asset: Pubkey,
}

/// Seller lists the asset for 1 SOL with a `plugin_bps` royalty plugin and a
/// 1000-bps signed cap.
fn listed(plugin_bps: u16) -> Scenario {
    let mut svm = setup();
    let seller = Keypair::new();
    let buyer = Keypair::new();
    let royalty_creator = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&buyer.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &royalty_creator.pubkey(), plugin_bps);
    let t = now(&svm);
    let ix = register_ix(
        &seller.pubkey(), &asset, &collection, 1, Side::Listing, None,
        1_000_000_000, 1000, t, 0, 0,
    );
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();
    Scenario { svm, seller, buyer, royalty_creator, collection, asset }
}

#[test]
fn fulfill_sol_listing_transfers_asset_and_splits_payment() {
    let mut s = listed(500); // 5% plugin, under the 10% cap
    let seller_before = s.svm.get_account(&s.seller.pubkey()).unwrap().lamports;
    let ix = fulfill_sol_ix(
        &s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection,
        &[s.royalty_creator.pubkey()],
    );
    send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix]).unwrap();

    let parsed = mpl_core::Asset::from_bytes(&s.svm.get_account(&s.asset).unwrap().data).unwrap();
    assert_eq!(parsed.base.owner, s.buyer.pubkey());

    let creator_lamports = s.svm.get_account(&s.royalty_creator.pubkey()).map(|a| a.lamports).unwrap_or(0);
    assert_eq!(creator_lamports, 50_000_000); // 5% of 1 SOL
    let seller_after = s.svm.get_account(&s.seller.pubkey()).unwrap().lamports;
    assert_eq!(seller_after - seller_before, 950_000_000);

    let order = Order::try_deserialize(
        &mut s.svm.get_account(&order_pda(&s.seller.pubkey(), 1)).unwrap().data.as_slice(),
    )
    .unwrap();
    assert_eq!(order.status, OrderStatus::Filled);
}

#[test]
fn fulfill_sol_royalty_capped_at_signed_max() {
    let mut s = listed(2000); // 20% plugin, capped at the signed 10%
    let ix = fulfill_sol_ix(
        &s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection,
        &[s.royalty_creator.pubkey()],
    );
    send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix]).unwrap();
    let creator_lamports = s.svm.get_account(&s.royalty_creator.pubkey()).map(|a| a.lamports).unwrap_or(0);
    assert_eq!(creator_lamports, 100_000_000); // exactly 10%
}

#[test]
fn fulfill_sol_no_plugin_seller_keeps_all() {
    let mut s = listed(0);
    let seller_before = s.svm.get_account(&s.seller.pubkey()).unwrap().lamports;
    let ix = fulfill_sol_ix(&s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection, &[]);
    send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix]).unwrap();
    let seller_after = s.svm.get_account(&s.seller.pubkey()).unwrap().lamports;
    assert_eq!(seller_after - seller_before, 1_000_000_000);
}

#[test]
fn fulfill_sol_self_fill_rejected() {
    let mut s = listed(500);
    let ix = fulfill_sol_ix(
        &s.seller.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection,
        &[s.royalty_creator.pubkey()],
    );
    let seller = s.seller.insecure_clone();
    let err = send(&mut s.svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6005)"), "expected SelfFill, got {err}");
}

#[test]
fn fulfill_sol_double_fill_rejected() {
    let mut s = listed(500);
    let ix = fulfill_sol_ix(
        &s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection,
        &[s.royalty_creator.pubkey()],
    );
    send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix.clone()]).unwrap();
    s.svm.expire_blockhash();
    let err = send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6007)"), "expected OrderAlreadyFilled, got {err}");
}

#[test]
fn fulfill_sol_stale_counter_rejected() {
    let mut s = listed(500);
    let bump = increment_counter_ix(&s.seller.pubkey());
    let seller = s.seller.insecure_clone();
    send(&mut s.svm, &seller, &[&seller], &[bump]).unwrap();
    let ix = fulfill_sol_ix(
        &s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection,
        &[s.royalty_creator.pubkey()],
    );
    let err = send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6001)"), "expected InvalidCounter, got {err}");
}

#[test]
fn fulfill_sol_expiry_and_not_yet_valid() {
    // not yet valid
    let mut svm = setup();
    let seller = Keypair::new();
    let buyer = Keypair::new();
    let rc = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&buyer.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) = create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 0);
    let t = now(&svm);
    let ix = register_ix(
        &seller.pubkey(), &asset, &collection, 1, Side::Listing, None,
        1_000_000_000, 0, t + 1000, t + 2000, 0,
    );
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();
    let fill = fulfill_sol_ix(&buyer.pubkey(), &seller.pubkey(), 1, &asset, &collection, &[]);
    let err = send(&mut svm, &buyer, &[&buyer], &[fill.clone()]).unwrap_err();
    assert!(err.contains("Custom(6006)"), "expected OrderNotYetValid, got {err}");

    // expired: warp the clock past end_time
    let mut clock: Clock = svm.get_sysvar();
    clock.unix_timestamp = t + 3000;
    svm.set_sysvar(&clock);
    svm.expire_blockhash();
    let err = send(&mut svm, &buyer, &[&buyer], &[fill]).unwrap_err();
    assert!(err.contains("Custom(6004)"), "expected OrderExpired, got {err}");
}

#[test]
fn fulfill_sol_wrong_creator_account_rejected() {
    let mut s = listed(500);
    let impostor = Keypair::new();
    let ix = fulfill_sol_ix(
        &s.buyer.pubkey(), &s.seller.pubkey(), 1, &s.asset, &s.collection,
        &[impostor.pubkey()],
    );
    let err = send(&mut s.svm, &s.buyer, &[&s.buyer], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6011)"), "expected CreatorAccountMismatch, got {err}");
}

#[test]
fn fulfill_sol_free_order() {
    let mut svm = setup();
    let seller = Keypair::new();
    let buyer = Keypair::new();
    let rc = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&buyer.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) = create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 500);
    let t = now(&svm);
    let ix = register_ix(&seller.pubkey(), &asset, &collection, 1, Side::Listing, None, 0, 1000, t, 0, 0);
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();
    let fill = fulfill_sol_ix(&buyer.pubkey(), &seller.pubkey(), 1, &asset, &collection, &[rc.pubkey()]);
    send(&mut svm, &buyer, &[&buyer], &[fill]).unwrap();
    let parsed = mpl_core::Asset::from_bytes(&svm.get_account(&asset).unwrap().data).unwrap();
    assert_eq!(parsed.base.owner, buyer.pubkey());
}
