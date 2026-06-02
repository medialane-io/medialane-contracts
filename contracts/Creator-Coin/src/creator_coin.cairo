/// CreatorCoin — a plain, fixed-supply ERC-20 with an immutable `creator` field.
///
/// Deliberately standard (OpenZeppelin ERC-20) so it trades on any DEX / shows in
/// any wallet (interoperability, principles 00 §8). Full supply is minted once at
/// deploy; there is no post-deploy mint. The `creator` is recorded for on-chain
/// provenance; the richer coin↔profile link lives off-chain in the indexer.
#[starknet::contract]
pub mod CreatorCoin {
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use creator_coin::interfaces::ICreatorCoin::ICreatorCoin;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    /// Standard 18 decimals (OZ 2.0 makes decimals an ImmutableConfig).
    impl CoinImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        creator: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        initial_supply: u256,
        recipient: ContractAddress,
        creator: ContractAddress,
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient, initial_supply);
        self.creator.write(creator);
    }

    #[abi(embed_v0)]
    impl CreatorCoinImpl of ICreatorCoin<ContractState> {
        fn creator(self: @ContractState) -> ContractAddress {
            self.creator.read()
        }
    }
}
