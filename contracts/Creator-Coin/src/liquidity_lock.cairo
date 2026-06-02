/// LiquidityLock — custodies an AMM LP position NFT until an unlock time.
///
/// The factory provisions liquidity, the adapter transfers the position NFT to
/// this contract, then the factory records the lock here. Only the recorded
/// `beneficiary` (the creator) may withdraw, and only at/after `unlock_time`;
/// withdraw transfers the position NFT back to the beneficiary. This is the
/// on-chain expression of the anti-rug guarantee (locked liquidity).
#[starknet::contract]
pub mod LiquidityLock {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry,
    };
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use creator_coin::interfaces::ILiquidityLock::ILiquidityLock;
    use creator_coin::events::{LiquidityLocked, LiquidityWithdrawn};

    #[storage]
    struct Storage {
        last_lock_id: u64,
        coin: Map<u64, ContractAddress>,
        beneficiary: Map<u64, ContractAddress>,
        nft_address: Map<u64, ContractAddress>,
        position_id: Map<u64, u256>,
        unlock_time: Map<u64, u64>,
        withdrawn: Map<u64, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LiquidityLocked: LiquidityLocked,
        LiquidityWithdrawn: LiquidityWithdrawn,
    }

    #[abi(embed_v0)]
    impl LiquidityLockImpl of ILiquidityLock<ContractState> {
        fn lock(
            ref self: ContractState,
            coin_address: ContractAddress,
            beneficiary: ContractAddress,
            nft_address: ContractAddress,
            position_id: u256,
            unlock_time: u64,
        ) -> u64 {
            let id = self.last_lock_id.read() + 1;
            self.last_lock_id.write(id);
            self.coin.entry(id).write(coin_address);
            self.beneficiary.entry(id).write(beneficiary);
            self.nft_address.entry(id).write(nft_address);
            self.position_id.entry(id).write(position_id);
            self.unlock_time.entry(id).write(unlock_time);
            self.withdrawn.entry(id).write(false);
            self
                .emit(
                    LiquidityLocked {
                        lock_id: id, coin_address, beneficiary, position_id, unlock_time,
                    },
                );
            id
        }

        fn withdraw(ref self: ContractState, lock_id: u64) {
            let caller = get_caller_address();
            assert(caller == self.beneficiary.entry(lock_id).read(), 'Not beneficiary');
            assert(!self.withdrawn.entry(lock_id).read(), 'Already withdrawn');
            assert(get_block_timestamp() >= self.unlock_time.entry(lock_id).read(), 'Still locked');
            self.withdrawn.entry(lock_id).write(true);
            // Return the LP position NFT to the beneficiary.
            IERC721Dispatcher { contract_address: self.nft_address.entry(lock_id).read() }
                .transfer_from(
                    get_contract_address(), caller, self.position_id.entry(lock_id).read(),
                );
            self
                .emit(
                    LiquidityWithdrawn {
                        lock_id, beneficiary: caller, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn beneficiary_of(self: @ContractState, lock_id: u64) -> ContractAddress {
            self.beneficiary.entry(lock_id).read()
        }
        fn unlock_time_of(self: @ContractState, lock_id: u64) -> u64 {
            self.unlock_time.entry(lock_id).read()
        }
        fn nft_address_of(self: @ContractState, lock_id: u64) -> ContractAddress {
            self.nft_address.entry(lock_id).read()
        }
        fn position_id_of(self: @ContractState, lock_id: u64) -> u256 {
            self.position_id.entry(lock_id).read()
        }
        fn is_withdrawn(self: @ContractState, lock_id: u64) -> bool {
            self.withdrawn.entry(lock_id).read()
        }
    }
}
