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

#[allow(clippy::too_many_arguments)]
fn fulfill_spl_ix(
    fulfiller: &Pubkey,
    offerer: &Pubkey,
    salt: u64,
    asset: &Pubkey,
    core_collection: &Pubkey,
    payment_mint: &Pubkey,
    fulfiller_token: &Pubkey,
    offerer_token: &Pubkey,
    creator_tokens: &[Pubkey],
) -> Instruction {
    let mut accounts = medialane_marketplace::accounts::FulfillOrderSpl {
        fulfiller: *fulfiller,
        order: order_pda(offerer, salt),
        offerer: *offerer,
        cancel_counter: counter_pda(offerer),
        settlement_authority: settlement_pda(),
        asset: *asset,
        core_collection: *core_collection,
        payment_mint: *payment_mint,
        fulfiller_token: *fulfiller_token,
        offerer_token: *offerer_token,
        token_program: spl_token::id(),
        mpl_core_program: MPL_CORE_ID,
        system_program: anchor_lang::system_program::ID,
    }
    .to_account_metas(None);
    for creator_token in creator_tokens {
        accounts.push(AccountMeta::new(*creator_token, false));
    }
    Instruction {
        program_id: program_id(),
        accounts,
        data: medialane_marketplace::instruction::FulfillOrderSpl {}.data(),
    }
}

#[test]
fn fulfill_spl_listing_splits_tokens_with_capped_royalty() {
    let mut svm = setup();
    let seller = Keypair::new();
    let buyer = Keypair::new();
    let royalty_creator = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&buyer.pubkey(), 10_000_000_000).unwrap();
    // 20% plugin royalty, capped by the signed 10%.
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &royalty_creator.pubkey(), 2000);
    let (mint, buyer_ata) = create_mint_and_fund(&mut svm, &buyer, &buyer.pubkey(), 100_000_000);
    let seller_ata = ensure_ata(&mut svm, &buyer, &seller.pubkey(), &mint);
    let creator_ata = ensure_ata(&mut svm, &buyer, &royalty_creator.pubkey(), &mint);

    let t = now(&svm);
    let ix = register_ix(
        &seller.pubkey(), &asset, &collection, 1, Side::Listing, Some(mint),
        10_000_000, 1000, t, 0, 0,
    );
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();

    let fill = fulfill_spl_ix(
        &buyer.pubkey(), &seller.pubkey(), 1, &asset, &collection, &mint,
        &buyer_ata, &seller_ata, &[creator_ata],
    );
    send(&mut svm, &buyer, &[&buyer], &[fill]).unwrap();

    assert_eq!(token_balance(&svm, &creator_ata), 1_000_000); // capped 10%
    assert_eq!(token_balance(&svm, &seller_ata), 9_000_000);
    assert_eq!(token_balance(&svm, &buyer_ata), 90_000_000);
    let parsed = mpl_core::Asset::from_bytes(&svm.get_account(&asset).unwrap().data).unwrap();
    assert_eq!(parsed.base.owner, buyer.pubkey());
}

#[test]
fn fulfill_spl_bid_with_delegation() {
    let mut svm = setup();
    let seller = Keypair::new();
    let bidder = Keypair::new();
    let royalty_creator = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&bidder.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &royalty_creator.pubkey(), 500);
    let (mint, bidder_ata) = create_mint_and_fund(&mut svm, &bidder, &bidder.pubkey(), 100_000_000);
    let seller_ata = ensure_ata(&mut svm, &bidder, &seller.pubkey(), &mint);
    let creator_ata = ensure_ata(&mut svm, &bidder, &royalty_creator.pubkey(), &mint);

    let t = now(&svm);
    let ix = register_ix(
        &bidder.pubkey(), &asset, &collection, 3, Side::Bid, Some(mint),
        10_000_000, 1000, t, 0, 0,
    );
    send(&mut svm, &bidder, &[&bidder], &[ix]).unwrap();
    approve_delegate(&mut svm, &bidder, &bidder_ata, &settlement_pda(), 10_000_000);

    let fill = fulfill_spl_ix(
        &seller.pubkey(), &bidder.pubkey(), 3, &asset, &collection, &mint,
        &seller_ata, &bidder_ata, &[creator_ata],
    );
    send(&mut svm, &seller, &[&seller], &[fill]).unwrap();

    assert_eq!(token_balance(&svm, &creator_ata), 500_000); // 5% under cap
    assert_eq!(token_balance(&svm, &seller_ata), 9_500_000);
    let parsed = mpl_core::Asset::from_bytes(&svm.get_account(&asset).unwrap().data).unwrap();
    assert_eq!(parsed.base.owner, bidder.pubkey());
    let order = Order::try_deserialize(
        &mut svm.get_account(&order_pda(&bidder.pubkey(), 3)).unwrap().data.as_slice(),
    )
    .unwrap();
    assert_eq!(order.status, OrderStatus::Filled);
}

#[test]
fn fulfill_spl_bid_without_approval_fails_atomically() {
    let mut svm = setup();
    let seller = Keypair::new();
    let bidder = Keypair::new();
    let rc = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&bidder.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) = create_core_asset(&mut svm, &seller, &seller.pubkey(), &rc.pubkey(), 0);
    let (mint, bidder_ata) = create_mint_and_fund(&mut svm, &bidder, &bidder.pubkey(), 100_000_000);
    let seller_ata = ensure_ata(&mut svm, &bidder, &seller.pubkey(), &mint);

    let t = now(&svm);
    let ix = register_ix(
        &bidder.pubkey(), &asset, &collection, 3, Side::Bid, Some(mint),
        10_000_000, 0, t, 0, 0,
    );
    send(&mut svm, &bidder, &[&bidder], &[ix]).unwrap();
    // No approve_delegate call.
    let fill = fulfill_spl_ix(
        &seller.pubkey(), &bidder.pubkey(), 3, &asset, &collection, &mint,
        &seller_ata, &bidder_ata, &[],
    );
    let err = send(&mut svm, &seller, &[&seller], &[fill]).unwrap_err();
    assert!(!err.is_empty());
    // Order remains open; the asset never moved.
    let order = Order::try_deserialize(
        &mut svm.get_account(&order_pda(&bidder.pubkey(), 3)).unwrap().data.as_slice(),
    )
    .unwrap();
    assert_eq!(order.status, OrderStatus::Created);
    let parsed = mpl_core::Asset::from_bytes(&svm.get_account(&asset).unwrap().data).unwrap();
    assert_eq!(parsed.base.owner, seller.pubkey());
}

#[test]
fn fulfill_spl_wrong_creator_token_rejected() {
    let mut svm = setup();
    let seller = Keypair::new();
    let buyer = Keypair::new();
    let royalty_creator = Keypair::new();
    let impostor = Keypair::new();
    svm.airdrop(&seller.pubkey(), 10_000_000_000).unwrap();
    svm.airdrop(&buyer.pubkey(), 10_000_000_000).unwrap();
    let (collection, asset) =
        create_core_asset(&mut svm, &seller, &seller.pubkey(), &royalty_creator.pubkey(), 500);
    let (mint, buyer_ata) = create_mint_and_fund(&mut svm, &buyer, &buyer.pubkey(), 100_000_000);
    let seller_ata = ensure_ata(&mut svm, &buyer, &seller.pubkey(), &mint);
    let impostor_ata = ensure_ata(&mut svm, &buyer, &impostor.pubkey(), &mint);

    let t = now(&svm);
    let ix = register_ix(
        &seller.pubkey(), &asset, &collection, 1, Side::Listing, Some(mint),
        10_000_000, 1000, t, 0, 0,
    );
    send(&mut svm, &seller, &[&seller], &[ix]).unwrap();
    let fill = fulfill_spl_ix(
        &buyer.pubkey(), &seller.pubkey(), 1, &asset, &collection, &mint,
        &buyer_ata, &seller_ata, &[impostor_ata],
    );
    let err = send(&mut svm, &buyer, &[&buyer], &[fill]).unwrap_err();
    assert!(err.contains("Custom(6011)"), "expected CreatorAccountMismatch, got {err}");
}
