// NOTE: Signature arrays in these tests were computed with StarknetJS using the
// SNIP-12 domain { name: 'Medialane', version: 2 } and the type hashes defined
// in src/core/utils.cairo.  Run scripts/compute_signatures.mjs to regenerate them
// if the domain, type strings, or test account addresses change.
//
// snforge chain ID: 0x534e5f5345504f4c4941 (SN_SEPOLIA in ASCII)

#[cfg(test)]
    mod test {
    use medialane_erc1155::core::medialane::Medialane1155V2;
    use medialane_erc1155::core::interface::{
        IMedialane1155V2Dispatcher, IMedialane1155V2DispatcherTrait,
    };
    use medialane_erc1155::core::types::*;
    use medialane_erc1155::core::events::*;
    use medialane_erc1155::mocks::erc1155::{IMockERC1155Dispatcher, IMockERC1155DispatcherTrait};
    use medialane_erc1155::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use openzeppelin_account::interface::AccountABIDispatcher;
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
        cheat_caller_address, declare, spy_events, start_cheat_block_timestamp,
    };
    use starknet::ContractAddress;

    // -------------------------------------------------------------------------
    // Pre-computed SNIP-12 signatures (computed with scripts/compute_signatures.mjs)
    // Domain: { name: 'Medialane', version: 2, chainId: SN_SEPOLIA }
    // offerer  private key: 0x1a2b3c4d5e6f
    // fulfiller private key: 0xdeadbeef1234
    // -------------------------------------------------------------------------

    fn erc20_erc1155_order_signature() -> Array<felt252> {
        array![
            0x31cd8027c023e4d562741262ea193a80f005d043242025f3cc7caa1a1833db,
            0x3c5f226fe775e71fb27dee2e5f038826b178f95bacec7f7acdbe8c859424931,
        ]
    }

    // Full fill: quantity = 10, nonce = 0
    fn erc20_erc1155_fulfillment_signature() -> Array<felt252> {
        array![
            0x5d17f68018f458e1dcd0de1d446285f421a35d16d279bfc308894e247cb5e8d,
            0xf1b587d781bae219861cdd1791a859135890cd930ef723652d0497056da50e,
        ]
    }

    // Partial fill: quantity = 5, nonce = 0
    fn erc20_erc1155_partial_fulfillment_signature() -> Array<felt252> {
        array![
            0x1a3898122a7ba533950214bb450819c9da6ad7f7bb1542ddcc39289711fc9f2,
            0x4b1158e77be48bb687f6afd9603d9f34724e6452b54dacae77e55d9b940843b,
        ]
    }

    // nonce = 1: offerer nonce 0 is consumed by register_order, cancel uses nonce 1
    fn erc20_erc1155_cancel_signature() -> Array<felt252> {
        array![
            0x11b1aca0383154e5673347578868493b65c080053404114d67e9c5cfcbecd64,
            0x1541458d7ee9278bb29b8eed0bf2eeaf305b24e118b7cb31481e12dcccd8434,
        ]
    }

    fn native_erc1155_order_signature() -> Array<felt252> {
        array![
            0x62a395747e2b83fd6b9d55cb44db8c6e213a3fc09012fb65b51ddc8609c4f85,
            0xef8e4fa1a0f03aa3f7a3154c0a4a79790b08ae2862d39f72ab52d2ab85fdbc,
        ]
    }

    fn native_erc1155_fulfillment_signature() -> Array<felt252> {
        array![
            0x732347287ea2fecdd0c6bc5c6d88bf276744d5b7bd4de48c2ed4ed1b2127056,
            0x37dcb553cc80e2d55b37657f662f8c1a9fb7d90c1345239a515a3bf4eeefb1f,
        ]
    }

    fn erc20_for_erc1155_bid_order_signature() -> Array<felt252> {
        array![
            0x7431432f091d9380c7271a09e42405a95639f0f995cd816a624e529cefc9082,
            0x70a17b6700733ab77358a967c5635e711a667019e7d9e39ab34241e91c46bf5,
        ]
    }

    fn erc20_for_erc1155_bid_fulfillment_signature() -> Array<felt252> {
        array![
            0x2753ea110be035405406472495491f58d11ab960072a177bc1a1e2ac080b88f,
            0x42dbc52e61cbe9ca8314aadda96005dfd56e111f294f59faa3db30fcc12088b,
        ]
    }

    fn erc20_for_erc1155_bid_partial_fulfillment_signature() -> Array<felt252> {
        array![
            0xc5c006363424db917ac83463de740cac5a0ce48118b3f03e4364bb40ee0cdf,
            0xe747c2ea00ef8c0979a2c3c0441d5584c61829fa2898e3a3819a15386d7fc1,
        ]
    }

    fn native_for_erc1155_bid_order_signature() -> Array<felt252> {
        array![
            0x5dec8ccf0f9301782f306c02073608f202dda82ca20079b18ee9676224fe96f,
            0x66eac7c2fef7e57ce5b0c2a02993f9736ff1c051683ae354cac40731550ddd8,
        ]
    }

    fn native_for_erc1155_bid_fulfillment_signature() -> Array<felt252> {
        array![
            0x7f312bcb1b079e660c6d868efa75dc53f55478aea98bbd84006f07df9fdec5,
            0x7606de5fa8baffba5d8e25fa895bd8e114c0d06eef152e2d64569bf63bbe9a4,
        ]
    }

    fn invalid_signature() -> Array<felt252> {
        array![
            0x19c559e58bf68cc202bce6435bc16fffc2c21ef2d984b288d040ea99c0232c5,
            0x7c0649a8f7b8bc8e5f3918c181d1987934fed7ac108995ec3288aecd6535740,
        ]
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    const OWNER_ADDRESS: felt252 = 0x1001;
    const TOKEN_ID: felt252 = 1;
    const TOKEN_AMOUNT: felt252 = 10;
    const PRICE_PER_UNIT: felt252 = 1000000;
    const ROYALTY_FEE: u256 = 500; // 5% in basis points (out of 10 000)

    // -------------------------------------------------------------------------
    // Test structs
    // -------------------------------------------------------------------------

    #[derive(Clone, Drop)]
    struct DeployedContracts {
        medialane: IMedialane1155V2Dispatcher,
        erc20: IMockERC20Dispatcher,
        erc1155: IMockERC1155Dispatcher,
    }

    #[derive(Clone, Drop, Debug)]
    struct Accounts {
        owner: ContractAddress,
        offerer: ContractAddress,
        fulfiller: ContractAddress,
        royalty_receiver: ContractAddress,
    }

    // -------------------------------------------------------------------------
    // Deploy helpers
    // -------------------------------------------------------------------------

    fn deploy_contract(
        contract_name: ByteArray,
        calldata: @Array<felt252>,
        contract_address: ContractAddress,
    ) -> ContractAddress {
        let contract = declare(contract_name).unwrap().contract_class();
        let (addr, _) = contract.deploy_at(calldata, contract_address).unwrap();
        addr
    }

    fn deploy_medialane(native_token: ContractAddress) -> IMedialane1155V2Dispatcher {
        let expected: ContractAddress =
            0x2a0626d1a71fab6c6cdcb262afc48bff92a6844700ebbd16297596e6c53da29
            .try_into()
            .unwrap();
        let mut calldata = array![];
        native_token.serialize(ref calldata);
        let addr = deploy_contract("Medialane1155V2", @calldata, expected);
        IMedialane1155V2Dispatcher { contract_address: addr }
    }

    fn deploy_erc20(owner: ContractAddress) -> IMockERC20Dispatcher {
        let expected: ContractAddress =
            0x0589edc6e13293530fec9cad58787ed8cff1fce35c3ef80342b7b00651e04d1f
            .try_into()
            .unwrap();
        let mut calldata = array![];
        owner.serialize(ref calldata);
        let addr = deploy_contract("MockERC20", @calldata, expected);
        IMockERC20Dispatcher { contract_address: addr }
    }

    fn deploy_erc1155(owner: ContractAddress) -> IMockERC1155Dispatcher {
        let expected: ContractAddress =
            0x07ca2d381f55b159ea4c80abf84d4343fde9989854a6be2f02585daae7d89d76
            .try_into()
            .unwrap();
        let mut calldata = array![];
        owner.serialize(ref calldata);
        let addr = deploy_contract("MockERC1155", @calldata, expected);
        IMockERC1155Dispatcher { contract_address: addr }
    }

    fn deploy_account(
        public_key: ContractAddress, account_address: ContractAddress,
    ) -> AccountABIDispatcher {
        let mut calldata = array![];
        public_key.serialize(ref calldata);
        let addr = deploy_contract("MockAccount", @calldata, account_address);
        AccountABIDispatcher { contract_address: addr }
    }

    fn setup_accounts() -> Accounts {
        let offerer_pub_key: ContractAddress =
            0x0161523dc3f079d9daf9d97ff87ea448c93e2dc4153e7010d45203ff97f4dfbe
            .try_into()
            .unwrap();
        let offerer_address: ContractAddress =
            0x040204472aef47d0aa8d68316e773f09a6f7d8d10ff6d30363b353ef3f2d1305
            .try_into()
            .unwrap();
        let offerer = deploy_account(offerer_pub_key, offerer_address);

        let fulfiller_pub_key: ContractAddress =
            0x074302e19249520569d2cd18869a304dfd1fbfced5760cd8e0ddfe621077d2e2
            .try_into()
            .unwrap();
        let fulfiller_address: ContractAddress =
            0x01d0c57c28e34bf6407c2fbfadbda7ae59d39ff9c8f9ac4ec3fa32ec784fb549
            .try_into()
            .unwrap();
        let fulfiller = deploy_account(fulfiller_pub_key, fulfiller_address);

        Accounts {
            owner: OWNER_ADDRESS.try_into().unwrap(),
            offerer: offerer.contract_address,
            fulfiller: fulfiller.contract_address,
            royalty_receiver: 0x9999.try_into().unwrap(),
        }
    }

    fn setup() -> (DeployedContracts, Accounts) {
        let accounts = setup_accounts();
        let erc20 = deploy_erc20(accounts.owner);
        let medialane = deploy_medialane(erc20.contract_address);
        let erc1155 = deploy_erc1155(accounts.owner);
        (DeployedContracts { medialane, erc20, erc1155 }, accounts)
    }

    fn default_order_params(
        offerer: ContractAddress,
        nft_contract: ContractAddress,
        payment_token: ContractAddress,
    ) -> OrderParameters {
        OrderParameters {
            offerer,
            offer: OfferItem {
                item_type: 'ERC1155',
                token: nft_contract,
                identifier_or_criteria: TOKEN_ID,
                start_amount: TOKEN_AMOUNT,
                end_amount: TOKEN_AMOUNT,
            },
            consideration: ConsiderationItem {
                item_type: 'ERC20',
                token: payment_token,
                identifier_or_criteria: 0,
                start_amount: PRICE_PER_UNIT,
                end_amount: PRICE_PER_UNIT,
                recipient: offerer,
            },
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        }
    }

    fn default_native_order_params(
        offerer: ContractAddress, nft_contract: ContractAddress,
    ) -> OrderParameters {
        let zero: ContractAddress = 0.try_into().unwrap();
        OrderParameters {
            offerer,
            offer: OfferItem {
                item_type: 'ERC1155',
                token: nft_contract,
                identifier_or_criteria: TOKEN_ID,
                start_amount: TOKEN_AMOUNT,
                end_amount: TOKEN_AMOUNT,
            },
            consideration: ConsiderationItem {
                item_type: 'NATIVE',
                token: zero,
                identifier_or_criteria: 0,
                start_amount: PRICE_PER_UNIT,
                end_amount: PRICE_PER_UNIT,
                recipient: offerer,
            },
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        }
    }

    fn default_bid_order_params(
        buyer: ContractAddress,
        nft_contract: ContractAddress,
        payment_token: ContractAddress,
    ) -> OrderParameters {
        OrderParameters {
            offerer: buyer,
            offer: OfferItem {
                item_type: 'ERC20',
                token: payment_token,
                identifier_or_criteria: 0,
                start_amount: PRICE_PER_UNIT,
                end_amount: PRICE_PER_UNIT,
            },
            consideration: ConsiderationItem {
                item_type: 'ERC1155',
                token: nft_contract,
                identifier_or_criteria: TOKEN_ID,
                start_amount: TOKEN_AMOUNT,
                end_amount: TOKEN_AMOUNT,
                recipient: buyer,
            },
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        }
    }

    fn default_native_bid_order_params(
        buyer: ContractAddress,
        nft_contract: ContractAddress,
    ) -> OrderParameters {
        let zero: ContractAddress = 0.try_into().unwrap();
        OrderParameters {
            offerer: buyer,
            offer: OfferItem {
                item_type: 'NATIVE',
                token: zero,
                identifier_or_criteria: 0,
                start_amount: PRICE_PER_UNIT,
                end_amount: PRICE_PER_UNIT,
            },
            consideration: ConsiderationItem {
                item_type: 'ERC1155',
                token: nft_contract,
                identifier_or_criteria: TOKEN_ID,
                start_amount: TOKEN_AMOUNT,
                end_amount: TOKEN_AMOUNT,
                recipient: buyer,
            },
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        }
    }

    /// Mints TOKEN_AMOUNT ERC-1155 tokens to the listing seller and approves Medialane.
    fn setup_listing_seller_erc1155(
        contracts: @DeployedContracts, accounts: @Accounts,
    ) {
        cheat_caller_address(
            (*contracts.erc1155).contract_address, *accounts.owner, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc1155).mint(*accounts.offerer, 1_u256, 10_u256, array![].span());

        cheat_caller_address(
            (*contracts.erc1155).contract_address, *accounts.offerer, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc1155).approve((*contracts.medialane).contract_address, true);
    }

    /// Mints TOKEN_AMOUNT ERC-1155 tokens to the bid-accepting seller and approves Medialane.
    fn setup_bid_seller_erc1155(
        contracts: @DeployedContracts, accounts: @Accounts,
    ) {
        cheat_caller_address(
            (*contracts.erc1155).contract_address, *accounts.owner, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc1155).mint(*accounts.fulfiller, 1_u256, 10_u256, array![].span());

        cheat_caller_address(
            (*contracts.erc1155).contract_address, *accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc1155).approve((*contracts.medialane).contract_address, true);
    }

    /// Mints `amount` ERC-20 tokens to the bid buyer and approves Medialane.
    fn setup_bid_buyer_erc20(
        contracts: @DeployedContracts, accounts: @Accounts, amount: u256,
    ) {
        cheat_caller_address(
            (*contracts.erc20).contract_address, *accounts.owner, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc20).mint_token(*accounts.offerer, amount);

        cheat_caller_address(
            (*contracts.erc20).contract_address, *accounts.offerer, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc20).approve_token((*contracts.medialane).contract_address, amount);
    }

    /// Mints `amount` ERC-20 tokens to the listing buyer and approves Medialane.
    fn setup_listing_buyer_erc20(
        contracts: @DeployedContracts, accounts: @Accounts, amount: u256,
    ) {
        cheat_caller_address(
            (*contracts.erc20).contract_address, *accounts.owner, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc20).mint_token(*accounts.fulfiller, amount);

        cheat_caller_address(
            (*contracts.erc20).contract_address, *accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        (*contracts.erc20).approve_token((*contracts.medialane).contract_address, amount);
    }

    // -------------------------------------------------------------------------
    // Unit tests — order hash
    // -------------------------------------------------------------------------

    #[test]
    fn test_get_order_hash_is_deterministic() {
        let (contracts, accounts) = setup();
        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let h1 = contracts.medialane.get_order_hash(params, accounts.offerer);
        let h2 = contracts.medialane.get_order_hash(params, accounts.offerer);
        assert_eq!(h1, h2);
    }

    #[test]
    fn test_order_hash_differs_by_token_id() {
        let (contracts, accounts) = setup();
        let params1 = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let mut params2 = params1;
        params2.offer.identifier_or_criteria = 2;
        assert_ne!(
            contracts.medialane.get_order_hash(params1, accounts.offerer),
            contracts.medialane.get_order_hash(params2, accounts.offerer),
        );
    }

    #[test]
    fn test_order_hash_differs_by_amount() {
        let (contracts, accounts) = setup();
        let params1 = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let mut params2 = params1;
        params2.offer.start_amount = 5;
        params2.offer.end_amount = 5;
        assert_ne!(
            contracts.medialane.get_order_hash(params1, accounts.offerer),
            contracts.medialane.get_order_hash(params2, accounts.offerer),
        );
    }

    // -------------------------------------------------------------------------
    // Unit tests — native token / order status default
    // -------------------------------------------------------------------------

    #[test]
    fn test_get_native_token() {
        let (contracts, _) = setup();
        assert_eq!(contracts.medialane.get_native_token_address(), contracts.erc20.contract_address);
    }

    #[test]
    fn test_unknown_order_returns_none_status() {
        let (contracts, _) = setup();
        let order = contracts.medialane.get_order_details(0x1234);
        assert_eq!(order.order_status, OrderStatus::None);
    }

    // -------------------------------------------------------------------------
    // Unit tests — ERC-2981 royalty mock
    // -------------------------------------------------------------------------

    #[test]
    fn test_mock_erc1155_royalty_zero_by_default() {
        let (contracts, _) = setup();
        let (_, amount) = contracts.erc1155.royalty_info(1_u256, 1000000_u256);
        assert_eq!(amount, 0_u256);
    }

    #[test]
    fn test_mock_erc1155_royalty_five_percent() {
        let (contracts, accounts) = setup();
        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, ROYALTY_FEE);

        let (receiver, amount) = contracts.erc1155.royalty_info(1_u256, 1000000_u256);
        assert_eq!(receiver, accounts.royalty_receiver);
        assert_eq!(amount, 50000_u256); // 5% of 1_000_000
    }

    #[test]
    fn test_mock_erc1155_royalty_eight_percent() {
        let (contracts, accounts) = setup();
        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, 800); // 8%

        let (_, amount) = contracts.erc1155.royalty_info(1_u256, 1000000_u256);
        assert_eq!(amount, 80000_u256); // 8% of 1_000_000
    }

    // -------------------------------------------------------------------------
    // Negative tests — register_order
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: "Offerer cannot be zero")]
    fn test_register_order_rejects_zero_offerer() {
        let (contracts, _) = setup();
        let mut params = default_order_params(
            0.try_into().unwrap(),
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Invalid amount")]
    fn test_register_order_rejects_zero_amount() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.offer.start_amount = 0;
        params.offer.end_amount = 0;
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Invalid amount")]
    fn test_register_order_rejects_zero_price() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.consideration.start_amount = 0;
        params.consideration.end_amount = 0;
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Token address cannot be zero")]
    fn test_register_order_rejects_zero_nft_contract() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, 0.try_into().unwrap(), contracts.erc20.contract_address,
        );
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Unsupported consideration item")]
    fn test_register_order_rejects_payment_for_payment_shape() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.offer.item_type = 'ERC20';
        params.offer.identifier_or_criteria = 0;
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Unsupported offer item")]
    fn test_register_order_rejects_unsupported_offer_item() {
        let (contracts, accounts) = setup();
        let mut params = default_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.offer.item_type = 'ERC721';
        params.offer.identifier_or_criteria = TOKEN_ID;
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Unsupported consideration item")]
    fn test_register_order_rejects_unsupported_consideration() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.consideration.item_type = 'ERC721';
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Recipient cannot be zero")]
    fn test_register_order_rejects_zero_recipient() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.consideration.recipient = 0.try_into().unwrap();
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Invalid identifier")]
    fn test_register_order_rejects_erc20_identifier() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.consideration.identifier_or_criteria = 1;
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Token address must be zero")]
    fn test_register_order_rejects_native_token_field_nonzero() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.consideration.item_type = 'NATIVE';
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Token address cannot be zero")]
    fn test_register_bid_rejects_zero_erc20_token() {
        let (contracts, accounts) = setup();
        let zero: ContractAddress = 0.try_into().unwrap();
        let params = default_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address, zero,
        );
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Token address must be zero")]
    fn test_register_native_bid_rejects_nonzero_token_field() {
        let (contracts, accounts) = setup();
        let mut params = default_native_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address,
        );
        params.offer.token = contracts.erc20.contract_address;
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Recipient cannot be zero")]
    fn test_register_bid_rejects_zero_asset_recipient() {
        let (contracts, accounts) = setup();
        let mut params = default_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.consideration.recipient = 0.try_into().unwrap();
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    #[test]
    #[should_panic(expected: "Order expired")]
    fn test_register_order_rejects_expired_end_time() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000003601);
        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Invalid time window")]
    fn test_register_order_rejects_start_after_end() {
        let (contracts, accounts) = setup();
        // start_time > end_time with non-zero end_time would create a stuck order.
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.start_time = 1000003600; // equal to end_time
        params.end_time = 1000000000;
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Order already created")]
    fn test_register_order_rejects_duplicate() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);
        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Invalid signature")]
    fn test_register_order_rejects_invalid_signature() {
        let (contracts, accounts) = setup();
        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        contracts.medialane.register_order(Order { parameters: params, signature: invalid_signature() });
    }

    // -------------------------------------------------------------------------
    // Negative tests — fulfill_order
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: "Caller not fulfiller")]
    fn test_fulfill_order_rejects_wrong_caller() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        // Caller is wrong_caller but fulfiller field claims accounts.fulfiller
        let wrong_caller: ContractAddress = 0xbad.try_into().unwrap();
        cheat_caller_address(
            contracts.medialane.contract_address, wrong_caller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash,
                fulfiller: accounts.fulfiller,
                quantity: TOKEN_AMOUNT,
                nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Order not found")]
    fn test_fulfill_non_existent_order() {
        let (contracts, accounts) = setup();
        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash: 0xdeadbeef,
                fulfiller: accounts.fulfiller,
                quantity: TOKEN_AMOUNT,
                nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Order already filled")]
    fn test_fulfill_order_rejects_double_fill() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        let fulfillment = OrderFulfillment {
            order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
        };

        // First fill — succeeds
        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment, signature: erc20_erc1155_fulfillment_signature(),
        });

        // Second fill — status check fires before signature/nonce → ORDER_ALREADY_FILLED
        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment, signature: erc20_erc1155_fulfillment_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Cannot fill own order")]
    fn test_fulfill_order_rejects_self_fill() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.offerer, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.offerer, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: invalid_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Quantity must be nonzero")]
    fn test_fulfill_order_rejects_zero_quantity() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: 0, nonce: 0,
            },
            signature: invalid_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Insufficient remaining units")]
    fn test_fulfill_order_rejects_overfill() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT + 1, nonce: 0,
            },
            signature: invalid_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Invalid signature")]
    fn test_fulfill_order_rejects_invalid_signature() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: invalid_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Order expired")]
    fn test_fulfill_order_rejects_expired() {
        let (contracts, accounts) = setup();

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000003601);
        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Order not yet valid")]
    fn test_fulfill_order_rejects_not_yet_valid() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 999999999);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });
    }

    // -------------------------------------------------------------------------
    // Negative tests — cancel_order
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: "Caller not offerer")]
    fn test_cancel_order_rejects_wrong_offerer() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        let wrong_offerer: ContractAddress = 0xbad.try_into().unwrap();
        contracts.medialane.cancel_order(CancelRequest {
            cancelation: OrderCancellation {
                order_hash, offerer: wrong_offerer, nonce: 0,
            },
            signature: erc20_erc1155_cancel_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Order not found")]
    fn test_cancel_non_existent_order() {
        let (contracts, accounts) = setup();
        contracts.medialane.cancel_order(CancelRequest {
            cancelation: OrderCancellation {
                order_hash: 0xdeadbeef, offerer: accounts.offerer, nonce: 0,
            },
            signature: erc20_erc1155_cancel_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Invalid signature")]
    fn test_cancel_order_rejects_invalid_signature() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        contracts.medialane.cancel_order(CancelRequest {
            cancelation: OrderCancellation {
                order_hash, offerer: accounts.offerer, nonce: 1,
            },
            signature: invalid_signature(),
        });
    }

    // -------------------------------------------------------------------------
    // Happy-path — full fill (no royalty)
    // -------------------------------------------------------------------------

    #[test]
    fn test_full_fill_no_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        // total = price_per_unit * amount = 1_000_000 * 10 = 10_000_000
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });

        // Offerer received full payment (no royalty)
        assert_eq!(contracts.erc20.get_balance(accounts.offerer), 10_000_000_u256);
        // Fulfiller holds the 10 ERC-1155 tokens
        let fulfiller_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.fulfiller, 1_u256,
        );
        assert_eq!(fulfiller_balance, 10_u256);
        // Order status = Filled, remaining = 0
        let details = contracts.medialane.get_order_details(order_hash);
        assert_eq!(details.order_status, OrderStatus::Filled);
        assert_eq!(details.remaining_amount, 0);
    }

    #[test]
    fn test_full_fill_native_consideration_no_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_native_order_params(accounts.offerer, contracts.erc1155.contract_address);
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: native_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: native_erc1155_fulfillment_signature(),
        });

        assert_eq!(contracts.erc20.get_balance(accounts.offerer), 10_000_000_u256);
        let fulfiller_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.fulfiller, 1_u256,
        );
        assert_eq!(fulfiller_balance, 10_u256);
        assert_eq!(
            contracts.medialane.get_order_details(order_hash).order_status, OrderStatus::Filled,
        );
    }

    // -------------------------------------------------------------------------
    // Happy-path — bid acceptance (ERC20 offer for ERC-1155)
    // -------------------------------------------------------------------------

    #[test]
    fn test_accept_erc20_bid_full_fill_no_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_for_erc1155_bid_order_signature(),
        });

        setup_bid_buyer_erc20(@contracts, @accounts, 10_000_000_u256);
        setup_bid_seller_erc1155(@contracts, @accounts);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_for_erc1155_bid_fulfillment_signature(),
        });

        assert_eq!(contracts.erc20.get_balance(accounts.fulfiller), 10_000_000_u256);
        let buyer_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.offerer, 1_u256,
        );
        assert_eq!(buyer_balance, 10_u256);
        let details = contracts.medialane.get_order_details(order_hash);
        assert_eq!(details.order_status, OrderStatus::Filled);
        assert_eq!(details.remaining_amount, 0);
    }

    #[test]
    fn test_accept_erc20_bid_partial_fill_no_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_for_erc1155_bid_order_signature(),
        });

        setup_bid_buyer_erc20(@contracts, @accounts, 5_000_000_u256);
        setup_bid_seller_erc1155(@contracts, @accounts);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: 5, nonce: 0,
            },
            signature: erc20_for_erc1155_bid_partial_fulfillment_signature(),
        });

        assert_eq!(contracts.erc20.get_balance(accounts.fulfiller), 5_000_000_u256);
        let buyer_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.offerer, 1_u256,
        );
        assert_eq!(buyer_balance, 5_u256);
        let details = contracts.medialane.get_order_details(order_hash);
        assert_eq!(details.order_status, OrderStatus::Created);
        assert_eq!(details.remaining_amount, 5);
    }

    #[test]
    fn test_accept_erc20_bid_with_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, ROYALTY_FEE);

        let params = default_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_for_erc1155_bid_order_signature(),
        });

        setup_bid_buyer_erc20(@contracts, @accounts, 10_000_000_u256);
        setup_bid_seller_erc1155(@contracts, @accounts);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_for_erc1155_bid_fulfillment_signature(),
        });

        assert_eq!(contracts.erc20.get_balance(accounts.royalty_receiver), 500_000_u256);
        assert_eq!(contracts.erc20.get_balance(accounts.fulfiller), 9_500_000_u256);
        let buyer_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.offerer, 1_u256,
        );
        assert_eq!(buyer_balance, 10_u256);
    }

    #[test]
    fn test_accept_native_bid_full_fill_no_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_native_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: native_for_erc1155_bid_order_signature(),
        });

        setup_bid_buyer_erc20(@contracts, @accounts, 10_000_000_u256);
        setup_bid_seller_erc1155(@contracts, @accounts);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: native_for_erc1155_bid_fulfillment_signature(),
        });

        assert_eq!(contracts.erc20.get_balance(accounts.fulfiller), 10_000_000_u256);
        let buyer_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.offerer, 1_u256,
        );
        assert_eq!(buyer_balance, 10_u256);
        assert_eq!(
            contracts.medialane.get_order_details(order_hash).order_status, OrderStatus::Filled,
        );
    }

    #[test]
    fn test_accept_native_bid_with_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, ROYALTY_FEE);

        let params = default_native_bid_order_params(
            accounts.offerer, contracts.erc1155.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: native_for_erc1155_bid_order_signature(),
        });

        setup_bid_buyer_erc20(@contracts, @accounts, 10_000_000_u256);
        setup_bid_seller_erc1155(@contracts, @accounts);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: native_for_erc1155_bid_fulfillment_signature(),
        });

        assert_eq!(contracts.erc20.get_balance(accounts.royalty_receiver), 500_000_u256);
        assert_eq!(contracts.erc20.get_balance(accounts.fulfiller), 9_500_000_u256);
        let buyer_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.offerer, 1_u256,
        );
        assert_eq!(buyer_balance, 10_u256);
    }

    // -------------------------------------------------------------------------
    // Happy-path — partial fill (5 of 10 units, no royalty)
    // -------------------------------------------------------------------------

    #[test]
    fn test_partial_fill_no_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        // Partial: only buying 5 units — 1_000_000 * 5 = 5_000_000
        setup_listing_buyer_erc20(@contracts, @accounts, 5_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: 5, nonce: 0,
            },
            signature: erc20_erc1155_partial_fulfillment_signature(),
        });

        // Offerer received payment for 5 units
        assert_eq!(contracts.erc20.get_balance(accounts.offerer), 5_000_000_u256);
        // Order still Created, 5 units remain
        let details = contracts.medialane.get_order_details(order_hash);
        assert_eq!(details.order_status, OrderStatus::Created);
        assert_eq!(details.remaining_amount, 5);
    }

    // -------------------------------------------------------------------------
    // Happy-path — full fill with 5% royalty
    // -------------------------------------------------------------------------

    #[test]
    fn test_full_fill_with_royalty() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        // Enable 5% royalty on the ERC-1155 contract
        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, ROYALTY_FEE);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        // total = 10_000_000; fulfiller must approve the full amount
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });

        // 5% royalty on 10_000_000 = 500_000
        assert_eq!(contracts.erc20.get_balance(accounts.royalty_receiver), 500_000_u256);
        // Offerer receives remainder: 10_000_000 - 500_000 = 9_500_000
        assert_eq!(contracts.erc20.get_balance(accounts.offerer), 9_500_000_u256);
        // Fulfiller holds the 10 ERC-1155 tokens
        let fulfiller_balance = erc1155_balance_of(
            contracts.erc1155.contract_address, accounts.fulfiller, 1_u256,
        );
        assert_eq!(fulfiller_balance, 10_u256);
        assert_eq!(
            contracts.medialane.get_order_details(order_hash).order_status, OrderStatus::Filled,
        );
    }

    #[test]
    fn test_full_fill_emits_royalty_event_fields() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let mut spy = spy_events();

        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, ROYALTY_FEE);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        setup_listing_seller_erc1155(@contracts, @accounts);
        setup_listing_buyer_erc20(@contracts, @accounts, 10_000_000_u256);

        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment: OrderFulfillment {
                order_hash, fulfiller: accounts.fulfiller, quantity: TOKEN_AMOUNT, nonce: 0,
            },
            signature: erc20_erc1155_fulfillment_signature(),
        });

        spy.assert_emitted(
            @array![
                (
                    contracts.medialane.contract_address,
                    Medialane1155V2::Event::OrderFulfilled(
                        OrderFulfilled {
                            order_hash,
                            offerer: accounts.offerer,
                            fulfiller: accounts.fulfiller,
                            quantity: TOKEN_AMOUNT,
                            remaining_amount: 0,
                            sale_amount: 10_000_000_u256,
                            royalty_receiver: accounts.royalty_receiver,
                            royalty_amount: 500_000_u256,
                        },
                    ),
                ),
            ],
        );
    }

    // -------------------------------------------------------------------------
    // Happy-path — register then cancel
    // -------------------------------------------------------------------------

    #[test]
    fn test_register_and_cancel() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        contracts.medialane.cancel_order(CancelRequest {
            cancelation: OrderCancellation {
                order_hash, offerer: accounts.offerer, nonce: 1,
            },
            signature: erc20_erc1155_cancel_signature(),
        });

        let details = contracts.medialane.get_order_details(order_hash);
        assert_eq!(details.order_status, OrderStatus::Cancelled);
    }

    #[test]
    #[should_panic(expected: "Order cancelled")]
    fn test_cancel_after_cancel_fails() {
        let (contracts, accounts) = setup();
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
        // First cancel: nonce 1 (registration consumed nonce 0)
        contracts.medialane.cancel_order(CancelRequest {
            cancelation: OrderCancellation {
                order_hash, offerer: accounts.offerer, nonce: 1,
            },
            signature: erc20_erc1155_cancel_signature(),
        });
        // Second cancel: status check fires before nonce check → "Order cancelled"
        contracts.medialane.cancel_order(CancelRequest {
            cancelation: OrderCancellation {
                order_hash, offerer: accounts.offerer, nonce: 2,
            },
            signature: erc20_erc1155_cancel_signature(),
        });
    }

    // -------------------------------------------------------------------------
    // Helpers — raw ERC-1155 balance check via dispatcher
    // -------------------------------------------------------------------------

    fn erc1155_balance_of(
        contract: ContractAddress, account: ContractAddress, token_id: u256,
    ) -> u256 {
        IERC1155Dispatcher { contract_address: contract }.balance_of(account, token_id)
    }
}
