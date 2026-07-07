use anchor_lang::prelude::*;
use anchor_spl::token::TokenAccount;

declare_id!("GBpbZYXuyC1EquzCUag5FrsryeenLHrnFea8LUGb1bRd");

/// Medialane marketplace — immutable venue for Metaplex Core assets.
///
/// Safety model — every check is on-chain and falls in exactly one bucket:
///   1. Statically determinable from the order → validated at registration,
///      fail-fast. The offerer signs registration; the runtime verifies it.
///   2. Mutable on-chain state (ownership, delegation, allowance, live
///      royalties) → not pre-simulated; enforced by atomic revert at fill.
///      Settlement pays before delivering the asset.
///
/// No admin instructions, no fees, no pause.
#[program]
pub mod medialane_marketplace {
    use super::*;

    /// Register an order. The offerer signs; a relayer may pay fees. For
    /// listings, the same transaction approves the venue's settlement PDA as
    /// the asset's transfer delegate. Bids are SPL-priced only — native
    /// lamports cannot be delegated — and rely on an SPL delegate approval
    /// enforced at fill.
    #[allow(clippy::too_many_arguments)]
    pub fn register_order(
        ctx: Context<RegisterOrder>,
        salt: u64,
        side: Side,
        payment_mint: Option<Pubkey>,
        amount: u64,
        royalty_max_bps: u16,
        start_time: i64,
        end_time: i64,
        counter: u64,
    ) -> Result<()> {
        let _ = salt;
        require!(royalty_max_bps <= 10_000, VenueError::RoyaltyBpsTooHigh);
        require!(
            counter == ctx.accounts.cancel_counter.count,
            VenueError::InvalidCounter
        );
        if side == Side::Bid {
            require!(payment_mint.is_some(), VenueError::NativeBidUnsupported);
        }
        let now = Clock::get()?.unix_timestamp;
        if end_time != 0 {
            require!(start_time < end_time, VenueError::InvalidTimeWindow);
            require!(now < end_time, VenueError::OrderExpired);
        }

        if side == Side::Listing {
            let mpl_core_program = ctx.accounts.mpl_core_program.to_account_info();
            let asset = ctx.accounts.asset.to_account_info();
            let core_collection = ctx.accounts.core_collection.to_account_info();
            let offerer = ctx.accounts.offerer.to_account_info();
            let system_program = ctx.accounts.system_program.to_account_info();
            mpl_core::instructions::AddPluginV1CpiBuilder::new(&mpl_core_program)
                .asset(&asset)
                .collection(Some(&core_collection))
                .authority(Some(&offerer))
                .payer(&offerer)
                .system_program(&system_program)
                .plugin(mpl_core::types::Plugin::TransferDelegate(
                    mpl_core::types::TransferDelegate {},
                ))
                .init_authority(mpl_core::types::PluginAuthority::Address {
                    address: ctx.accounts.settlement_authority.key(),
                })
                .invoke()?;
        }

        let order = &mut ctx.accounts.order;
        order.offerer = ctx.accounts.offerer.key();
        order.side = side;
        order.asset = ctx.accounts.asset.key();
        order.core_collection = ctx.accounts.core_collection.key();
        order.payment_mint = payment_mint;
        order.amount = amount;
        order.royalty_max_bps = royalty_max_bps;
        order.start_time = start_time;
        order.end_time = end_time;
        order.counter = counter;
        order.status = OrderStatus::Created;
        order.bump = ctx.bumps.order;

        emit!(OrderCreated {
            order: order.key(),
            offerer: ctx.accounts.offerer.key(),
        });
        Ok(())
    }

    /// Fulfil an open SOL-priced listing. The caller IS the fulfiller and pays
    /// the sale amount in lamports. Royalties are read live from the asset's
    /// (or its collection's) Core Royalties plugin, capped at the
    /// offerer-signed maximum, and split pro-rata across the plugin's
    /// creators, passed as remaining accounts in plugin order. Payment settles
    /// before the asset moves via the venue's transfer delegate.
    pub fn fulfill_order<'info>(ctx: Context<'info, FulfillOrder<'info>>) -> Result<()> {
        let order = &ctx.accounts.order;
        require!(order.payment_mint.is_none(), VenueError::WrongPaymentMint);
        require!(order.side == Side::Listing, VenueError::WrongPaymentMint);

        check_fillable(
            order,
            ctx.accounts.fulfiller.key(),
            ctx.accounts.cancel_counter.count,
        )?;

        ctx.accounts.order.status = OrderStatus::Filled;

        let sale_amount = ctx.accounts.order.amount;
        let asset_info = ctx.accounts.asset.to_account_info();
        let collection_info = ctx.accounts.core_collection.to_account_info();
        let (royalty_receiver, royalty_amount, payouts) = royalty_payouts(
            &asset_info,
            &collection_info,
            sale_amount,
            ctx.accounts.order.royalty_max_bps,
            ctx.remaining_accounts,
        )?;

        // Payment first: royalties, then the seller's remainder.
        for (creator_account, amount) in &payouts {
            if *amount > 0 {
                anchor_lang::system_program::transfer(
                    CpiContext::new(
                        ctx.accounts.system_program.key(),
                        anchor_lang::system_program::Transfer {
                            from: ctx.accounts.fulfiller.to_account_info(),
                            to: creator_account.clone(),
                        },
                    ),
                    *amount,
                )?;
            }
        }
        let seller_amount = sale_amount
            .checked_sub(royalty_amount)
            .ok_or(VenueError::RoyaltyExceedsSale)?;
        if seller_amount > 0 {
            anchor_lang::system_program::transfer(
                CpiContext::new(
                    ctx.accounts.system_program.key(),
                    anchor_lang::system_program::Transfer {
                        from: ctx.accounts.fulfiller.to_account_info(),
                        to: ctx.accounts.offerer.to_account_info(),
                    },
                ),
                seller_amount,
            )?;
        }

        // Delivery via the settlement delegate approved at registration.
        let bump = ctx.bumps.settlement_authority;
        let signer_seeds: &[&[&[u8]]] = &[&[b"authority", &[bump]]];
        let mpl_core_program = ctx.accounts.mpl_core_program.to_account_info();
        let settlement = ctx.accounts.settlement_authority.to_account_info();
        let fulfiller_info = ctx.accounts.fulfiller.to_account_info();
        mpl_core::instructions::TransferV1CpiBuilder::new(&mpl_core_program)
            .asset(&asset_info)
            .collection(Some(&collection_info))
            .authority(Some(&settlement))
            .payer(&fulfiller_info)
            .new_owner(&fulfiller_info)
            .invoke_signed(signer_seeds)?;

        emit!(OrderFulfilled {
            order: ctx.accounts.order.key(),
            offerer: ctx.accounts.order.offerer,
            fulfiller: ctx.accounts.fulfiller.key(),
            sale_amount,
            royalty_receiver,
            royalty_amount,
        });
        Ok(())
    }

    /// Fulfil an open SPL-priced order. Listings: the fulfiller pays from
    /// their token account. Bids: payment is pulled from the bidder's token
    /// account through the SPL delegation to the settlement PDA, approved by
    /// the bidder before fill — a missing or spent allowance fails the fill
    /// atomically. Royalties as in `fulfill_order`, paid to the creators'
    /// token accounts (remaining accounts, plugin order). Payment settles
    /// before the asset moves.
    pub fn fulfill_order_spl<'info>(
        ctx: Context<'info, FulfillOrderSpl<'info>>,
    ) -> Result<()> {
        let order = &ctx.accounts.order;
        require!(
            order.payment_mint == Some(ctx.accounts.payment_mint.key()),
            VenueError::WrongPaymentMint
        );

        check_fillable(
            order,
            ctx.accounts.fulfiller.key(),
            ctx.accounts.cancel_counter.count,
        )?;

        ctx.accounts.order.status = OrderStatus::Filled;

        let side = ctx.accounts.order.side;
        let sale_amount = ctx.accounts.order.amount;
        let asset_info = ctx.accounts.asset.to_account_info();
        let collection_info = ctx.accounts.core_collection.to_account_info();
        let (royalty_receiver, royalty_amount, shares) = royalty_shares(
            &asset_info,
            &collection_info,
            sale_amount,
            ctx.accounts.order.royalty_max_bps,
        )?;

        // Validate the creator token accounts against the plugin's creators.
        require!(
            ctx.remaining_accounts.len() == shares.len(),
            VenueError::CreatorAccountMismatch
        );
        let mint_key = ctx.accounts.payment_mint.key();
        for (i, (creator, _)) in shares.iter().enumerate() {
            let info = &ctx.remaining_accounts[i];
            let token_account = TokenAccount::try_deserialize(&mut &info.data.borrow()[..])?;
            require!(
                token_account.owner == *creator && token_account.mint == mint_key,
                VenueError::CreatorAccountMismatch
            );
        }

        // Payment first. Listings pull from the fulfiller (signer); bids pull
        // from the bidder's account through the settlement PDA delegation.
        let bump = ctx.bumps.settlement_authority;
        let signer_seeds: &[&[&[u8]]] = &[&[b"authority", &[bump]]];
        let (source, authority_is_delegate) = match side {
            Side::Listing => (ctx.accounts.fulfiller_token.to_account_info(), false),
            Side::Bid => (ctx.accounts.offerer_token.to_account_info(), true),
        };
        let payment_recipient = match side {
            Side::Listing => ctx.accounts.offerer_token.to_account_info(),
            Side::Bid => ctx.accounts.fulfiller_token.to_account_info(),
        };

        let pay = |to: AccountInfo<'info>, amount: u64| -> Result<()> {
            if amount == 0 {
                return Ok(());
            }
            let accounts = anchor_spl::token::Transfer {
                from: source.clone(),
                to,
                authority: if authority_is_delegate {
                    ctx.accounts.settlement_authority.to_account_info()
                } else {
                    ctx.accounts.fulfiller.to_account_info()
                },
            };
            let cpi = if authority_is_delegate {
                CpiContext::new_with_signer(
                    ctx.accounts.token_program.key(),
                    accounts,
                    signer_seeds,
                )
            } else {
                CpiContext::new(ctx.accounts.token_program.key(), accounts)
            };
            anchor_spl::token::transfer(cpi, amount)
        };

        for (i, (_, share)) in shares.iter().enumerate() {
            pay(ctx.remaining_accounts[i].clone(), *share)?;
        }
        let seller_amount = sale_amount
            .checked_sub(royalty_amount)
            .ok_or(VenueError::RoyaltyExceedsSale)?;
        pay(payment_recipient, seller_amount)?;

        // Delivery. Listings move via the settlement delegate; bids are
        // fulfiller-signed (the fulfiller owns the asset).
        let mpl_core_program = ctx.accounts.mpl_core_program.to_account_info();
        let settlement = ctx.accounts.settlement_authority.to_account_info();
        let fulfiller_info = ctx.accounts.fulfiller.to_account_info();
        let offerer_info = ctx.accounts.offerer.to_account_info();
        match side {
            Side::Listing => {
                mpl_core::instructions::TransferV1CpiBuilder::new(&mpl_core_program)
                    .asset(&asset_info)
                    .collection(Some(&collection_info))
                    .authority(Some(&settlement))
                    .payer(&fulfiller_info)
                    .new_owner(&fulfiller_info)
                    .invoke_signed(signer_seeds)?;
            }
            Side::Bid => {
                mpl_core::instructions::TransferV1CpiBuilder::new(&mpl_core_program)
                    .asset(&asset_info)
                    .collection(Some(&collection_info))
                    .authority(Some(&fulfiller_info))
                    .payer(&fulfiller_info)
                    .new_owner(&offerer_info)
                    .invoke()?;
            }
        }

        emit!(OrderFulfilled {
            order: ctx.accounts.order.key(),
            offerer: ctx.accounts.order.offerer,
            fulfiller: ctx.accounts.fulfiller.key(),
            sale_amount,
            royalty_receiver,
            royalty_amount,
        });
        Ok(())
    }

    /// Bulk-cancel: bump the caller's counter, invalidating all of their
    /// outstanding orders registered under the previous counter.
    pub fn increment_counter(ctx: Context<IncrementCounter>) -> Result<()> {
        let counter = &mut ctx.accounts.cancel_counter;
        counter.count = counter.count.checked_add(1).unwrap();
        emit!(CounterIncremented {
            offerer: ctx.accounts.offerer.key(),
            new_counter: counter.count,
        });
        Ok(())
    }
}

/// Shared fill-time checks: status, self-fill, counter epoch, active window.
fn check_fillable(order: &Order, fulfiller: Pubkey, current_counter: u64) -> Result<()> {
    match order.status {
        OrderStatus::Created => {}
        OrderStatus::Filled => return err!(VenueError::OrderAlreadyFilled),
        OrderStatus::Cancelled => return err!(VenueError::OrderCancelledError),
    }
    require!(fulfiller != order.offerer, VenueError::SelfFill);
    require!(order.counter == current_counter, VenueError::InvalidCounter);
    let now = Clock::get()?.unix_timestamp;
    require!(now >= order.start_time, VenueError::OrderNotYetValid);
    if order.end_time != 0 {
        require!(now < order.end_time, VenueError::OrderExpired);
    }
    Ok(())
}

/// Reads the Royalties plugin (asset first, then collection), caps the total
/// at the signed maximum, and returns (first_creator, total, per-creator
/// shares). No plugin, a zero total, or a zero sale ⇒ no royalty.
fn royalty_shares(
    asset: &AccountInfo,
    collection: &AccountInfo,
    sale_amount: u64,
    royalty_max_bps: u16,
) -> Result<(Pubkey, u64, Vec<(Pubkey, u64)>)> {
    let royalties = mpl_core::fetch_asset_plugin::<mpl_core::types::Royalties>(
        asset,
        mpl_core::types::PluginType::Royalties,
    )
    .map(|(_, r, _)| r)
    .or_else(|_| {
        mpl_core::fetch_collection_plugin::<mpl_core::types::Royalties>(
            collection,
            mpl_core::types::PluginType::Royalties,
        )
        .map(|(_, r, _)| r)
    })
    .ok();

    let Some(royalties) = royalties else {
        return Ok((Pubkey::default(), 0, vec![]));
    };
    if sale_amount == 0 || royalties.creators.is_empty() {
        return Ok((Pubkey::default(), 0, vec![]));
    }

    let plugin_amount = (sale_amount as u128) * (royalties.basis_points as u128) / 10_000;
    let max_amount = (sale_amount as u128) * (royalty_max_bps as u128) / 10_000;
    let total = plugin_amount.min(max_amount) as u64;
    if total == 0 {
        return Ok((Pubkey::default(), 0, vec![]));
    }

    let mut shares = Vec::with_capacity(royalties.creators.len());
    let mut paid: u64 = 0;
    for (i, creator) in royalties.creators.iter().enumerate() {
        let share = if i == royalties.creators.len() - 1 {
            total - paid
        } else {
            ((total as u128) * (creator.percentage as u128) / 100) as u64
        };
        paid += share;
        shares.push((creator.address, share));
    }
    Ok((royalties.creators[0].address, total, shares))
}

/// SOL variant: validates the passed creator system accounts against the
/// plugin's creator list and pairs each with its share.
fn royalty_payouts<'info>(
    asset: &AccountInfo<'info>,
    collection: &AccountInfo<'info>,
    sale_amount: u64,
    royalty_max_bps: u16,
    creator_accounts: &'info [AccountInfo<'info>],
) -> Result<(Pubkey, u64, Vec<(AccountInfo<'info>, u64)>)> {
    let (receiver, total, shares) =
        royalty_shares(asset, collection, sale_amount, royalty_max_bps)?;
    if total == 0 {
        return Ok((receiver, 0, vec![]));
    }
    require!(
        creator_accounts.len() == shares.len(),
        VenueError::CreatorAccountMismatch
    );
    let mut payouts = Vec::with_capacity(shares.len());
    for (i, (creator, share)) in shares.iter().enumerate() {
        let account = &creator_accounts[i];
        require!(account.key() == *creator, VenueError::CreatorAccountMismatch);
        payouts.push((account.clone(), *share));
    }
    Ok((receiver, total, payouts))
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug)]
pub enum Side {
    Listing,
    Bid,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug)]
pub enum OrderStatus {
    Created,
    Filled,
    Cancelled,
}

/// Stored order. An order's identity is its PDA (offerer + salt), derived
/// from this program id — a registration cannot be replayed against another
/// deployment.
#[account]
pub struct Order {
    pub offerer: Pubkey,
    pub side: Side,
    pub asset: Pubkey,
    pub core_collection: Pubkey,
    /// None = native SOL (listings only).
    pub payment_mint: Option<Pubkey>,
    pub amount: u64,
    pub royalty_max_bps: u16,
    pub start_time: i64,
    /// 0 = no expiry.
    pub end_time: i64,
    pub counter: u64,
    pub status: OrderStatus,
    pub bump: u8,
}

impl Order {
    pub const SPACE: usize = 8 + 32 + 1 + 32 + 32 + 33 + 8 + 2 + 8 + 8 + 8 + 1 + 1;
}

/// Per-offerer bulk-cancel epoch.
#[account]
pub struct CancelCounter {
    pub count: u64,
}

#[derive(Accounts)]
#[instruction(salt: u64)]
pub struct RegisterOrder<'info> {
    #[account(mut)]
    pub offerer: Signer<'info>,
    #[account(
        init,
        payer = offerer,
        space = Order::SPACE,
        seeds = [b"order", offerer.key().as_ref(), &salt.to_le_bytes()],
        bump
    )]
    pub order: Account<'info, Order>,
    #[account(
        init_if_needed,
        payer = offerer,
        space = 8 + 8,
        seeds = [b"counter", offerer.key().as_ref()],
        bump
    )]
    pub cancel_counter: Account<'info, CancelCounter>,
    /// CHECK: the venue's settlement delegate; holds no data or funds.
    #[account(seeds = [b"authority"], bump)]
    pub settlement_authority: UncheckedAccount<'info>,
    /// CHECK: validated by mpl-core when the delegate plugin is added, and
    /// bound into the order for settlement.
    #[account(mut)]
    pub asset: UncheckedAccount<'info>,
    /// CHECK: validated by mpl-core as the asset's collection.
    #[account(mut)]
    pub core_collection: UncheckedAccount<'info>,
    /// CHECK: constrained to the Metaplex Core program id.
    #[account(address = mpl_core::programs::MPL_CORE_ID)]
    pub mpl_core_program: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct FulfillOrder<'info> {
    #[account(mut)]
    pub fulfiller: Signer<'info>,
    #[account(mut, has_one = offerer, has_one = asset, has_one = core_collection)]
    pub order: Account<'info, Order>,
    /// CHECK: bound to the order by the has_one constraint; receives payment.
    #[account(mut)]
    pub offerer: UncheckedAccount<'info>,
    #[account(seeds = [b"counter", order.offerer.as_ref()], bump)]
    pub cancel_counter: Account<'info, CancelCounter>,
    /// CHECK: the venue's settlement delegate; signs the asset transfer.
    #[account(seeds = [b"authority"], bump)]
    pub settlement_authority: UncheckedAccount<'info>,
    /// CHECK: bound to the order; validated by mpl-core at transfer.
    #[account(mut)]
    pub asset: UncheckedAccount<'info>,
    /// CHECK: bound to the order; validated by mpl-core at transfer.
    #[account(mut)]
    pub core_collection: UncheckedAccount<'info>,
    /// CHECK: constrained to the Metaplex Core program id.
    #[account(address = mpl_core::programs::MPL_CORE_ID)]
    pub mpl_core_program: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct FulfillOrderSpl<'info> {
    #[account(mut)]
    pub fulfiller: Signer<'info>,
    #[account(mut, has_one = offerer, has_one = asset, has_one = core_collection)]
    pub order: Account<'info, Order>,
    /// CHECK: bound to the order by the has_one constraint.
    #[account(mut)]
    pub offerer: UncheckedAccount<'info>,
    #[account(seeds = [b"counter", order.offerer.as_ref()], bump)]
    pub cancel_counter: Account<'info, CancelCounter>,
    /// CHECK: the venue's settlement delegate; signs delegated transfers.
    #[account(seeds = [b"authority"], bump)]
    pub settlement_authority: UncheckedAccount<'info>,
    /// CHECK: bound to the order; validated by mpl-core at transfer.
    #[account(mut)]
    pub asset: UncheckedAccount<'info>,
    /// CHECK: bound to the order; validated by mpl-core at transfer.
    #[account(mut)]
    pub core_collection: UncheckedAccount<'info>,
    pub payment_mint: Account<'info, anchor_spl::token::Mint>,
    #[account(
        mut,
        constraint = fulfiller_token.mint == payment_mint.key() @ VenueError::WrongPaymentMint,
        constraint = fulfiller_token.owner == fulfiller.key() @ VenueError::WrongPaymentMint,
    )]
    pub fulfiller_token: Account<'info, TokenAccount>,
    #[account(
        mut,
        constraint = offerer_token.mint == payment_mint.key() @ VenueError::WrongPaymentMint,
        constraint = offerer_token.owner == order.offerer @ VenueError::WrongPaymentMint,
    )]
    pub offerer_token: Account<'info, TokenAccount>,
    pub token_program: Program<'info, anchor_spl::token::Token>,
    /// CHECK: constrained to the Metaplex Core program id.
    #[account(address = mpl_core::programs::MPL_CORE_ID)]
    pub mpl_core_program: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct IncrementCounter<'info> {
    #[account(mut)]
    pub offerer: Signer<'info>,
    #[account(
        init_if_needed,
        payer = offerer,
        space = 8 + 8,
        seeds = [b"counter", offerer.key().as_ref()],
        bump
    )]
    pub cancel_counter: Account<'info, CancelCounter>,
    pub system_program: Program<'info, System>,
}

#[event]
pub struct OrderCreated {
    pub order: Pubkey,
    pub offerer: Pubkey,
}

#[event]
pub struct OrderFulfilled {
    pub order: Pubkey,
    pub offerer: Pubkey,
    pub fulfiller: Pubkey,
    pub sale_amount: u64,
    pub royalty_receiver: Pubkey,
    pub royalty_amount: u64,
}

#[event]
pub struct OrderCancelled {
    pub order: Pubkey,
    pub offerer: Pubkey,
}

#[event]
pub struct CounterIncremented {
    pub offerer: Pubkey,
    pub new_counter: u64,
}

#[error_code]
pub enum VenueError {
    #[msg("royalty basis points exceed 10000")]
    RoyaltyBpsTooHigh, // 6000
    #[msg("order counter does not match the offerer's epoch")]
    InvalidCounter, // 6001
    #[msg("native-priced bids are unsupported")]
    NativeBidUnsupported, // 6002
    #[msg("invalid time window")]
    InvalidTimeWindow, // 6003
    #[msg("order expired")]
    OrderExpired, // 6004
    #[msg("offerer cannot fill their own order")]
    SelfFill, // 6005
    #[msg("order not yet valid")]
    OrderNotYetValid, // 6006
    #[msg("order already filled")]
    OrderAlreadyFilled, // 6007
    #[msg("order cancelled")]
    OrderCancelledError, // 6008
    #[msg("caller is not the offerer")]
    CallerNotOfferer, // 6009
    #[msg("royalty exceeds sale amount")]
    RoyaltyExceedsSale, // 6010
    #[msg("creator account does not match the royalties plugin")]
    CreatorAccountMismatch, // 6011
    #[msg("order is not terminal")]
    OrderNotTerminal, // 6012
    #[msg("wrong payment mint")]
    WrongPaymentMint, // 6013
}
