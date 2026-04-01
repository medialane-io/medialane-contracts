/// POPCollection — Soulbound ERC-721 collection for a single event / class / bootcamp.
///
/// Deployed by POPFactory. The organizer (ORGANIZER_ROLE) manages the allowlist.
/// The platform admin (DEFAULT_ADMIN_ROLE) has override capability for emergencies.
///
/// Only whitelisted addresses can claim a token.
/// Tokens are non-transferable (soulbound) — they function as on-chain credentials.
///
/// Per-token URI support: individual NFTs can have their own metadata URI,
/// enabling achievement tiers (e.g. max score, distinction) within the same collection.

#[starknet::contract]
pub mod POPCollection {
    use core::num::traits::Zero;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::ERC721Component;
    use openzeppelin_token::erc721::interface::IERC721Metadata;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry,
    };

    use crate::interfaces::IPOPCollection::IPOPCollection;
    use crate::events::{
        POPMinted, AllowlistUpdated, BatchAllowlistUpdated, CollectionPauseChanged, TokenURIUpdated,
    };

    /// Organizers can manage allowlists, mint, and update metadata.
    pub const ORGANIZER_ROLE: felt252 = selector!("ORGANIZER_ROLE");
    /// Safety cap — 100 addresses per batch is well within Starknet tx limits.
    pub const MAX_BATCH_SIZE: u32 = 100;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // Use ERC721Impl + ERC721CamelOnlyImpl individually instead of ERC721MixinImpl
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

    /// Soulbound: auth is zero only for mints. Any other operation (transfer/burn) reverts.
    impl ERC721SoulboundHooks of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            assert(auth.is_zero(), 'SOULBOUND_TOKEN');
        }
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
        collection_id: u256,
        claim_end_time: u64,
        paused: bool,
        last_token_id: u256,
        // Per-token URI overrides: set a custom URI per token for achievement tiers.
        // Falls back to {base_uri}{token_id} when empty.
        token_uris: Map<u256, ByteArray>,
        // allowlist[address] = true → address may call claim()
        allowlist: Map<ContractAddress, bool>,
        // claimed[address]   = true → address has already minted
        claimed: Map<ContractAddress, bool>,
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
        POPMinted: POPMinted,
        AllowlistUpdated: AllowlistUpdated,
        BatchAllowlistUpdated: BatchAllowlistUpdated,
        CollectionPauseChanged: CollectionPauseChanged,
        TokenURIUpdated: TokenURIUpdated,
    }

    /// Called by POPFactory via deploy_syscall.
    ///
    /// `platform_admin`  — Mediolano's admin address; gets DEFAULT_ADMIN_ROLE + ORGANIZER_ROLE.
    /// `organizer`       — The provider's address; gets ORGANIZER_ROLE.
    /// `base_uri`        — IPFS/Arweave URI for the collection (e.g. "ipfs://QmXXX/").
    ///                     Standard tokenURI = base_uri + token_id unless overridden per-token.
    /// `claim_end_time`  — Unix timestamp deadline. 0 = no deadline.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        collection_id: u256,
        platform_admin: ContractAddress,
        organizer: ContractAddress,
        claim_end_time: u64,
    ) {
        self.erc721.initializer(name, symbol, base_uri);
        self.accesscontrol.initializer();
        // Platform admin: emergency override + day-to-day organizer capabilities
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, platform_admin);
        self.accesscontrol._grant_role(ORGANIZER_ROLE, platform_admin);
        // Provider organizer: day-to-day management of this collection
        self.accesscontrol._grant_role(ORGANIZER_ROLE, organizer);
        self.collection_id.write(collection_id);
        self.claim_end_time.write(claim_end_time);
    }

    // ── ERC-721 Metadata with per-token URI override ──────────────────────────

    /// Implements IERC721Metadata with a custom token_uri that checks the per-token
    /// override map before falling back to the collection base URI.
    #[abi(embed_v0)]
    impl POPMetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }
        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }
        /// Resolution order:
        ///   1. Per-token URI (set via set_token_uri or admin_mint with custom_uri)
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
    impl POPCollectionImpl of IPOPCollection<ContractState> {
        // ── Allowlist management ──────────────────────────────────────────────

        fn add_to_allowlist(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            assert(!address.is_zero(), 'Invalid address');
            self.allowlist.entry(address).write(true);
            self
                .emit(
                    AllowlistUpdated {
                        user: address, allowed: true, timestamp: get_block_timestamp(),
                    },
                );
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
            self
                .emit(
                    AllowlistUpdated {
                        user: address, allowed: false, timestamp: get_block_timestamp(),
                    },
                );
        }

        // ── Collection management ─────────────────────────────────────────────

        fn set_base_uri(ref self: ContractState, new_uri: ByteArray) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            self.erc721._set_base_uri(new_uri);
        }

        fn set_token_uri(ref self: ContractState, token_id: u256, uri: ByteArray) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            self.token_uris.entry(token_id).write(uri.clone());
            self.emit(TokenURIUpdated { token_id, uri, timestamp: get_block_timestamp() });
        }

        /// Emergency pause/unpause — platform admin only, not organizer.
        fn set_paused(ref self: ContractState, paused: bool) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.paused.write(paused);
            self
                .emit(
                    CollectionPauseChanged {
                        collection_id: self.collection_id.read(),
                        paused,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        /// Mints directly to a recipient, bypassing the allowlist.
        /// Pass a non-empty `custom_uri` to assign an achievement-tier URI at mint time.
        /// Pass an empty ByteArray to use the standard collection base URI.
        fn admin_mint(ref self: ContractState, recipient: ContractAddress, custom_uri: ByteArray) {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            assert(!recipient.is_zero(), 'Invalid recipient');
            assert(!self.claimed.entry(recipient).read(), 'Already claimed');
            let token_id = self._mint_pop(recipient);
            if custom_uri.len() > 0 {
                self.token_uris.entry(token_id).write(custom_uri.clone());
                self
                    .emit(
                        TokenURIUpdated {
                            token_id, uri: custom_uri, timestamp: get_block_timestamp(),
                        },
                    );
            }
        }

        // ── Student claim ─────────────────────────────────────────────────────

        fn claim(ref self: ContractState) {
            let caller = get_caller_address();
            assert(!self.paused.read(), 'Collection is paused');
            let end_time = self.claim_end_time.read();
            if end_time > 0 {
                assert(get_block_timestamp() <= end_time, 'Claim window closed');
            }
            assert(self.allowlist.entry(caller).read(), 'Not on allowlist');
            assert(!self.claimed.entry(caller).read(), 'Already claimed');
            self._mint_pop(caller);
        }

        // ── View functions ────────────────────────────────────────────────────

        fn is_eligible(self: @ContractState, address: ContractAddress) -> bool {
            self.allowlist.entry(address).read()
        }

        fn has_claimed(self: @ContractState, address: ContractAddress) -> bool {
            self.claimed.entry(address).read()
        }

        fn get_collection_id(self: @ContractState) -> u256 {
            self.collection_id.read()
        }

        fn get_claim_end_time(self: @ContractState) -> u64 {
            self.claim_end_time.read()
        }

        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }

        fn total_minted(self: @ContractState) -> u256 {
            self.last_token_id.read()
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Mints one token to `recipient`, marks them as claimed, emits POPMinted.
        /// Returns the new token ID so callers can optionally set a per-token URI.
        fn _mint_pop(ref self: ContractState, recipient: ContractAddress) -> u256 {
            let next_token_id = self.last_token_id.read() + 1;
            self.erc721.mint(recipient, next_token_id);
            self.last_token_id.write(next_token_id);
            self.claimed.entry(recipient).write(true);
            self
                .emit(
                    POPMinted {
                        collection_id: self.collection_id.read(),
                        recipient,
                        token_id: next_token_id,
                        timestamp: get_block_timestamp(),
                    },
                );
            next_token_id
        }
    }
}
