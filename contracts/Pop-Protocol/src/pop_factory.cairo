/// Deploys POP collections. Anyone may call `create_collection`; the caller
/// becomes the collection's organizer. No owner, no upgrade.
#[starknet::contract]
pub mod POPFactory {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use crate::events::CollectionCreated;
    use crate::interfaces::IPOPFactory;

    pub const VERSION: felt252 = '1.0.0';

    #[storage]
    struct Storage {
        collection_class_hash: ClassHash,
        last_collection_id: u256,
        collections: Map<u256, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CollectionCreated: CollectionCreated,
    }

    #[constructor]
    fn constructor(ref self: ContractState, collection_class_hash: ClassHash) {
        assert(!collection_class_hash.is_zero(), 'Invalid class hash');
        self.collection_class_hash.write(collection_class_hash);
    }

    #[abi(embed_v0)]
    impl POPFactoryImpl of IPOPFactory<ContractState> {
        fn create_collection(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            claim_end_time: u64,
        ) -> ContractAddress {
            assert(name.len() > 0, 'Name is required');
            let organizer = get_caller_address();
            let collection_id = self.last_collection_id.read() + 1;

            let mut calldata: Array<felt252> = array![];
            (name.clone(), symbol.clone(), base_uri.clone(), organizer, claim_end_time)
                .serialize(ref calldata);
            let (collection_address, _) = deploy_syscall(
                self.collection_class_hash.read(), collection_id.low.into(), calldata.span(), false,
            )
                .unwrap_syscall();

            self.last_collection_id.write(collection_id);
            self.collections.entry(collection_id).write(collection_address);
            self
                .emit(
                    CollectionCreated {
                        collection_id,
                        organizer,
                        collection_address,
                        name,
                        symbol,
                        base_uri,
                        claim_end_time,
                    },
                );
            collection_address
        }

        fn get_collection_address(self: @ContractState, collection_id: u256) -> ContractAddress {
            self.collections.entry(collection_id).read()
        }

        fn get_last_collection_id(self: @ContractState) -> u256 {
            self.last_collection_id.read()
        }

        fn get_collection_class_hash(self: @ContractState) -> ClassHash {
            self.collection_class_hash.read()
        }

        fn version(self: @ContractState) -> felt252 {
            VERSION
        }
    }
}
