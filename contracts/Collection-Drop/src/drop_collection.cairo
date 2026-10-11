/// A drop: a standard ERC-721 whose sale terms are fixed at deployment.
///
/// Anyone may claim within the sale window (and the allowlist, when a root is set);
/// payment goes straight from the buyer to the organizer. The organizer may issue
/// free tokens within the supply cap and change the allowlist root. Nothing else
/// changes after deployment.
#[starknet::contract]
pub mod DropCollection {
    use core::num::traits::Zero;
    use core::poseidon::poseidon_hash_span;
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_interfaces::erc721::IERC721Metadata;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_merkle_tree::merkle_proof::verify_poseidon;
    use openzeppelin_token::erc721::{
        ERC721Component, ERC721HooksEmptyImpl, ERC721OwnerOfDefaultImpl,
    };
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::events::{AllowlistRootSet, Claimed, Issued};
    use crate::interfaces::IDropCollection;
    use crate::types::SaleTerms;

    pub const VERSION: felt252 = '1.0.0';

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        organizer: ContractAddress,
        max_supply: u256,
        terms: SaleTerms,
        allowlist_root: felt252,
        total_minted: u256,
        claimed_by: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        Claimed: Claimed,
        Issued: Issued,
        AllowlistRootSet: AllowlistRootSet,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        organizer: ContractAddress,
        max_supply: u256,
        terms: SaleTerms,
        allowlist_root: felt252,
    ) {
        assert(!organizer.is_zero(), 'Invalid organizer');
        self.erc721.initializer(name, symbol, base_uri);
        self.organizer.write(organizer);
        self.max_supply.write(max_supply);
        self.terms.write(terms);
        self.allowlist_root.write(allowlist_root);
    }

    #[abi(embed_v0)]
    impl ERC721MetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }

        /// `base_uri` followed by the token id.
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            let base = self.erc721._base_uri();
            if base.len() == 0 {
                return "";
            }
            format!("{}{}", base, token_id)
        }
    }

    #[abi(embed_v0)]
    impl DropCollectionImpl of IDropCollection<ContractState> {
        fn claim(ref self: ContractState, quantity: u256, proof: Span<felt252>) {
            assert(quantity > 0, 'Quantity must be positive');
            let caller = get_caller_address();
            let terms = self.terms.read();
            let now = get_block_timestamp();
            if terms.start_time != 0 {
                assert(now >= terms.start_time, 'Drop has not started');
            }
            if terms.end_time != 0 {
                assert(now <= terms.end_time, 'Drop has ended');
            }
            let root = self.allowlist_root.read();
            if root != 0 {
                let leaf = poseidon_hash_span(
                    array![poseidon_hash_span(array![caller.into()].span())].span(),
                );
                assert(verify_poseidon(proof, root, leaf), 'Not on allowlist');
            }
            let already = self.claimed_by.entry(caller).read();
            if terms.max_per_wallet != 0 {
                assert(already + quantity <= terms.max_per_wallet, 'Exceeds wallet limit');
            }

            let first_token_id = self.mint_batch(caller, quantity);
            self.claimed_by.entry(caller).write(already + quantity);
            let total_paid = terms.price * quantity;
            self.emit(Claimed { claimer: caller, quantity, first_token_id, total_paid });

            // Payment last: if it fails, the whole claim reverts.
            if total_paid > 0 {
                let token = IERC20Dispatcher { contract_address: terms.payment_token };
                assert(token.transfer_from(caller, self.organizer.read(), total_paid), 'Payment failed');
            }
        }

        fn issue(ref self: ContractState, recipient: ContractAddress, quantity: u256) {
            self.assert_only_organizer();
            assert(!recipient.is_zero(), 'Invalid recipient');
            assert(quantity > 0, 'Quantity must be positive');
            let first_token_id = self.mint_batch(recipient, quantity);
            self.emit(Issued { recipient, quantity, first_token_id });
        }

        fn set_allowlist_root(ref self: ContractState, root: felt252) {
            self.assert_only_organizer();
            self.allowlist_root.write(root);
            self.emit(AllowlistRootSet { root });
        }

        fn organizer(self: @ContractState) -> ContractAddress {
            self.organizer.read()
        }

        fn terms(self: @ContractState) -> SaleTerms {
            self.terms.read()
        }

        fn allowlist_root(self: @ContractState) -> felt252 {
            self.allowlist_root.read()
        }

        fn max_supply(self: @ContractState) -> u256 {
            self.max_supply.read()
        }

        fn total_minted(self: @ContractState) -> u256 {
            self.total_minted.read()
        }

        fn claimed_by(self: @ContractState, wallet: ContractAddress) -> u256 {
            self.claimed_by.entry(wallet).read()
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

        /// Mints `quantity` sequential tokens to `recipient`; returns the first id.
        fn mint_batch(ref self: ContractState, recipient: ContractAddress, quantity: u256) -> u256 {
            let minted = self.total_minted.read();
            let max = self.max_supply.read();
            if max != 0 {
                assert(minted + quantity <= max, 'Exceeds max supply');
            }
            self.total_minted.write(minted + quantity);
            let first = minted + 1;
            let mut i: u256 = 0;
            while i < quantity {
                self.erc721.mint(recipient, first + i);
                i += 1;
            };
            first
        }
    }
}
