#[cfg(test)]
mod test {
    use creator_coin::interfaces::ICreatorCoin::{
        ICreatorCoinDispatcher, ICreatorCoinDispatcherTrait,
    };
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    };
    use starknet::ContractAddress;

    // ── Test addresses ──────────────────────────────────────────────────────
    fn CREATOR() -> ContractAddress {
        0xC0FFEE.try_into().unwrap()
    }
    fn FAN() -> ContractAddress {
        0xFA11.try_into().unwrap()
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
}
