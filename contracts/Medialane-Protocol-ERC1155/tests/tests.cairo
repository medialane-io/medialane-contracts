#[cfg(test)]
mod test {
    use medialane_marketplace_erc1155::core::interface::{
        IMedialane1155Dispatcher, IMedialane1155DispatcherTrait,
    };
    use medialane_marketplace_erc1155::core::types::*;
    use medialane_marketplace_erc1155::mocks::erc1155::{IMockERC1155Dispatcher, IMockERC1155DispatcherTrait};
    use medialane_marketplace_erc1155::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use medialane_marketplace_erc1155::mocks::malicious::{
        IMaliciousERC20Dispatcher, IMaliciousERC20DispatcherTrait,
    };
    use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use snforge_std::signature::KeyPairTrait;
    use snforge_std::signature::stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl};
    use snforge_std::{
        CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
        start_cheat_block_timestamp_global,
    };
    use starknet::ContractAddress;

    const OWNER: felt252 = 0x1001;
    const OFFERER_SK: felt252 = 0x111111;
    const FULFILLER_SK: felt252 = 0x222222;
    const TOKEN_ID: felt252 = 7;
    const UNITS: felt252 = 100; // ERC1155 quantity listed
    const PRICE: felt252 = 10000; // price per unit

    #[derive(Drop)]
    struct Env {
        medialane: IMedialane1155Dispatcher,
        erc20: IMockERC20Dispatcher,
        erc1155: IMockERC1155Dispatcher,
        offerer: ContractAddress,
        offerer_sk: felt252,
        fulfiller: ContractAddress,
        fulfiller_sk: felt252,
    }

    fn declare_and_deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
        let contract = declare(name).unwrap().contract_class();
        let (addr, _) = contract.deploy(@calldata).unwrap();
        addr
    }

    fn deploy_account(secret_key: felt252) -> ContractAddress {
        let kp = KeyPairTrait::<felt252, felt252>::from_secret_key(secret_key);
        declare_and_deploy("MockAccount", array![kp.public_key])
    }

    fn setup() -> Env {
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let offerer = deploy_account(OFFERER_SK);
        let fulfiller = deploy_account(FULFILLER_SK);
        let erc20 = IMockERC20Dispatcher {
            contract_address: declare_and_deploy("MockERC20", array![owner.into()]),
        };
        // MockERC1155 ctor: (owner). Royalty configured later via set_royalty.
        let erc1155 = IMockERC1155Dispatcher {
            contract_address: declare_and_deploy("MockERC1155", array![owner.into()]),
        };
        let medialane = IMedialane1155Dispatcher {
            contract_address: declare_and_deploy(
                "Medialane1155", array![erc20.contract_address.into()],
            ),
        };
        Env {
            medialane, erc20, erc1155, offerer, offerer_sk: OFFERER_SK, fulfiller,
            fulfiller_sk: FULFILLER_SK,
        }
    }

    /// A fixed-price ERC1155 listing: offer UNITS of the token, ask PRICE per unit.
    fn listing_params(env: @Env) -> OrderParameters {
        OrderParameters {
            offerer: *env.offerer,
            marketplace: *env.medialane.contract_address,
            offer: OfferItem {
                item_type: 'ERC1155',
                token: *env.erc1155.contract_address,
                identifier_or_criteria: TOKEN_ID,
                amount: UNITS,
            },
            consideration: ConsiderationItem {
                item_type: 'ERC20',
                token: *env.erc20.contract_address,
                identifier_or_criteria: 0,
                amount: PRICE,
                recipient: *env.offerer,
            },
            royalty_max_bps: 1000,
            start_time: 0,
            end_time: 0,
            salt: 1,
            counter: 0,
        }
    }

    /// A bid: offer ERC20 (price/unit), ask for UNITS of the ERC1155 (to the bidder).
    fn bid_params(env: @Env) -> OrderParameters {
        OrderParameters {
            offerer: *env.offerer,
            marketplace: *env.medialane.contract_address,
            offer: OfferItem {
                item_type: 'ERC20',
                token: *env.erc20.contract_address,
                identifier_or_criteria: 0,
                amount: PRICE,
            },
            consideration: ConsiderationItem {
                item_type: 'ERC1155',
                token: *env.erc1155.contract_address,
                identifier_or_criteria: TOKEN_ID,
                amount: UNITS,
                recipient: *env.offerer,
            },
            royalty_max_bps: 1000,
            start_time: 0,
            end_time: 0,
            salt: 1,
            counter: 0,
        }
    }

    fn signed_order(env: @Env, params: OrderParameters, signer_sk: felt252) -> Order {
        let hash = (*env.medialane).get_order_hash(params, params.offerer);
        let kp = KeyPairTrait::<felt252, felt252>::from_secret_key(signer_sk);
        let (r, s) = kp.sign(hash).unwrap();
        Order { parameters: params, signature: array![r, s] }
    }

    fn call_as(target: ContractAddress, caller: ContractAddress) {
        cheat_caller_address(target, caller, CheatSpan::TargetCalls(1));
    }

    #[test]
    fn test_register_listing_stores_created() {
        let env = setup();
        let params = listing_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        let details = env.medialane.get_order_details(hash);
        assert!(details.order_status == OrderStatus::Created, "should be Created");
        assert!(details.remaining_amount == UNITS, "remaining should equal listed units");
        assert!(details.consideration.amount == PRICE, "price/unit mismatch");
    }

    #[test]
    fn test_register_accepts_bid() {
        let env = setup();
        let params = bid_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        let details = env.medialane.get_order_details(hash);
        assert!(details.order_status == OrderStatus::Created, "bid should register");
        assert!(details.remaining_amount == UNITS, "remaining should equal wanted units");
    }

    #[test]
    fn test_register_allows_zero_price() {
        let env = setup();
        let mut params = listing_params(@env);
        params.consideration.amount = 0;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Created,
            "zero-price listing should register",
        );
    }

    #[test]
    #[should_panic(expected: 'Invalid signature')]
    fn test_register_rejects_invalid_signature() {
        let env = setup();
        let params = listing_params(@env);
        env.medialane.register_order(signed_order(@env, params, env.fulfiller_sk));
    }

    #[test]
    #[should_panic(expected: 'Wrong marketplace')]
    fn test_register_rejects_wrong_marketplace() {
        let env = setup();
        let mut params = listing_params(@env);
        params.marketplace = 0xdead.try_into().unwrap();
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Invalid counter')]
    fn test_register_rejects_stale_counter() {
        let env = setup();
        let mut params = listing_params(@env);
        params.counter = 5;
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Order already created')]
    fn test_register_rejects_duplicate() {
        let env = setup();
        let params = listing_params(@env);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Offerer cannot be zero')]
    fn test_register_rejects_zero_offerer() {
        let env = setup();
        let mut params = listing_params(@env);
        params.offerer = 0.try_into().unwrap();
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Unsupported trade shape')]
    fn test_register_rejects_nft_for_nft() {
        let env = setup();
        let mut params = listing_params(@env);
        params.consideration.item_type = 'ERC1155';
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Invalid amount')]
    fn test_register_rejects_zero_erc1155_amount() {
        let env = setup();
        let mut params = listing_params(@env);
        params.offer.amount = 0;
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Recipient cannot be zero')]
    fn test_register_rejects_zero_recipient() {
        let env = setup();
        let mut params = listing_params(@env);
        params.consideration.recipient = 0.try_into().unwrap();
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Token address must be zero')]
    fn test_register_rejects_native_with_token() {
        let env = setup();
        let mut params = listing_params(@env);
        params.consideration.item_type = 'NATIVE';
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Royalty bound too high')]
    fn test_register_rejects_royalty_bps_above_max() {
        // royalty_max_bps is a percentage in bps; > 10000 (100%) is nonsensical and
        // would overflow the cap math at fill. Reject it at registration.
        let env = setup();
        let mut params = listing_params(@env);
        params.royalty_max_bps = 10001;
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    fn test_register_allows_royalty_bps_at_max() {
        // The boundary value 10000 (100%) is valid.
        let env = setup();
        let mut params = listing_params(@env);
        params.royalty_max_bps = 10000;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Created,
            "bps == 10000 should register",
        );
    }

    #[test]
    #[should_panic(expected: 'Payment token is the NFT')]
    fn test_register_rejects_payment_token_equals_nft_listing() {
        // Listing whose ERC20 payment token IS the ERC1155 contract — an incoherent
        // trade (the payment transfer_from has no entrypoint on the 1155). Reject it.
        let env = setup();
        let mut params = listing_params(@env);
        params.consideration.token = params.offer.token; // payment token == ERC1155
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Payment token is the NFT')]
    fn test_register_rejects_payment_token_equals_nft_bid() {
        // Same collision in the bid direction (offer = payment, consideration = 1155).
        let env = setup();
        let mut params = bid_params(@env);
        params.offer.token = params.consideration.token; // payment token == ERC1155
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Order expired')]
    fn test_register_rejects_expired() {
        let env = setup();
        let mut params = listing_params(@env);
        params.end_time = 100;
        start_cheat_block_timestamp_global(200);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Invalid time window')]
    fn test_register_rejects_inverted_window() {
        let env = setup();
        let mut params = listing_params(@env);
        params.start_time = 200;
        params.end_time = 100;
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    // --- fulfilment (partial fills) ---

    fn erc1155(env: @Env) -> IERC1155Dispatcher {
        IERC1155Dispatcher { contract_address: *env.erc1155.contract_address }
    }

    /// Mint UNITS of the 1155 to the offerer + approve; fund the fulfiller's ERC20
    /// for a full fill (PRICE*UNITS) + approve. Register the listing; return hash.
    fn setup_fulfillable_listing(env: @Env) -> felt252 {
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let medialane = *env.medialane.contract_address;

        call_as(*env.erc1155.contract_address, owner);
        (*env.erc1155).mint(*env.offerer, TOKEN_ID.into(), UNITS.into(), array![].span());
        call_as(*env.erc1155.contract_address, *env.offerer);
        (*env.erc1155).approve(medialane, true);

        let total: u256 = (PRICE * UNITS).into();
        call_as(*env.erc20.contract_address, owner);
        (*env.erc20).mint_token(*env.fulfiller, total);
        call_as(*env.erc20.contract_address, *env.fulfiller);
        (*env.erc20).approve_token(medialane, total);

        let params = listing_params(env);
        let hash = (*env.medialane).get_order_hash(params, params.offerer);
        (*env.medialane).register_order(signed_order(env, params, *env.offerer_sk));
        hash
    }

    #[test]
    #[should_panic(expected: 'Invalid counter')]
    fn test_fulfill_rejects_after_counter_bump() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        // Offerer bulk-cancels by bumping their counter.
        call_as(env.medialane.contract_address, env.offerer);
        env.medialane.increment_counter();
        // The already-registered listing must no longer be fulfillable.
        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 1);
    }

    #[test]
    #[should_panic(expected: 'Invalid counter')]
    fn test_partial_fill_then_counter_bump_blocks_remainder() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        // Consume one unit; the multi-unit (UNITS) order stays Created.
        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 1);
        // Offerer bumps their counter; the remainder must now be blocked.
        call_as(env.medialane.contract_address, env.offerer);
        env.medialane.increment_counter();
        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 1);
    }

    #[test]
    #[should_panic(expected: 'Cannot fill own order')]
    fn test_fulfill_rejects_self_fill() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        call_as(env.medialane.contract_address, env.offerer);
        env.medialane.fulfill_order(hash, UNITS);
    }

    #[test]
    #[should_panic(expected: 'Quantity must be nonzero')]
    fn test_fulfill_rejects_zero_quantity() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 0);
    }

    #[test]
    #[should_panic(expected: 'Insufficient remaining units')]
    fn test_fulfill_rejects_overfill() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS + 1);
    }

    #[test]
    fn test_fulfill_full_no_royalty() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);

        assert!(
            erc1155(@env).balance_of(env.fulfiller, TOKEN_ID.into()) == UNITS.into(),
            "buyer should hold all units",
        );
        assert!(
            env.erc20.get_balance(env.offerer) == (PRICE * UNITS).into(), "seller paid in full",
        );
        let details = env.medialane.get_order_details(hash);
        assert!(details.order_status == OrderStatus::Filled, "should be Filled");
        assert!(details.remaining_amount == 0, "remaining should be 0");
    }

    #[test]
    fn test_fulfill_partial_keeps_open() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 40);

        assert!(
            erc1155(@env).balance_of(env.fulfiller, TOKEN_ID.into()) == 40_u256,
            "buyer holds 40 units",
        );
        assert!(env.erc20.get_balance(env.offerer) == (PRICE * 40).into(), "seller paid for 40");
        let details = env.medialane.get_order_details(hash);
        assert!(details.order_status == OrderStatus::Created, "should stay Created");
        assert!(details.remaining_amount == UNITS - 40, "remaining should be 60");
    }

    const ROYALTY_RECEIVER: felt252 = 0x5005;

    #[test]
    fn test_fulfill_pays_royalty() {
        // 5% royalty, 10% cap → full 5% paid to the creator.
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();
        call_as(env.erc1155.contract_address, owner);
        env.erc1155.set_royalty(receiver, 500);

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);

        let sale: u256 = (PRICE * UNITS).into();
        let royalty: u256 = sale * 500 / 10000;
        assert!(env.erc20.get_balance(receiver) == royalty, "creator royalty mismatch");
        assert!(env.erc20.get_balance(env.offerer) == sale - royalty, "seller net mismatch");
    }

    #[test]
    fn test_fulfill_caps_royalty_at_signed_bound() {
        // 50% NFT royalty, but the seller signed a 10% cap → only 10% paid.
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();
        call_as(env.erc1155.contract_address, owner);
        env.erc1155.set_royalty(receiver, 5000);

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);

        let sale: u256 = (PRICE * UNITS).into();
        let capped: u256 = sale * 1000 / 10000; // 10%
        assert!(env.erc20.get_balance(receiver) == capped, "royalty should be capped");
        assert!(env.erc20.get_balance(env.offerer) == sale - capped, "seller net mismatch");
    }

    #[test]
    fn test_fulfill_bid() {
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let medialane = env.medialane.contract_address;

        // Seller (fulfiller) holds the units + approves.
        call_as(env.erc1155.contract_address, owner);
        env.erc1155.mint(env.fulfiller, TOKEN_ID.into(), UNITS.into(), array![].span());
        call_as(env.erc1155.contract_address, env.fulfiller);
        env.erc1155.approve(medialane, true);

        // Bidder (offerer) funds + approves the ERC20 for a full fill.
        let total: u256 = (PRICE * UNITS).into();
        call_as(env.erc20.contract_address, owner);
        env.erc20.mint_token(env.offerer, total);
        call_as(env.erc20.contract_address, env.offerer);
        env.erc20.approve_token(medialane, total);

        let params = bid_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);

        assert!(
            erc1155(@env).balance_of(env.offerer, TOKEN_ID.into()) == UNITS.into(),
            "bidder should receive units",
        );
        assert!(env.erc20.get_balance(env.fulfiller) == total, "seller should be paid");
    }

    // --- cancellation + bulk-cancel counter ---

    fn signed_cancel(env: @Env, order_hash: felt252, signer_sk: felt252) -> CancelRequest {
        let cancellation = OrderCancellation { order_hash, offerer: *env.offerer };
        let hash = (*env.medialane).get_cancellation_hash(cancellation, *env.offerer);
        let kp = KeyPairTrait::<felt252, felt252>::from_secret_key(signer_sk);
        let (r, s) = kp.sign(hash).unwrap();
        CancelRequest { cancelation: cancellation, signature: array![r, s] }
    }

    #[test]
    fn test_cancel_marks_cancelled() {
        let env = setup();
        let params = listing_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        env.medialane.cancel_order(signed_cancel(@env, hash, env.offerer_sk));

        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Cancelled,
            "should be Cancelled",
        );
    }

    #[test]
    #[should_panic(expected: 'Invalid signature')]
    fn test_cancel_rejects_wrong_signer() {
        let env = setup();
        let params = listing_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        env.medialane.cancel_order(signed_cancel(@env, hash, env.fulfiller_sk));
    }

    #[test]
    fn test_increment_counter() {
        let env = setup();
        call_as(env.medialane.contract_address, env.offerer);
        env.medialane.increment_counter();
        assert!(env.medialane.get_counter(env.offerer) == 1, "counter should be 1");
    }

    #[test]
    #[should_panic(expected: 'Invalid counter')]
    fn test_order_under_old_counter_rejected_after_bump() {
        let env = setup();
        call_as(env.medialane.contract_address, env.offerer);
        env.medialane.increment_counter();
        let params = listing_params(@env); // counter 0, now stale
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Reentrant call')]
    fn test_fulfill_reentrancy_blocked() {
        // A listing whose payment token reenters fulfill_order during settlement.
        // The guard must abort the reentrant call.
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let medialane = env.medialane.contract_address;

        let malicious = IMaliciousERC20Dispatcher {
            contract_address: declare_and_deploy("MaliciousERC20", array![]),
        };

        // Offerer owns + approves the units (shape/registration are valid).
        call_as(env.erc1155.contract_address, owner);
        env.erc1155.mint(env.offerer, TOKEN_ID.into(), UNITS.into(), array![].span());
        call_as(env.erc1155.contract_address, env.offerer);
        env.erc1155.approve(medialane, true);

        // Consideration token = the malicious reentrant ERC20.
        let mut params = listing_params(@env);
        params.consideration.token = malicious.contract_address;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        malicious.set_attack(medialane, hash, UNITS);

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS); // _pay -> malicious.transfer_from -> reenter
    }

    #[test]
    fn test_fulfill_multi_step_partial() {
        // Two sequential partial fills by the same buyer accumulate correctly.
        let env = setup();
        let hash = setup_fulfillable_listing(@env);

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 40);
        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash, 35);

        assert!(
            erc1155(@env).balance_of(env.fulfiller, TOKEN_ID.into()) == 75_u256,
            "buyer should hold 75 units",
        );
        assert!(env.erc20.get_balance(env.offerer) == (PRICE * 75).into(), "seller paid for 75");
        let details = env.medialane.get_order_details(hash);
        assert!(details.order_status == OrderStatus::Created, "still open");
        assert!(details.remaining_amount == UNITS - 75, "remaining should be 25");
    }

    #[test]
    fn test_fulfill_bid_pays_royalty() {
        // Royalty paid on the bid direction (consideration ERC1155 carries 2981).
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();
        let medialane = env.medialane.contract_address;

        call_as(env.erc1155.contract_address, owner);
        env.erc1155.set_royalty(receiver, 500); // 5%
        call_as(env.erc1155.contract_address, owner);
        env.erc1155.mint(env.fulfiller, TOKEN_ID.into(), UNITS.into(), array![].span());
        call_as(env.erc1155.contract_address, env.fulfiller);
        env.erc1155.approve(medialane, true);

        let total: u256 = (PRICE * UNITS).into();
        call_as(env.erc20.contract_address, owner);
        env.erc20.mint_token(env.offerer, total);
        call_as(env.erc20.contract_address, env.offerer);
        env.erc20.approve_token(medialane, total);

        let params = bid_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);

        let royalty: u256 = total * 500 / 10000;
        assert!(env.erc20.get_balance(receiver) == royalty, "creator royalty on bid");
        assert!(env.erc20.get_balance(env.fulfiller) == total - royalty, "seller net");
    }

    #[test]
    fn test_fulfill_zero_price() {
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let medialane = env.medialane.contract_address;
        call_as(env.erc1155.contract_address, owner);
        env.erc1155.mint(env.offerer, TOKEN_ID.into(), UNITS.into(), array![].span());
        call_as(env.erc1155.contract_address, env.offerer);
        env.erc1155.approve(medialane, true);

        let mut params = listing_params(@env);
        params.consideration.amount = 0;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);

        assert!(
            erc1155(@env).balance_of(env.fulfiller, TOKEN_ID.into()) == UNITS.into(),
            "free transfer of units",
        );
        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Filled, "Filled",
        );
    }

    #[test]
    #[should_panic]
    fn test_fulfill_phantom_order_reverts() {
        // Offerer never minted/approved the units → fulfilment reverts at delivery.
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let medialane = env.medialane.contract_address;
        let total: u256 = (PRICE * UNITS).into();
        call_as(env.erc20.contract_address, owner);
        env.erc20.mint_token(env.fulfiller, total);
        call_as(env.erc20.contract_address, env.fulfiller);
        env.erc20.approve_token(medialane, total);

        let params = listing_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash, UNITS);
    }
}
