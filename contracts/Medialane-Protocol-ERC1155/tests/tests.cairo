// NOTE: Signature arrays in these tests were computed with StarknetJS using the
// SNIP-12 domain { name: 'Medialane1155', version: 1 } and the type hashes defined
// in src/core/utils.cairo.  Run scripts/compute_signatures.mjs to regenerate them
// if the domain, type strings, or test account addresses change.
//
// snforge chain ID: 0x534e5f5345504f4c4941 (SN_SEPOLIA in ASCII)

#[cfg(test)]
mod test {
    use medialane_erc1155::core::interface::{IMedialane1155Dispatcher, IMedialane1155DispatcherTrait};
    use medialane_erc1155::core::types::*;
    use medialane_erc1155::core::events::*;
    use medialane_erc1155::mocks::erc1155::{IMockERC1155Dispatcher, IMockERC1155DispatcherTrait};
    use medialane_erc1155::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use openzeppelin_account::interface::AccountABIDispatcher;
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait,
        cheat_caller_address, declare, start_cheat_block_timestamp,
    };
    use starknet::ContractAddress;

    // -------------------------------------------------------------------------
    // Pre-computed SNIP-12 signatures (computed with scripts/compute_signatures.mjs)
    // Domain: { name: 'Medialane1155', version: 1, chainId: SN_SEPOLIA }
    // offerer  private key: 0x1a2b3c4d5e6f
    // fulfiller private key: 0xdeadbeef1234
    // -------------------------------------------------------------------------

    fn erc20_erc1155_order_signature() -> Array<felt252> {
        array![
            0xb9bd2f489bb7ee9c2b37e944fdb7de6f3e97a1ca3c678ce743eb0d7f86f013,
            0x645d166095bd318f9e6dbed73886f2e4fbd42018ea807316225142272944496,
        ]
    }

    // Full fill: quantity = 10, nonce = 0
    fn erc20_erc1155_fulfillment_signature() -> Array<felt252> {
        array![
            0x19c559e58bf68cc202bce6435bc16fffc2c21ef2d984b288d040ea99c0232c5,
            0x59eba0ecc274a9ecfbd9747025cc6ea9bf4cdac2340665cb49d946ee36b2bd4,
        ]
    }

    // Partial fill: quantity = 5, nonce = 0
    fn erc20_erc1155_partial_fulfillment_signature() -> Array<felt252> {
        array![
            0x10689a2879083dda31312e7cf009e76f08efca4fd47a4f4fe10376effbeaa2f,
            0xda48234b92512f7ebb33fc78095bda75ebb120b6f99138527149e8a8af9c48,
        ]
    }

    // nonce = 1: offerer nonce 0 is consumed by register_order, cancel uses nonce 1
    fn erc20_erc1155_cancel_signature() -> Array<felt252> {
        array![
            0x26239fcac0b80eb632dbe69a47121b8ca8b10936cac24a6be9453f240b1a99f,
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

    fn deploy_medialane(native_token: ContractAddress) -> IMedialane1155Dispatcher {
        let expected: ContractAddress =
            0x2a0626d1a71fab6c6cdcb262afc48bff92a6844700ebbd16297596e6c53da29
            .try_into()
            .unwrap();
        let mut calldata = array![];
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

    /// Mints TOKEN_AMOUNT ERC-1155 tokens to the offerer and approves Medialane.
    fn setup_offerer_erc1155(
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

    /// Mints `amount` ERC-20 tokens to the fulfiller and approves Medialane.
    fn setup_fulfiller_erc20(
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
        params2.token_id = 2;
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
        params2.amount = 5;
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
        let (contracts, accounts) = setup();
        assert_eq!(contracts.medialane.get_native_token(), contracts.erc20.contract_address);
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
    #[should_panic(expected: "Amount must be nonzero")]
    fn test_register_order_rejects_zero_amount() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.amount = 0;
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "Price must be nonzero")]
    fn test_register_order_rejects_zero_price() {
        let (contracts, accounts) = setup();
        let mut params = default_order_params(
            accounts.offerer, contracts.erc1155.contract_address, contracts.erc20.contract_address,
        );
        params.price_per_unit = 0;
        contracts.medialane.register_order(Order {
            parameters: params, signature: erc20_erc1155_order_signature(),
        });
    }

    #[test]
    #[should_panic(expected: "NFT contract cannot be zero")]
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
    #[should_panic(expected: "Start time must precede end time")]
    fn test_register_order_rejects_start_after_end() {
        let (contracts, accounts) = setup();
        // start_time > end_time with non-zero end_time — would create a stuck order
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

        setup_offerer_erc1155(@contracts, @accounts);
        setup_fulfiller_erc20(@contracts, @accounts, 10_000_000_u256);

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

        setup_offerer_erc1155(@contracts, @accounts);
        // total = price_per_unit * amount = 1_000_000 * 10 = 10_000_000
        setup_fulfiller_erc20(@contracts, @accounts, 10_000_000_u256);

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

        setup_offerer_erc1155(@contracts, @accounts);
        // Partial: only buying 5 units — 1_000_000 * 5 = 5_000_000
        setup_fulfiller_erc20(@contracts, @accounts, 5_000_000_u256);

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

        setup_offerer_erc1155(@contracts, @accounts);
        // total = 10_000_000; fulfiller must approve the full amount
        setup_fulfiller_erc20(@contracts, @accounts, 10_000_000_u256);

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
