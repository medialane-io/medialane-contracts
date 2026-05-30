use starknet::ContractAddress;

/// Minimal EIP-2981 royalty NFT for marketplace tests: a standard OZ ERC721 that
/// also advertises `IERC2981_ID` via SRC5 and answers `royalty_info`.
#[starknet::contract]
pub mod MockERC721Royalty {
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use openzeppelin_token::common::erc2981::interface::IERC2981_ID;
    use openzeppelin_token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::*;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        royalty_receiver: ContractAddress,
        royalty_bps: u128,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        royalty_receiver: ContractAddress,
        royalty_bps: u128,
    ) {
        self.erc721.initializer("RoyaltyNFT", "RNFT", "");
        self.ownable.initializer(owner);
        self.src5.register_interface(IERC2981_ID);
        self.royalty_receiver.write(royalty_receiver);
        self.royalty_bps.write(royalty_bps);
    }

    #[abi(embed_v0)]
    impl MockERC721RoyaltyImpl of super::IMockERC721Royalty<ContractState> {
        fn mint_token(ref self: ContractState, recipient: ContractAddress, token_id: u256) {
            self.ownable.assert_only_owner();
            self.erc721.mint(recipient, token_id);
        }

        fn approve_token(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self.erc721.approve(to, token_id);
        }

        /// EIP-2981: royalty = sale_price * bps / 10000.
        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let amount = (sale_price * self.royalty_bps.read().into()) / 10000_u256;
            (self.royalty_receiver.read(), amount)
        }
    }
}

#[starknet::interface]
pub trait IMockERC721Royalty<TContractState> {
    fn mint_token(ref self: TContractState, recipient: ContractAddress, token_id: u256);
    fn approve_token(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
}
