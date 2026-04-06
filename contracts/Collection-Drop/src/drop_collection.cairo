/// DropCollection — Limited-edition timed NFT drop collection.
///
/// Deployed by DropFactory. Each instance is a fully independent ERC-721 collection
/// with configurable claim conditions, optional allowlist, and optional pricing.
///
/// The organizer (ORGANIZER_ROLE) manages claim conditions, allowlist, and metadata.
/// The platform admin (DEFAULT_ADMIN_ROLE) has emergency pause capability.
///
/// Claim flow:
///   1. Caller invokes `claim(quantity)`.
///   2. Contract validates: not paused, time window active, supply available,
///      per-wallet limit not exceeded, allowlist (if enabled).
///   3. If price > 0: ERC-20 transferFrom caller to contract.
///   4. ERC-721 tokens are minted sequentially.
///   5. TokensClaimed event emitted with full accounting.
///
/// The organizer can update ClaimConditions at any time to run sequential phases
/// (e.g. allowlist phase → public phase) by calling `set_claim_conditions`.

#[starknet::contract]
pub mod DropCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::IERC721Metadata;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry,
    };

    use crate::interfaces::IDropCollection::IDropCollection;
    use crate::events::{
        TokensClaimed, ClaimConditionsUpdated, AllowlistUpdated, BatchAllowlistUpdated,
        AllowlistEnabledChanged, DropPauseChanged, PaymentsWithdrawn, TokenURIUpdated,
    };
    use crate::types::ClaimConditions;

    /// Organizers can manage the drop — conditions, allowlist, metadata, withdrawals.
    pub const ORGANIZER_ROLE: felt252 = selector!("ORGANIZER_ROLE");
    /// Safety cap — 100 addresses per batch is well within Starknet tx limits.
    pub const MAX_BATCH_SIZE: u32 = 100;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // Use ERC721Impl + ERC721CamelOnlyImpl individually (not ERC721MixinImpl)
    // so we can provide our own IERC721Metadata with per-token URI override.
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    /// Standard transferable ERC-721 — hooks are no-ops.
    impl ERC721DefaultHooks of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// On-chain ID assigned by the factory.
        drop_id: u256,
        /// Hard cap on total tokens. 0 = open edition (unlimited).
        max_supply: u256,
        /// Last minted token ID (also equals total minted count).
        last_token_id: u256,
        /// Active claim configuration. Updated by organizer to change phases.
        conditions: ClaimConditions,
        /// When true, only allowlisted addresses may claim.
        allowlist_enabled: bool,
        /// allowlist[address] = true → address may claim.
        allowlist: Map<ContractAddress, bool>,
        /// minted_by_wallet[address] = count of tokens already minted by that wallet.
        minted_by_wallet: Map<ContractAddress, u256>,
        /// Per-token URI overrides. Falls back to {base_uri}{token_id} when empty.
        token_uris: Map<u256, ByteArray>,
        /// Emergency stop — set by DEFAULT_ADMIN_ROLE only.
        paused: bool,
        /// Accumulated ERC-20 payments held in this contract, available for withdrawal.
        payments_received: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        TokensClaimed: TokensClaimed,
        ClaimConditionsUpdated: ClaimConditionsUpdated,
        AllowlistUpdated: AllowlistUpdated,
        BatchAllowlistUpdated: BatchAllowlistUpdated,
        AllowlistEnabledChanged: AllowlistEnabledChanged,
        DropPauseChanged: DropPauseChanged,
        PaymentsWithdrawn: PaymentsWithdrawn,
        TokenURIUpdated: TokenURIUpdated,
    }

    /// Called by DropFactory via deploy_syscall.
    ///
    /// `drop_id`           — Factory-assigned unique ID.
    /// `max_supply`        — Hard cap on total mints. 0 = open edition.
    /// `platform_admin`    — Medialane's admin address; gets DEFAULT_ADMIN_ROLE + ORGANIZER_ROLE.
    /// `organizer`         — The creator's address; gets ORGANIZER_ROLE.
    /// `initial_conditions`— Starting ClaimConditions (can be updated later for phases).
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        drop_id: u256,
        max_supply: u256,
        platform_admin: ContractAddress,
        organizer: ContractAddress,
        initial_conditions: ClaimConditions,
    ) {
        self.erc721.initializer(name, symbol, base_uri);
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, platform_admin);
        self.accesscontrol._grant_role(ORGANIZER_ROLE, platform_admin);
        self.accesscontrol._grant_role(ORGANIZER_ROLE, organizer);
        self.drop_id.write(drop_id);
        self.max_supply.write(max_supply);
        self.conditions.write(initial_conditions);
    }

    // ── ERC-721 Metadata with per-token URI override ──────────────────────────

    #[abi(embed_v0)]
    impl DropMetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }
        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }
        /// Resolution order:
        ///   1. Per-token URI (set via set_token_uri)
        ///   2. {base_uri}{token_id}  (standard ERC-721 behaviour)
        ///   3. Empty string          (if base_uri is also unset)
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            let custom = self.token_uris.entry(token_id).read();
            if custom.len() > 0 {
                return custom;
            }
            let base = self.erc721._base_uri();
            if base.len() > 0 {
                format!("{}{}", base, token_id)
            } else {
                ""
            }
        }
    }

    // ── Main interface ────────────────────────────────────────────────────────

    #[abi(embed_v0)]
    impl DropCollectionImpl of IDropCollection<ContractState> {
        // ── Minting ──────────────────────────────────────────────────────────

        fn claim(ref self: ContractState, quantity: u256) {
            assert(quantity > 0, 'Quantity must be positive');
            let caller = get_caller_address();
            self._validate_claim(caller, quantity);

            let conditions = self.conditions.read();
            let total_cost = conditions.price * quantity;

            // Collect payment before minting (checks-effects-interactions)
            if total_cost > 0 {
                let token = IERC20Dispatcher { contract_address: conditions.payment_token };
                let success = token.transfer_from(caller, get_contract_address(), total_cost);
                assert(success, 'Payment transfer failed');
                self.payments_received.write(self.payments_received.read() + total_cost);
            }

            let start_token_id = self._mint_batch(caller, quantity);

            self
                .emit(
                    TokensClaimed {
                        drop_id: self.drop_id.read(),
                        claimer: caller,
                        recipient: caller,
                        quantity,
                        start_token_id,
                        price_per_token: conditions.price,
                        total_paid: total_cost,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        fn admin_mint(
            ref self: ContractState, recipient: ContractAddress, quantity: u256, custom_uri: ByteArray,
        ) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            assert(quantity > 0, 'Quantity must be positive');
            assert(!recipient.is_zero(), 'Invalid recipient');

            // Check supply only (skip time/price/allowlist)
            let current = self.last_token_id.read();
            let max = self.max_supply.read();
            if max > 0 {
                assert(current + quantity <= max, 'Exceeds max supply');
            }

            let start_token_id = self._mint_batch(recipient, quantity);

            // Set a shared custom URI for all tokens in this admin mint if provided
            if custom_uri.len() > 0 {
                let mut i: u256 = 0;
                loop {
                    if i >= quantity {
                        break;
                    }
                    let token_id = start_token_id + i;
                    self.token_uris.entry(token_id).write(custom_uri.clone());
                    self
                        .emit(
                            TokenURIUpdated {
                                token_id, uri: custom_uri.clone(), timestamp: get_block_timestamp(),
                            },
                        );
                    i += 1;
                };
            }

            self
                .emit(
                    TokensClaimed {
                        drop_id: self.drop_id.read(),
                        claimer: get_caller_address(),
                        recipient,
                        quantity,
                        start_token_id,
                        price_per_token: 0,
                        total_paid: 0,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        // ── Claim conditions ─────────────────────────────────────────────────

        fn set_claim_conditions(ref self: ContractState, conditions: ClaimConditions) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            if conditions.price > 0 {
                assert(!conditions.payment_token.is_zero(), 'Payment token required');
            }
            if conditions.end_time > 0 {
                assert(conditions.end_time > conditions.start_time, 'end_time must be after start');
            }
            self.conditions.write(conditions.clone());
            self
                .emit(
                    ClaimConditionsUpdated {
                        drop_id: self.drop_id.read(),
                        start_time: conditions.start_time,
                        end_time: conditions.end_time,
                        price: conditions.price,
                        max_quantity_per_wallet: conditions.max_quantity_per_wallet,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        fn get_claim_conditions(self: @ContractState) -> ClaimConditions {
            self.conditions.read()
        }

        // ── Allowlist ────────────────────────────────────────────────────────

        fn set_allowlist_enabled(ref self: ContractState, enabled: bool) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            self.allowlist_enabled.write(enabled);
            self
                .emit(
                    AllowlistEnabledChanged {
                        drop_id: self.drop_id.read(), enabled, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn is_allowlist_enabled(self: @ContractState) -> bool {
            self.allowlist_enabled.read()
        }

        fn add_to_allowlist(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            assert(!address.is_zero(), 'Invalid address');
            self.allowlist.entry(address).write(true);
            self.emit(AllowlistUpdated { user: address, allowed: true, timestamp: get_block_timestamp() });
        }

        fn batch_add_to_allowlist(ref self: ContractState, addresses: Span<ContractAddress>) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            let count = addresses.len();
            assert(count <= MAX_BATCH_SIZE, 'Batch too large');
            let mut i = 0;
            loop {
                if i >= count {
                    break;
                }
                let addr = *addresses.at(i);
                assert(!addr.is_zero(), 'Invalid address in batch');
                self.allowlist.entry(addr).write(true);
                i += 1;
            };
            self.emit(BatchAllowlistUpdated { count, timestamp: get_block_timestamp() });
        }

        fn remove_from_allowlist(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            self.allowlist.entry(address).write(false);
            self.emit(AllowlistUpdated { user: address, allowed: false, timestamp: get_block_timestamp() });
        }

        fn is_allowlisted(self: @ContractState, address: ContractAddress) -> bool {
            self.allowlist.entry(address).read()
        }

        // ── Metadata ─────────────────────────────────────────────────────────

        fn set_base_uri(ref self: ContractState, new_uri: ByteArray) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            self.erc721._set_base_uri(new_uri);
        }

        fn set_token_uri(ref self: ContractState, token_id: u256, uri: ByteArray) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            self.token_uris.entry(token_id).write(uri.clone());
            self.emit(TokenURIUpdated { token_id, uri, timestamp: get_block_timestamp() });
        }

        // ── Admin ────────────────────────────────────────────────────────────

        fn set_paused(ref self: ContractState, paused: bool) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.paused.write(paused);
            self
                .emit(
                    DropPauseChanged {
                        drop_id: self.drop_id.read(), paused, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn withdraw_payments(ref self: ContractState) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            let conditions = self.conditions.read();
            assert(!conditions.payment_token.is_zero(), 'No payment token configured');

            let token = IERC20Dispatcher { contract_address: conditions.payment_token };
            let balance = token.balance_of(get_contract_address());
            assert(balance > 0, 'No payments to withdraw');

            let caller = get_caller_address();
            let success = token.transfer(caller, balance);
            assert(success, 'Withdrawal failed');
            self.payments_received.write(0);

            self
                .emit(
                    PaymentsWithdrawn {
                        drop_id: self.drop_id.read(),
                        to: caller,
                        amount: balance,
                        token: conditions.payment_token,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        // ── Views ────────────────────────────────────────────────────────────

        fn get_drop_id(self: @ContractState) -> u256 {
            self.drop_id.read()
        }

        fn get_max_supply(self: @ContractState) -> u256 {
            self.max_supply.read()
        }

        fn total_minted(self: @ContractState) -> u256 {
            self.last_token_id.read()
        }

        fn remaining_supply(self: @ContractState) -> u256 {
            let max = self.max_supply.read();
            if max == 0 {
                // Open edition — u256::MAX as sentinel for unlimited
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256
            } else {
                let minted = self.last_token_id.read();
                if minted >= max {
                    0
                } else {
                    max - minted
                }
            }
        }

        fn minted_by_wallet(self: @ContractState, wallet: ContractAddress) -> u256 {
            self.minted_by_wallet.entry(wallet).read()
        }

        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Validates a claim request against all active conditions.
        fn _validate_claim(ref self: ContractState, claimer: ContractAddress, quantity: u256) {
            assert(!self.paused.read(), 'Drop is paused');

            let conditions = self.conditions.read();
            let now = get_block_timestamp();

            if conditions.start_time > 0 {
                assert(now >= conditions.start_time, 'Drop has not started');
            }
            if conditions.end_time > 0 {
                assert(now <= conditions.end_time, 'Drop has ended');
            }

            // Supply check
            let current = self.last_token_id.read();
            let max = self.max_supply.read();
            if max > 0 {
                assert(current + quantity <= max, 'Exceeds max supply');
            }

            // Per-wallet limit
            if conditions.max_quantity_per_wallet > 0 {
                let already_minted = self.minted_by_wallet.entry(claimer).read();
                assert(
                    already_minted + quantity <= conditions.max_quantity_per_wallet,
                    'Exceeds wallet limit',
                );
            }

            // Allowlist gate
            if self.allowlist_enabled.read() {
                assert(self.allowlist.entry(claimer).read(), 'Not on allowlist');
            }
        }

        /// Mints `quantity` tokens sequentially to `recipient`.
        /// Returns the start token ID of the batch.
        fn _mint_batch(
            ref self: ContractState, recipient: ContractAddress, quantity: u256,
        ) -> u256 {
            let start_token_id = self.last_token_id.read() + 1;
            let mut i: u256 = 0;
            loop {
                if i >= quantity {
                    break;
                }
                self.erc721.mint(recipient, start_token_id + i);
                i += 1;
            };
            self.last_token_id.write(start_token_id + quantity - 1);
            // Update per-wallet mint count
            let prev = self.minted_by_wallet.entry(recipient).read();
            self.minted_by_wallet.entry(recipient).write(prev + quantity);
            start_token_id
        }
    }
}
