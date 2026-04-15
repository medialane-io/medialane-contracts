// MockERC1155WithRoyalty — an ERC-1155 mock that also implements ERC-2981.
//
// Used in tests to verify that Medialane1155 correctly reads and distributes
// on-chain royalties during order fulfillment.
//
// The royalty rate is configurable: owner calls `set_royalty(receiver, fee_numerator)`
// where fee_numerator is out of 10,000 (e.g. 500 = 5%).

use starknet::ContractAddress;

#[starknet::contract]
pub mod MockERC1155 {
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::*;

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // ERC1155MixinImpl already embeds SRC5 — do not embed SRC5Impl separately
    // or supports_interface will be duplicated and fail ABI generation.
    #[abi(embed_v0)]
    impl ERC1155MixinImpl = ERC1155Component::ERC1155MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    // ERC-2981 interface ID
    const IERC2981_ID: felt252 = 0x2d3414e45a8700c29f119a54b9f11dca0e29e06ddcb214018fc37340e165d6b;
    const FEE_DENOMINATOR: u256 = 10000;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        royalty_receiver: ContractAddress,
        royalty_fee_numerator: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        // Register ERC-2981 in SRC5 so Medialane1155 can detect it
        self.src5.register_interface(IERC2981_ID);
    }

    #[abi(embed_v0)]
    pub impl MockERC1155Impl of super::IMockERC1155<ContractState> {
        fn mint(
            ref self: ContractState,
            account: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>,
        ) {
            self.ownable.assert_only_owner();
            self.erc1155.mint_with_acceptance_check(account, token_id, value, data);
        }

        fn approve(ref self: ContractState, operator: ContractAddress, approved: bool) {
            self.erc1155.set_approval_for_all(operator, approved);
        }

        /// Configure the ERC-2981 royalty. fee_numerator is out of 10,000.
        /// Call with fee_numerator=0 or receiver=zero to disable royalties.
        fn set_royalty(
            ref self: ContractState, receiver: ContractAddress, fee_numerator: u256,
        ) {
            self.ownable.assert_only_owner();
            self.royalty_receiver.write(receiver);
            self.royalty_fee_numerator.write(fee_numerator);
        }

        /// ERC-2981: returns (receiver, royalty_amount) for a given sale price.
        fn royalty_info(
            self: @ContractState, token_id: u256, sale_price: u256,
        ) -> (ContractAddress, u256) {
            let receiver = self.royalty_receiver.read();
            let numerator = self.royalty_fee_numerator.read();
            if numerator == 0 {
                return (receiver, 0);
            }
            let royalty_amount = sale_price * numerator / FEE_DENOMINATOR;
            (receiver, royalty_amount)
        }
    }
}

#[starknet::interface]
pub trait IMockERC1155<TContractState> {
    fn mint(
        ref self: TContractState,
        account: ContractAddress,
        token_id: u256,
        value: u256,
        data: Span<felt252>,
    );
    fn approve(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn set_royalty(
        ref self: TContractState, receiver: ContractAddress, fee_numerator: u256,
    );
    fn royalty_info(
        self: @TContractState, token_id: u256, sale_price: u256,
    ) -> (ContractAddress, u256);
}
