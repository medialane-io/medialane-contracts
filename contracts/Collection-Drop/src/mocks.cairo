/// A plain ERC-20 that mints its whole supply to `recipient`.
#[starknet::contract]
pub mod MockERC20 {
    use openzeppelin_token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.erc20.initializer("Mock", "MCK");
        self.erc20.mint(recipient, amount);
    }
}

/// An ERC-20 whose transfers return false instead of reverting.
#[starknet::contract]
pub mod FalseERC20 {
    use openzeppelin_interfaces::erc20::IERC20;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            0
        }
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            0
        }
        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            0
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            false
        }
        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
        ) -> bool {
            false
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            false
        }
    }
}
