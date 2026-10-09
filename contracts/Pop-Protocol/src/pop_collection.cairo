/// Soulbound ERC-721 credential collection for one event.
///
/// The organizer (fixed at deployment) publishes an allowlist Merkle root and may
/// issue tokens directly. Any listed address may claim one token with its proof.
/// Tokens cannot be transferred or approved; only their holder can burn them.
/// Metadata is fixed at deployment.
#[starknet::contract]
pub mod POPCollection {
    use core::num::traits::Zero;
    use core::poseidon::poseidon_hash_span;
    use openzeppelin_interfaces::erc721::{IERC721, IERC721Metadata};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_merkle_tree::merkle_proof::verify_poseidon;
    use openzeppelin_token::erc721::{ERC721Component, ERC721OwnerOfDefaultImpl};
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::events::{AllowlistRootSet, Locked, TokenURISet};
    use crate::interfaces::{IERC5192, IERC5192_ID, IPOPCollection};

    pub const VERSION: felt252 = '1.0.0';

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    /// Only mints and burns pass: a token never moves to another holder.
    impl SoulboundHooks of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            assert(to.is_zero() || self.ERC721_owners.read(token_id).is_zero(), 'SOULBOUND');
        }
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        organizer: ContractAddress,
        claim_end_time: u64,
        allowlist_root: felt252,
        last_token_id: u256,
        claimed: Map<ContractAddress, bool>,
        token_uris: Map<u256, ByteArray>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        AllowlistRootSet: AllowlistRootSet,
        TokenURISet: TokenURISet,
        Locked: Locked,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        organizer: ContractAddress,
        claim_end_time: u64,
    ) {
        assert(!organizer.is_zero(), 'Invalid organizer');
        self.erc721.initializer(name, symbol, base_uri);
        self.src5.register_interface(IERC5192_ID);
        self.organizer.write(organizer);
        self.claim_end_time.write(claim_end_time);
    }

    #[abi(embed_v0)]
    impl ERC721Impl of IERC721<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            assert(!account.is_zero(), 'ERC721: invalid account');
            self.erc721.ERC721_balances.read(account)
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._require_owned(token_id)
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            core::panic_with_felt252('SOULBOUND')
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256,
        ) {
            core::panic_with_felt252('SOULBOUND')
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            core::panic_with_felt252('SOULBOUND')
        }

        fn set_approval_for_all(ref self: ContractState, operator: ContractAddress, approved: bool) {
            core::panic_with_felt252('SOULBOUND')
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721._require_owned(token_id);
            Zero::zero()
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress,
        ) -> bool {
            false
        }
    }

    #[abi(embed_v0)]
    impl ERC721MetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }

        /// The token's own URI if it was issued with one, else the collection URI.
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            let custom = self.token_uris.entry(token_id).read();
            if custom.len() > 0 {
                custom
            } else {
                self.erc721._base_uri()
            }
        }
    }

    #[abi(embed_v0)]
    impl ERC5192Impl of IERC5192<ContractState> {
        fn locked(self: @ContractState, token_id: u256) -> bool {
            self.erc721._require_owned(token_id);
            true
        }
    }

    #[abi(embed_v0)]
    impl POPCollectionImpl of IPOPCollection<ContractState> {
        fn set_allowlist_root(ref self: ContractState, root: felt252) {
            self.assert_only_organizer();
            self.allowlist_root.write(root);
            self.emit(AllowlistRootSet { root });
        }

        fn claim(ref self: ContractState, proof: Span<felt252>) {
            let caller = get_caller_address();
            let root = self.allowlist_root.read();
            assert(root != 0, 'Claims are closed');
            let end = self.claim_end_time.read();
            if end != 0 {
                assert(get_block_timestamp() <= end, 'Claim window closed');
            }
            let leaf = poseidon_hash_span(
                array![poseidon_hash_span(array![caller.into()].span())].span(),
            );
            assert(verify_poseidon(proof, root, leaf), 'Not on allowlist');
            self.mint_to(caller, "");
        }

        fn issue(ref self: ContractState, recipient: ContractAddress, token_uri: ByteArray) {
            self.assert_only_organizer();
            assert(!recipient.is_zero(), 'Invalid recipient');
            self.mint_to(recipient, token_uri);
        }

        fn burn(ref self: ContractState, token_id: u256) {
            let holder = self.erc721._require_owned(token_id);
            assert(get_caller_address() == holder, 'Caller is not the holder');
            self.erc721.burn(token_id);
        }

        fn organizer(self: @ContractState) -> ContractAddress {
            self.organizer.read()
        }

        fn allowlist_root(self: @ContractState) -> felt252 {
            self.allowlist_root.read()
        }

        fn claim_end_time(self: @ContractState) -> u64 {
            self.claim_end_time.read()
        }

        fn has_claimed(self: @ContractState, address: ContractAddress) -> bool {
            self.claimed.entry(address).read()
        }

        fn total_issued(self: @ContractState) -> u256 {
            self.last_token_id.read()
        }

        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_only_organizer(self: @ContractState) {
            assert(get_caller_address() == self.organizer.read(), 'Caller is not the organizer');
        }

        fn mint_to(ref self: ContractState, recipient: ContractAddress, token_uri: ByteArray) {
            assert(!self.claimed.entry(recipient).read(), 'Already issued');
            let token_id = self.last_token_id.read() + 1;
            self.last_token_id.write(token_id);
            self.claimed.entry(recipient).write(true);
            self.erc721.mint(recipient, token_id);
            if token_uri.len() > 0 {
                self.token_uris.entry(token_id).write(token_uri.clone());
                self.emit(TokenURISet { token_id, uri: token_uri });
            }
            self.emit(Locked { token_id });
        }
    }
}
