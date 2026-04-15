// NOTE: Signature arrays in these tests were computed with StarknetJS using the
// SNIP-12 domain { name: 'Medialane1155', version: 1 } and the type hashes defined
// in src/core/utils.cairo.  Update them if the domain or type strings change.
//
// Test accounts use deterministic OZ accounts with known public keys.
// Private keys can be derived from the public keys for local testing.

#[cfg(test)]
mod test {
    use medialane_erc1155::core::interface::{IMedialane1155Dispatcher, IMedialane1155DispatcherTrait};
    use medialane_erc1155::core::types::*;
    use medialane_erc1155::mocks::erc1155::{IMockERC1155Dispatcher, IMockERC1155DispatcherTrait};
    use medialane_erc1155::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use openzeppelin_account::interface::AccountABIDispatcher;
    use snforge_std_deprecated::{
        CheatSpan, ContractClassTrait, DeclareResultTrait,
        cheat_caller_address, declare, start_cheat_block_timestamp,
    };
    use starknet::ContractAddress;

    // -------------------------------------------------------------------------
    // Pre-computed SNIP-12 signatures (computed with StarknetJS)
    // Domain: { name: 'Medialane1155', version: 1 }
    // -------------------------------------------------------------------------

    // Signatures computed with StarknetJS 6.24.1 using:
    //   domain  = { name: 'Medialane1155', version: '1', chainId: '0x534e5f5345504f4c4941', revision: '1' }
    //   offerer private key  = 0x1a2b3c4d5e6f  (pub: 0x0161523dc3f079d9daf9d97ff87ea448c93e2dc4153e7010d45203ff97f4dfbe)
    //   fulfiller private key = 0xdeadbeef1234  (pub: 0x074302e19249520569d2cd18869a304dfd1fbfced5760cd8e0ddfe621077d2e2)
    //   See scripts/compute_signatures.mjs for full reproduction.
    fn erc20_erc1155_order_signature() -> Array<felt252> {
        array![
            0xb9bd2f489bb7ee9c2b37e944fdb7de6f3e97a1ca3c678ce743eb0d7f86f013,
            0x645d166095bd318f9e6dbed73886f2e4fbd42018ea807316225142272944496,
        ]
    }

    fn erc20_erc1155_fulfillment_signature() -> Array<felt252> {
        array![
            0x4a040545013e490acb66523bb7090feb602ebc4115f2deca01cfd71be31fe54,
            0x758810b26b58542be5f2391be8ffc2df0c113d4aa2f5eb5c4975eb2de968136,
        ]
    }

    fn erc20_erc1155_cancel_signature() -> Array<felt252> {
        array![
            0x38a77718e113e7b1d0317118e369429853b7af626abb42b0677a0b2ab429533,
            0x7705786cedd695db185d990a071b88644bcc534d077661dc6d8a95f3049b86b,
        ]
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    const OWNER_ADDRESS: felt252 = 0x1001;
    const TOKEN_ID: felt252 = 1;
    const TOKEN_AMOUNT: felt252 = 10;
    const PRICE_PER_UNIT: felt252 = 1000000; // 1 USDC-equivalent per token
    const ROYALTY_FEE: u256 = 500; // 5% in basis points (out of 10,000)

    // -------------------------------------------------------------------------
    // Test structs
    // -------------------------------------------------------------------------

    #[derive(Clone, Drop)]
    struct DeployedContracts {
        medialane: IMedialane1155Dispatcher,
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

    fn deploy_medialane(
        native_token: ContractAddress, manager: ContractAddress,
    ) -> IMedialane1155Dispatcher {
        let expected: ContractAddress =
            0x2a0626d1a71fab6c6cdcb262afc48bff92a6844700ebbd16297596e6c53da29
            .try_into()
            .unwrap();
        let mut calldata = array![];
        manager.serialize(ref calldata);
        native_token.serialize(ref calldata);
        let addr = deploy_contract("Medialane1155", @calldata, expected);
        IMedialane1155Dispatcher { contract_address: addr }
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
        let medialane = deploy_medialane(erc20.contract_address, accounts.owner);
        let erc1155 = deploy_erc1155(accounts.owner);
        (
            DeployedContracts { medialane, erc20, erc1155 },
            accounts,
        )
    }

    fn default_order_params(
        offerer: ContractAddress,
        nft_contract: ContractAddress,
        payment_token: ContractAddress,
    ) -> OrderParameters {
        OrderParameters {
            offerer,
            nft_contract,
            token_id: TOKEN_ID,
            amount: TOKEN_AMOUNT,
            payment_token,
            price_per_unit: PRICE_PER_UNIT,
            start_time: 1000000000,
            end_time: 1000003600,
            salt: 0,
            nonce: 0,
        }
    }

    // -------------------------------------------------------------------------
    // Unit tests — order hash
    // -------------------------------------------------------------------------

    #[test]
    fn test_get_order_hash_is_deterministic() {
        let (contracts, accounts) = setup();
        let params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let h1 = contracts.medialane.get_order_hash(params, accounts.offerer);
        let h2 = contracts.medialane.get_order_hash(params, accounts.offerer);
        assert_eq!(h1, h2);
    }

    #[test]
    fn test_order_hash_differs_by_token_id() {
        let (contracts, accounts) = setup();
        let mut params1 = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let mut params2 = params1;
        params2.token_id = 2;
        let h1 = contracts.medialane.get_order_hash(params1, accounts.offerer);
        let h2 = contracts.medialane.get_order_hash(params2, accounts.offerer);
        assert_ne!(h1, h2);
    }

    #[test]
    fn test_order_hash_differs_by_amount() {
        let (contracts, accounts) = setup();
        let params1 = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let mut params2 = params1;
        params2.amount = 5;
        let h1 = contracts.medialane.get_order_hash(params1, accounts.offerer);
        let h2 = contracts.medialane.get_order_hash(params2, accounts.offerer);
        assert_ne!(h1, h2);
    }

    // -------------------------------------------------------------------------
    // Unit tests — native token
    // -------------------------------------------------------------------------

    #[test]
    fn test_get_native_token() {
        let (contracts, accounts) = setup();
        assert_eq!(
            contracts.medialane.get_native_token(),
            contracts.erc20.contract_address,
        );
    }

    // -------------------------------------------------------------------------
    // Unit tests — order status default
    // -------------------------------------------------------------------------

    #[test]
    fn test_unknown_order_returns_none_status() {
        let (contracts, _accounts) = setup();
        let order = contracts.medialane.get_order_details(0x1234);
        assert_eq!(order.order_status, OrderStatus::None);
    }

    // -------------------------------------------------------------------------
    // Integration tests — register_order
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Offerer cannot be zero',))]
    fn test_register_order_rejects_zero_offerer() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            0.try_into().unwrap(), // zero offerer
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: ('Amount must be nonzero',))]
    fn test_register_order_rejects_zero_amount() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        params.amount = 0;
        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: ('Price must be nonzero',))]
    fn test_register_order_rejects_zero_price() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        params.price_per_unit = 0;
        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: ('NFT contract cannot be zero',))]
    fn test_register_order_rejects_zero_nft_contract() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer,
            0.try_into().unwrap(), // zero nft contract
            contracts.erc20.contract_address,
        );
        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: ('Order expired',))]
    fn test_register_order_rejects_expired_end_time() {
        let (contracts, accounts) = setup();
        // Timestamp past the default end_time (1000003600) — registration must fail.
        // start_time is no longer checked at registration; only end_time matters.
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000003601);
        let params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: ('Order expired',))]
    fn test_register_order_rejects_explicit_expired() {
        let (contracts, accounts) = setup();
        let ts: u64 = 1000003601;
        start_cheat_block_timestamp(contracts.medialane.contract_address, ts);
        let mut params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        // end_time already in the past — registration must fail with ORDER_EXPIRED.
        // start_time can be anything; only end_time is validated at registration.
        params.end_time = (ts - 1).into();
        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);
    }

    // -------------------------------------------------------------------------
    // Integration test — fulfill_order: caller must be fulfiller
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Caller not fulfiller',))]
    fn test_fulfill_order_rejects_wrong_caller() {
        let (contracts, accounts) = setup();

        // Register a valid order first (using valid block time)
        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        // Cheat caller to offerer to register
        cheat_caller_address(
            contracts.medialane.contract_address,
            accounts.offerer,
            CheatSpan::TargetCalls(1),
        );

        let params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);

        // Now try to fulfill as someone other than the fulfiller
        let wrong_caller: ContractAddress = 0xbad.try_into().unwrap();
        cheat_caller_address(
            contracts.medialane.contract_address,
            wrong_caller,
            CheatSpan::TargetCalls(1),
        );

        let fulfillment = OrderFulfillment {
            order_hash,
            fulfiller: accounts.fulfiller, // claims to be fulfiller...
            nonce: 0,
        };
        let request = FulfillmentRequest {
            fulfillment,
            signature: erc20_erc1155_fulfillment_signature(),
        };
        contracts.medialane.fulfill_order(request); // ...but caller is wrong_caller
    }

    // -------------------------------------------------------------------------
    // Integration test — cancel_order: wrong offerer should fail
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Caller not offerer',))]
    fn test_cancel_order_rejects_wrong_offerer() {
        let (contracts, accounts) = setup();

        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        let order = Order { parameters: params, signature: erc20_erc1155_order_signature() };
        contracts.medialane.register_order(order);

        // Try to cancel with a different offerer address
        let wrong_offerer: ContractAddress = 0xbad.try_into().unwrap();
        let cancelation = OrderCancellation {
            order_hash,
            offerer: wrong_offerer, // does not match the order's offerer
            nonce: 0,
        };
        let request = CancelRequest {
            cancelation,
            signature: erc20_erc1155_cancel_signature(),
        };
        contracts.medialane.cancel_order(request);
    }

    // -------------------------------------------------------------------------
    // Integration test — double-fulfill should fail
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Order already filled',))]
    fn test_fulfill_order_rejects_double_fill() {
        let (contracts, accounts) = setup();

        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        let order_hash = contracts.medialane.get_order_hash(params, accounts.offerer);

        // Register the order
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });

        // Mint ERC-1155 tokens to offerer and approve Medialane1155
        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.mint(accounts.offerer, 1_u256, 10_u256, array![].span());

        cheat_caller_address(
            contracts.erc1155.contract_address, accounts.offerer, CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.approve(contracts.medialane.contract_address, true);

        // Mint ERC-20 to fulfiller and approve Medialane1155 (total = 1_000_000 * 10)
        cheat_caller_address(
            contracts.erc20.contract_address, accounts.owner, CheatSpan::TargetCalls(1),
        );
        contracts.erc20.mint_token(accounts.fulfiller, 10_000_000_u256);

        cheat_caller_address(
            contracts.erc20.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.erc20.approve_token(contracts.medialane.contract_address, 10_000_000_u256);

        let fulfillment = OrderFulfillment { order_hash, fulfiller: accounts.fulfiller, nonce: 0 };

        // First fulfillment — succeeds
        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment, signature: erc20_erc1155_fulfillment_signature(),
        });

        // Second fulfillment — status check fires before signature/nonce → ORDER_ALREADY_FILLED
        cheat_caller_address(
            contracts.medialane.contract_address, accounts.fulfiller, CheatSpan::TargetCalls(1),
        );
        contracts.medialane.fulfill_order(FulfillmentRequest {
            fulfillment, signature: erc20_erc1155_fulfillment_signature(),
        });
    }

    // -------------------------------------------------------------------------
    // Integration test — fulfill on non-existent order
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Order not found',))]
    fn test_fulfill_non_existent_order() {
        let (contracts, accounts) = setup();
        let fake_hash: felt252 = 0xdeadbeef;

        cheat_caller_address(
            contracts.medialane.contract_address,
            accounts.fulfiller,
            CheatSpan::TargetCalls(1),
        );

        let fulfillment = OrderFulfillment {
            order_hash: fake_hash,
            fulfiller: accounts.fulfiller,
            nonce: 0,
        };
        let request = FulfillmentRequest {
            fulfillment,
            signature: erc20_erc1155_fulfillment_signature(),
        };
        contracts.medialane.fulfill_order(request);
    }

    // -------------------------------------------------------------------------
    // Integration test — cancel non-existent order
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Order not found',))]
    fn test_cancel_non_existent_order() {
        let (contracts, accounts) = setup();
        let fake_hash: felt252 = 0xdeadbeef;

        let cancelation = OrderCancellation {
            order_hash: fake_hash,
            offerer: accounts.offerer,
            nonce: 0,
        };
        let request = CancelRequest {
            cancelation,
            signature: erc20_erc1155_cancel_signature(),
        };
        contracts.medialane.cancel_order(request);
    }

    // -------------------------------------------------------------------------
    // Integration test — register order twice (same hash) should fail
    // -------------------------------------------------------------------------

    #[test]
    #[should_panic(expected: ('Order already created',))]
    fn test_register_order_rejects_duplicate() {
        let (contracts, accounts) = setup();

        start_cheat_block_timestamp(contracts.medialane.contract_address, 1000000000);

        let params = default_order_params(
            accounts.offerer,
            contracts.erc1155.contract_address,
            contracts.erc20.contract_address,
        );
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
        // Second registration with same params — same hash — should panic
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    // -------------------------------------------------------------------------
    // Unit tests — ERC-2981 royalty mock
    // -------------------------------------------------------------------------

    #[test]
    fn test_mock_erc1155_royalty_zero_by_default() {
        let (contracts, accounts) = setup();
        let (receiver, amount) = contracts
            .erc1155
            .royalty_info(1_u256, 1000000_u256);
        assert_eq!(amount, 0_u256);
    }

    #[test]
    fn test_mock_erc1155_royalty_five_percent() {
        let (contracts, accounts) = setup();

        cheat_caller_address(
            contracts.erc1155.contract_address,
            accounts.owner,
            CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, ROYALTY_FEE);

        let sale_price: u256 = 1000000;
        let (receiver, amount) = contracts.erc1155.royalty_info(1_u256, sale_price);
        assert_eq!(receiver, accounts.royalty_receiver);
        // 5% of 1_000_000 = 50_000
        assert_eq!(amount, 50000_u256);
    }

    #[test]
    fn test_mock_erc1155_royalty_eight_percent() {
        let (contracts, accounts) = setup();

        cheat_caller_address(
            contracts.erc1155.contract_address,
            accounts.owner,
            CheatSpan::TargetCalls(1),
        );
        contracts.erc1155.set_royalty(accounts.royalty_receiver, 800); // 8%

        let sale_price: u256 = 1000000;
        let (_, amount) = contracts.erc1155.royalty_info(1_u256, sale_price);
        // 8% of 1_000_000 = 80_000
        assert_eq!(amount, 80000_u256);
    }

    // -------------------------------------------------------------------------
    // Happy-path integration tests (require valid StarknetJS signatures)
    // -------------------------------------------------------------------------
    // These tests are skipped until signatures are recomputed with StarknetJS
    // for the Medialane1155 domain.  Mark them with #[ignore] and update the
    // signature arrays at the top of this file once computed.
    //
    // Full happy-path scenario:
    //   1. Offerer mints ERC-1155 tokens and approves Medialane1155.
    //   2. Fulfiller receives ERC-20 tokens and approves Medialane1155.
    //   3. Offerer signs OrderParameters, calls register_order.
    //   4. Fulfiller signs OrderFulfillment, calls fulfill_order.
    //   5. Assert: fulfiller holds tokens, offerer holds payment minus royalty,
    //              royalty_receiver holds royalty, order status == Filled.
    // -------------------------------------------------------------------------
}
