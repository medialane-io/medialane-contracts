use anchor_lang::prelude::*;

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
