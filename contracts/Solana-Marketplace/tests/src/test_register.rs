use crate::common::*;
use anchor_lang::AccountDeserialize;
use medialane_marketplace::{Order, OrderStatus, Side};
use solana_sdk::{
    signature::{Keypair, Signer},
    transaction::Transaction,
};

fn now(svm: &litesvm::LiteSVM) -> i64 {
    svm.get_sysvar::<solana_sdk::clock::Clock>().unix_timestamp
}

#[test]
fn register_listing_stores_order_and_approves_delegate() {
    let mut svm = setup();
    let seller = Keypair::new();
    let royalty_creator = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &royalty_creator.pubkey(), 500);

    let t = now(&svm);
    let ix = register_ix(
        &seller.pubkey(), &asset, &collection, 1, Side::Listing, None,
        1_000_000_000, 1000, t, 0, 0,
    );
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();

    let order_account = svm.get_account(&order_pda(&seller.pubkey(), 1)).unwrap();
    let order = Order::try_deserialize(&mut order_account.data.as_slice()).unwrap();
    assert_eq!(order.offerer, seller.pubkey());
    assert_eq!(order.side, Side::Listing);
    assert_eq!(order.asset, asset);
    assert_eq!(order.payment_mint, None);
    assert_eq!(order.amount, 1_000_000_000);
    assert_eq!(order.royalty_max_bps, 1000);
    assert_eq!(order.status, OrderStatus::Created);

    // The settlement PDA is now the asset's transfer delegate.
    let asset_data = svm.get_account(&asset).unwrap().data;
    let parsed = mpl_core::Asset::from_bytes(&asset_data).unwrap();
    let delegate = parsed.plugin_list.transfer_delegate.expect("transfer delegate");
    assert_eq!(
        delegate.base.authority,
        mpl_core::types::PluginAuthority::Address { address: settlement_pda() }.into()
    );
}

#[test]
fn register_spl_bid_stores_order_without_delegate() {
    let mut svm = setup();
    let bidder = Keypair::new();
    let seller = Keypair::new();
    let royalty_creator = Keypair::new();
    svm.airdrop(&bidder.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &royalty_creator.pubkey(), 500);

    let fake_mint = Keypair::new().pubkey();
    let t = now(&svm);
    let ix = register_ix(
        &bidder.pubkey(), &asset, &collection, 7, Side::Bid, Some(fake_mint),
        500_000, 1000, t, t + 3600, 0,
    );
    send(&mut svm, &bidder, &[&bidder], &[ix]).unwrap();

    let order_account = svm.get_account(&order_pda(&bidder.pubkey(), 7)).unwrap();
    let order = Order::try_deserialize(&mut order_account.data.as_slice()).unwrap();
    assert_eq!(order.side, Side::Bid);
    assert_eq!(order.payment_mint, Some(fake_mint));

    let asset_data = svm.get_account(&asset).unwrap().data;
    let parsed = mpl_core::Asset::from_bytes(&asset_data).unwrap();
    assert!(parsed.plugin_list.transfer_delegate.is_none());
}

#[test]
fn register_rejects_native_bid() {
    let mut svm = setup();
    let bidder = Keypair::new();
    let seller = Keypair::new();
    svm.airdrop(&bidder.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    let rc = Keypair::new();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 0);

    let t = now(&svm);
    let ix = register_ix(
        &bidder.pubkey(), &asset, &collection, 1, Side::Bid, None, 500_000, 0, t, 0, 0,
    );
    let err = send(&mut svm, &bidder, &[&bidder], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6002)"), "expected NativeBidUnsupported, got {err}");
}

#[test]
fn register_rejects_wrong_counter_and_high_bps_and_bad_window() {
    let mut svm = setup();
    let seller = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    let rc = Keypair::new();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 0);
    let t = now(&svm);

    // wrong counter
    let ix = register_ix(&seller.pubkey(), &asset, &collection, 1, Side::Listing, None, 1, 0, t, 0, 5);
    let err = send(&mut svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6001)"), "expected InvalidCounter, got {err}");

    // bps too high
    let ix = register_ix(&seller.pubkey(), &asset, &collection, 2, Side::Listing, None, 1, 10_001, t, 0, 0);
    let err = send(&mut svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6000)"), "expected RoyaltyBpsTooHigh, got {err}");

    // inverted window
    let ix = register_ix(&seller.pubkey(), &asset, &collection, 3, Side::Listing, None, 1, 0, t + 100, t + 50, 0);
    let err = send(&mut svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6003)"), "expected InvalidTimeWindow, got {err}");

    // already expired
    let ix = register_ix(&seller.pubkey(), &asset, &collection, 4, Side::Listing, None, 1, 0, t - 100, t - 50, 0);
    let err = send(&mut svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("Custom(6004)"), "expected OrderExpired, got {err}");
}

#[test]
fn register_rejects_duplicate_salt() {
    let mut svm = setup();
    let seller = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    let rc = Keypair::new();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 0);
    let t = now(&svm);

    let ix = register_ix(&seller.pubkey(), &asset, &collection, 9, Side::Listing, None, 1, 0, t, 0, 0);
    send(&mut svm, &seller, &[&seller], &[ix.clone()]).unwrap();
    svm.expire_blockhash();
    let err = send(&mut svm, &seller, &[&seller], &[ix]).unwrap_err();
    assert!(err.contains("already in use") || err.contains("Custom(0)"), "got {err}");
}

#[test]
fn register_requires_offerer_signature() {
    let mut svm = setup();
    let seller = Keypair::new();
    let mallory = Keypair::new();
    svm.airdrop(&mallory.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    let rc = Keypair::new();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 0);
    let t = now(&svm);

    // mallory tries to register an order naming seller as offerer without seller's signature
    let ix = register_ix(&seller.pubkey(), &asset, &collection, 1, Side::Listing, None, 1, 0, t, 0, 0);
    let result = std::panic::catch_unwind(|| {
        Transaction::new_signed_with_payer(
            &[ix],
            Some(&mallory.pubkey()),
            &[&mallory],
            svm.latest_blockhash(),
        )
    });
    assert!(result.is_err(), "tx signing without the offerer must fail");
}
