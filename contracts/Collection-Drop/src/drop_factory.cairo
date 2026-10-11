/// Deploys drops. Anyone may call `create_drop`; the caller becomes the drop's
/// organizer. No owner, no upgrade.
#[starknet::contract]
pub mod DropFactory {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::events::DropCreated;
    use crate::interfaces::IDropFactory;
    use crate::types::SaleTerms;

    pub const VERSION: felt252 = '1.0.0';

    #[storage]
    struct Storage {
        collection_class_hash: ClassHash,
        last_drop_id: u256,
        drops: Map<u256, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DropCreated: DropCreated,
    }

    #[constructor]
    fn constructor(ref self: ContractState, collection_class_hash: ClassHash) {
        assert(!collection_class_hash.is_zero(), 'Invalid class hash');
        self.collection_class_hash.write(collection_class_hash);
    }

    #[abi(embed_v0)]
    impl DropFactoryImpl of IDropFactory<ContractState> {
        fn create_drop(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            max_supply: u256,
            terms: SaleTerms,
            allowlist_root: felt252,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name is required');
            if terms.price > 0 {
                assert(!terms.payment_token.is_zero(), 'Payment token required');
            } else {
                assert(terms.payment_token.is_zero(), 'Free drop names no token');
            }
            if terms.end_time != 0 {
                assert(terms.end_time > terms.start_time, 'Invalid sale window');
            }

            let organizer = get_caller_address();
            let drop_id = self.last_drop_id.read() + 1;
            let mut calldata: Array<felt252> = array![];
            (name.clone(), symbol.clone(), base_uri.clone(), organizer, max_supply, terms, allowlist_root)
                .serialize(ref calldata);
            let (collection_address, _) = deploy_syscall(
                self.collection_class_hash.read(), drop_id.low.into(), calldata.span(), false,
            )
                .unwrap_syscall();

            self.last_drop_id.write(drop_id);
            self.drops.entry(drop_id).write(collection_address);
            self
                .emit(
                    DropCreated {
                        drop_id,
                        organizer,
                        collection_address,
                        name,
                        symbol,
                        base_uri,
                        max_supply,
                        terms,
                        allowlist_root,
                    },
                );
            collection_address
        }

        fn get_drop_address(self: @ContractState, drop_id: u256) -> ContractAddress {
            self.drops.entry(drop_id).read()
        }

        fn get_last_drop_id(self: @ContractState) -> u256 {
            self.last_drop_id.read()
        }

        fn get_collection_class_hash(self: @ContractState) -> ClassHash {
            self.collection_class_hash.read()
        }

        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
    }
}
