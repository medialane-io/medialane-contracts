use anchor_lang::{InstructionData, ToAccountMetas};
use litesvm::LiteSVM;
use mpl_core::programs::MPL_CORE_ID;
use solana_sdk::{
    instruction::Instruction,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
};

pub fn program_id() -> Pubkey {
    medialane_marketplace::ID
}

pub fn setup() -> LiteSVM {
    let mut svm = LiteSVM::new();
    svm.add_program_from_file(program_id(), "../target/deploy/medialane_marketplace.so")
        .expect("venue .so — run `anchor build` first");
    svm.add_program_from_file(MPL_CORE_ID, "fixtures/mpl_core.so")
        .expect("mpl_core fixture");
    svm
}

/// Creates a Core collection (with a Royalties plugin at `royalty_bps`, sole
/// beneficiary `royalty_creator`) and one asset owned by `owner`.
pub fn create_core_asset(
    svm: &mut LiteSVM,
    payer: &Keypair,
    owner: &Pubkey,
    royalty_creator: &Pubkey,
    royalty_bps: u16,
) -> (Pubkey, Pubkey) {
    let collection = Keypair::new();
    let asset = Keypair::new();

    let mut plugins = vec![];
    if royalty_bps > 0 {
        plugins.push(mpl_core::types::PluginAuthorityPair {
            plugin: mpl_core::types::Plugin::Royalties(mpl_core::types::Royalties {
                basis_points: royalty_bps,
                creators: vec![mpl_core::types::Creator {
                    address: *royalty_creator,
                    percentage: 100,
                }],
                rule_set: mpl_core::types::RuleSet::None,
            }),
            authority: None,
        });
    }

    let create_col = mpl_core::instructions::CreateCollectionV2Builder::new()
        .collection(collection.pubkey())
        .payer(payer.pubkey())
        .update_authority(Some(payer.pubkey()))
        .name("Col".to_string())
        .uri("ipfs://col".to_string())
        .plugins(plugins)
        .instruction();
    let tx = Transaction::new_signed_with_payer(
        &[create_col],
        Some(&payer.pubkey()),
        &[payer, &collection],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).unwrap();

    let create_asset = mpl_core::instructions::CreateV2Builder::new()
        .asset(asset.pubkey())
        .collection(Some(collection.pubkey()))
        .authority(Some(payer.pubkey()))
        .payer(payer.pubkey())
        .owner(Some(*owner))
        .name("Work".to_string())
        .uri("ipfs://work".to_string())
        .instruction();
    let tx = Transaction::new_signed_with_payer(
        &[create_asset],
        Some(&payer.pubkey()),
        &[payer, &asset],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).unwrap();

    (collection.pubkey(), asset.pubkey())
}

pub fn order_pda(offerer: &Pubkey, salt: u64) -> Pubkey {
    Pubkey::find_program_address(
        &[b"order", offerer.as_ref(), &salt.to_le_bytes()],
        &program_id(),
    )
    .0
}

pub fn counter_pda(offerer: &Pubkey) -> Pubkey {
    Pubkey::find_program_address(&[b"counter", offerer.as_ref()], &program_id()).0
}

pub fn settlement_pda() -> Pubkey {
    Pubkey::find_program_address(&[b"authority"], &program_id()).0
}

#[allow(clippy::too_many_arguments)]
pub fn register_ix(
    offerer: &Pubkey,
    asset: &Pubkey,
    core_collection: &Pubkey,
    salt: u64,
    side: medialane_marketplace::Side,
    payment_mint: Option<Pubkey>,
    amount: u64,
    royalty_max_bps: u16,
    start_time: i64,
    end_time: i64,
    counter: u64,
) -> Instruction {
    Instruction {
        program_id: program_id(),
        accounts: medialane_marketplace::accounts::RegisterOrder {
            offerer: *offerer,
            order: order_pda(offerer, salt),
            cancel_counter: counter_pda(offerer),
            settlement_authority: settlement_pda(),
            asset: *asset,
            core_collection: *core_collection,
            mpl_core_program: MPL_CORE_ID,
            system_program: anchor_lang::system_program::ID,
        }
        .to_account_metas(None),
        data: medialane_marketplace::instruction::RegisterOrder {
            salt,
            side,
            payment_mint,
            amount,
            royalty_max_bps,
            start_time,
            end_time,
            counter,
        }
        .data(),
    }
}

pub fn send(
    svm: &mut LiteSVM,
    payer: &Keypair,
    signers: &[&Keypair],
    ixs: &[Instruction],
) -> Result<(), String> {
    let tx = Transaction::new_signed_with_payer(
        ixs,
        Some(&payer.pubkey()),
        signers,
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).map(|_| ()).map_err(|e| format!("{:?}", e.err))
}

use spl_associated_token_account::get_associated_token_address;
use solana_sdk::program_pack::Pack;

/// Creates an SPL mint (decimals 6) and mints `amount` to `owner`'s ATA.
pub fn create_mint_and_fund(
    svm: &mut LiteSVM,
    payer: &Keypair,
    owner: &Pubkey,
    amount: u64,
) -> (Pubkey, Pubkey) {
    let mint = Keypair::new();
    let rent = svm.minimum_balance_for_rent_exemption(spl_token::state::Mint::LEN);
    let create_mint = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        rent,
        spl_token::state::Mint::LEN as u64,
        &spl_token::id(),
    );
    let init_mint = spl_token::instruction::initialize_mint2(
        &spl_token::id(),
        &mint.pubkey(),
        &payer.pubkey(),
        None,
        6,
    )
    .unwrap();
    let tx = Transaction::new_signed_with_payer(
        &[create_mint, init_mint],
        Some(&payer.pubkey()),
        &[payer, &mint],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).unwrap();

    let ata = ensure_ata(svm, payer, owner, &mint.pubkey());
    if amount > 0 {
        let mint_to = spl_token::instruction::mint_to(
            &spl_token::id(),
            &mint.pubkey(),
            &ata,
            &payer.pubkey(),
            &[],
            amount,
        )
        .unwrap();
        let tx = Transaction::new_signed_with_payer(
            &[mint_to],
            Some(&payer.pubkey()),
            &[payer],
            svm.latest_blockhash(),
        );
        svm.send_transaction(tx).unwrap();
    }
    (mint.pubkey(), ata)
}

pub fn ensure_ata(svm: &mut LiteSVM, payer: &Keypair, owner: &Pubkey, mint: &Pubkey) -> Pubkey {
    let ata = get_associated_token_address(owner, mint);
    if svm.get_account(&ata).is_none() {
        let ix = spl_associated_token_account::instruction::create_associated_token_account(
            &payer.pubkey(),
            owner,
            mint,
            &spl_token::id(),
        );
        let tx = Transaction::new_signed_with_payer(
            &[ix],
            Some(&payer.pubkey()),
            &[payer],
            svm.latest_blockhash(),
        );
        svm.send_transaction(tx).unwrap();
    }
    ata
}

pub fn token_balance(svm: &LiteSVM, token_account: &Pubkey) -> u64 {
    use solana_sdk::program_pack::Pack;
    svm.get_account(token_account)
        .map(|a| spl_token::state::Account::unpack(&a.data).unwrap().amount)
        .unwrap_or(0)
}

pub fn approve_delegate(
    svm: &mut LiteSVM,
    owner: &Keypair,
    token_account: &Pubkey,
    delegate: &Pubkey,
    amount: u64,
) {
    let ix = spl_token::instruction::approve(
        &spl_token::id(),
        token_account,
        delegate,
        &owner.pubkey(),
        &[],
        amount,
    )
    .unwrap();
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&owner.pubkey()),
        &[owner],
        svm.latest_blockhash(),
    );
    svm.send_transaction(tx).unwrap();
}
