#[cfg(test)]
mod test {
    use creator_coin::interfaces::ICreatorCoin::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait,
    };
    use creator_coin::interfaces::ILiquidityLock::{
        ILiquidityLockDispatcher, ILiquidityLockDispatcherTrait,
    };
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
        start_cheat_block_timestamp_global, stop_cheat_block_timestamp_global,
    };
    use starknet::ContractAddress;

    // ── Test addresses ──────────────────────────────────────────────────────
    fn CREATOR() -> ContractAddress {
        0xC0FFEE.try_into().unwrap()
    }
    fn FAN() -> ContractAddress {
        0xFA11.try_into().unwrap()
    }
    fn COIN() -> ContractAddress {
        0xC01.try_into().unwrap()
    }

    // ── Deploy helpers ──────────────────────────────────────────────────────
    fn deploy_coin(
        recipient: ContractAddress, supply: u256, creator: ContractAddress,
    ) -> ContractAddress {
        let cls = declare("CreatorCoin").unwrap().contract_class();
        let mut cd: Array<felt252> = array![];
        let name: ByteArray = "Acme Coin";
        let symbol: ByteArray = "ACME";
        (name, symbol, supply, recipient, creator).serialize(ref cd);
        let (addr, _) = cls.deploy(@cd).unwrap();
        addr
    }

    // ── CreatorCoin (Task 2) ────────────────────────────────────────────────
    #[test]
    fn test_fixed_supply_minted_to_recipient() {
        let coin = deploy_coin(CREATOR(), 1_000_000_u256, CREATOR());
        let erc20 = IERC20Dispatcher { contract_address: coin };
        assert(erc20.total_supply() == 1_000_000, 'supply wrong');
        assert(erc20.balance_of(CREATOR()) == 1_000_000, 'recipient balance wrong');
    }

    #[test]
    fn test_creator_recorded() {
        let coin = deploy_coin(CREATOR(), 1_000_000_u256, CREATOR());
        let c = ICreatorCoinDispatcher { contract_address: coin };
        assert(c.creator() == CREATOR(), 'creator wrong');
    }

    #[test]
    fn test_transfer_works() {
        let coin = deploy_coin(CREATOR(), 1_000_000_u256, CREATOR());
        let erc20 = IERC20Dispatcher { contract_address: coin };
        cheat_caller_address(coin, CREATOR(), CheatSpan::TargetCalls(1));
        erc20.transfer(FAN(), 250_000_u256);
        assert(erc20.balance_of(FAN()) == 250_000, 'fan balance wrong');
        assert(erc20.balance_of(CREATOR()) == 750_000, 'creator balance wrong');
    }

    // ── LiquidityLock (Task 3) ──────────────────────────────────────────────
    fn deploy_lock() -> ILiquidityLockDispatcher {
        let cls = declare("LiquidityLock").unwrap().contract_class();
        let (addr, _) = cls.deploy(@array![]).unwrap();
        ILiquidityLockDispatcher { contract_address: addr }
    }

    /// Lock with unlock_time = 1000, beneficiary = CREATOR.
    fn make_lock() -> (ILiquidityLockDispatcher, u64) {
        let lock = deploy_lock();
        let id = lock.lock(COIN(), CREATOR(), 7_u256, 1000_u64);
        (lock, id)
    }

    #[test]
    fn test_lock_records_beneficiary_and_unlock() {
        let (lock, id) = make_lock();
        assert(lock.beneficiary_of(id) == CREATOR(), 'beneficiary wrong');
        assert(lock.unlock_time_of(id) == 1000, 'unlock wrong');
        assert(!lock.is_withdrawn(id), 'should not be withdrawn');
    }

    #[test]
    #[should_panic(expected: ('Still locked',))]
    fn test_withdraw_before_unlock_reverts() {
        let (lock, id) = make_lock();
        start_cheat_block_timestamp_global(999_u64);
        cheat_caller_address(lock.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        lock.withdraw(id);
        stop_cheat_block_timestamp_global();
    }

    #[test]
    #[should_panic(expected: ('Not beneficiary',))]
    fn test_non_beneficiary_cannot_withdraw() {
        let (lock, id) = make_lock();
        start_cheat_block_timestamp_global(2000_u64);
        cheat_caller_address(lock.contract_address, FAN(), CheatSpan::TargetCalls(1));
        lock.withdraw(id);
        stop_cheat_block_timestamp_global();
    }

    #[test]
    fn test_withdraw_after_unlock_succeeds() {
        let (lock, id) = make_lock();
        start_cheat_block_timestamp_global(2000_u64);
        cheat_caller_address(lock.contract_address, CREATOR(), CheatSpan::TargetCalls(1));
        lock.withdraw(id);
        stop_cheat_block_timestamp_global();
        assert(lock.is_withdrawn(id), 'should be withdrawn');
    }
}
