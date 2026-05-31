#[cfg(test)]
mod test {
    use medialane_protocol::core::interface::{IMedialaneDispatcher, IMedialaneDispatcherTrait};
    use medialane_protocol::core::types::*;
    use medialane_protocol::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use medialane_protocol::mocks::erc721::{IMockERC721Dispatcher, IMockERC721DispatcherTrait};
    use medialane_protocol::mocks::erc721_royalty::{
        IMockERC721RoyaltyDispatcher, IMockERC721RoyaltyDispatcherTrait,
    };
    use medialane_protocol::mocks::malicious::{
        IMaliciousERC20Dispatcher, IMaliciousERC20DispatcherTrait,
    };
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
    const PRICE: felt252 = 1000000;

    #[derive(Drop)]
    struct Env {
        medialane: IMedialaneDispatcher,
        erc20: IMockERC20Dispatcher,
        erc721: IMockERC721Dispatcher,
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
        let erc721 = IMockERC721Dispatcher {
            contract_address: declare_and_deploy("MockERC721", array![owner.into()]),
        };
        let medialane = IMedialaneDispatcher {
            contract_address: declare_and_deploy(
                "Medialane721", array![erc20.contract_address.into()],
            ),
        };

        Env {
            medialane,
            erc20,
            erc721,
            offerer,
            offerer_sk: OFFERER_SK,
            fulfiller,
            fulfiller_sk: FULFILLER_SK,
        }
    }

    /// A fixed-price ERC721 listing: offer the NFT, ask for ERC20 `PRICE`.
    fn listing_params(env: @Env) -> OrderParameters {
        OrderParameters {
            offerer: *env.offerer,
            marketplace: *env.medialane.contract_address,
            offer: OfferItem {
                item_type: 'ERC721',
                token: *env.erc721.contract_address,
                identifier_or_criteria: TOKEN_ID,
                amount: 1,
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

    /// A bid: offer ERC20 `PRICE`, ask for the NFT (delivered to the bidder).
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
                item_type: 'ERC721',
                token: *env.erc721.contract_address,
                identifier_or_criteria: TOKEN_ID,
                amount: 1,
                recipient: *env.offerer,
            },
            royalty_max_bps: 1000,
            start_time: 0,
            end_time: 0,
            salt: 1,
            counter: 0,
        }
    }

    /// Sign a set of order parameters as `signer_sk` and wrap into an `Order`.
    fn signed_order(env: @Env, params: OrderParameters, signer_sk: felt252) -> Order {
        let hash = (*env.medialane).get_order_hash(params, params.offerer);
        let kp = KeyPairTrait::<felt252, felt252>::from_secret_key(signer_sk);
        let (r, s) = kp.sign(hash).unwrap();
        Order { parameters: params, signature: array![r, s] }
    }

    fn call_as(target: ContractAddress, caller: ContractAddress) {
        cheat_caller_address(target, caller, CheatSpan::TargetCalls(1));
    }

    /// Mint the NFT to the offerer + approve the marketplace, fund + approve the
    /// fulfiller's ERC20, register the listing, and return its hash.
    fn setup_fulfillable_listing(env: @Env) -> felt252 {
        let medialane = *env.medialane.contract_address;
        let erc721 = *env.erc721;
        let erc20 = *env.erc20;

        call_as(erc721.contract_address, OWNER.try_into().unwrap());
        erc721.mint_token(*env.offerer, TOKEN_ID.into());
        call_as(erc721.contract_address, *env.offerer);
        erc721.approve_token(medialane, TOKEN_ID.into());

        call_as(erc20.contract_address, OWNER.try_into().unwrap());
        erc20.mint_token(*env.fulfiller, PRICE.into());
        call_as(erc20.contract_address, *env.fulfiller);
        erc20.approve_token(medialane, PRICE.into());

        let params = listing_params(env);
        let hash = (*env.medialane).get_order_hash(params, params.offerer);
        (*env.medialane).register_order(signed_order(env, params, *env.offerer_sk));
        hash
    }

    #[test]
    #[should_panic(expected: 'Cannot fill own order')]
    fn test_fulfill_rejects_self_fill() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);
        call_as(env.medialane.contract_address, env.offerer);
        env.medialane.fulfill_order(hash);
    }

    const ROYALTY_RECEIVER: felt252 = 0x5005;

    /// Deploy a 2981 NFT (`bps` royalty), list it, fund + approve the buyer.
    /// Returns the order hash. `royalty_max_bps` on the order is fixed at 1000 (10%).
    fn setup_royalty_listing(env: @Env, bps: u128) -> felt252 {
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();
        let roy = IMockERC721RoyaltyDispatcher {
            contract_address: declare_and_deploy(
                "MockERC721Royalty", array![owner.into(), receiver.into(), bps.into()],
            ),
        };
        call_as(roy.contract_address, owner);
        roy.mint_token(*env.offerer, TOKEN_ID.into());
        call_as(roy.contract_address, *env.offerer);
        roy.approve_token(*env.medialane.contract_address, TOKEN_ID.into());

        let erc20 = *env.erc20;
        call_as(erc20.contract_address, owner);
        erc20.mint_token(*env.fulfiller, PRICE.into());
        call_as(erc20.contract_address, *env.fulfiller);
        erc20.approve_token(*env.medialane.contract_address, PRICE.into());

        let mut params = listing_params(env);
        params.offer.token = roy.contract_address;
        let hash = (*env.medialane).get_order_hash(params, params.offerer);
        (*env.medialane).register_order(signed_order(env, params, *env.offerer_sk));
        hash
    }

    #[test]
    fn test_fulfill_pays_royalty() {
        // NFT royalty 5%, order cap 10% → full 5% paid to the creator.
        let env = setup();
        let hash = setup_royalty_listing(@env, 500);
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash);

        let royalty: u256 = 50000; // 5% of 1_000_000
        assert!(env.erc20.get_balance(receiver) == royalty, "creator royalty mismatch");
        assert!(env.erc20.get_balance(env.offerer) == PRICE.into() - royalty, "seller net mismatch");
    }

    #[test]
    fn test_fulfill_caps_royalty_at_signed_bound() {
        // NFT royalty 50%, but the seller signed a 10% cap → only 10% paid (F8).
        let env = setup();
        let hash = setup_royalty_listing(@env, 5000);
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash);

        let capped: u256 = 100000; // 10% of 1_000_000
        assert!(env.erc20.get_balance(receiver) == capped, "royalty should be capped");
        assert!(env.erc20.get_balance(env.offerer) == PRICE.into() - capped, "seller net mismatch");
    }

    #[test]
    fn test_fulfill_listing_no_royalty() {
        let env = setup();
        let hash = setup_fulfillable_listing(@env);

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash);

        assert!(env.erc721.get_owner(TOKEN_ID.into()) == env.fulfiller, "NFT should move to buyer");
        assert!(env.erc20.get_balance(env.offerer) == PRICE.into(), "seller should receive price");
        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Filled,
            "order should be Filled",
        );
    }

    #[test]
    fn test_fulfill_bid() {
        // Bid: offerer offers ERC20, the NFT owner (fulfiller) accepts.
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();

        // Fulfiller owns the NFT and approves the marketplace.
        call_as(env.erc721.contract_address, owner);
        env.erc721.mint_token(env.fulfiller, TOKEN_ID.into());
        call_as(env.erc721.contract_address, env.fulfiller);
        env.erc721.approve_token(env.medialane.contract_address, TOKEN_ID.into());

        // Bidder (offerer) funds + approves the ERC20.
        call_as(env.erc20.contract_address, owner);
        env.erc20.mint_token(env.offerer, PRICE.into());
        call_as(env.erc20.contract_address, env.offerer);
        env.erc20.approve_token(env.medialane.contract_address, PRICE.into());

        let params = bid_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(env.medialane.contract_address, env.fulfiller);
        env.medialane.fulfill_order(hash);

        assert!(env.erc721.get_owner(TOKEN_ID.into()) == env.offerer, "NFT should go to bidder");
        assert!(env.erc20.get_balance(env.fulfiller) == PRICE.into(), "seller should be paid");
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
            "order should be Cancelled",
        );
    }

    #[test]
    #[should_panic(expected: 'Invalid signature')]
    fn test_cancel_rejects_wrong_signer() {
        let env = setup();
        let params = listing_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        // Cancellation signed by the fulfiller's key.
        env.medialane.cancel_order(signed_cancel(@env, hash, env.fulfiller_sk));
    }

    #[test]
    fn test_increment_counter_invalidates_new_orders() {
        let env = setup();
        // Bump the offerer's epoch.
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
        // listing_params uses counter 0, now stale.
        let params = listing_params(@env);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    fn test_register_listing_stores_created() {
        let env = setup();
        let params = listing_params(@env);
        let order = signed_order(@env, params, env.offerer_sk);
        let hash = env.medialane.get_order_hash(params, params.offerer);

        env.medialane.register_order(order);

        let details = env.medialane.get_order_details(hash);
        assert!(details.order_status == OrderStatus::Created, "order should be Created");
        assert!(details.offerer == env.offerer, "offerer mismatch");
        assert!(details.consideration.amount == PRICE, "price mismatch");
        assert!(details.royalty_max_bps == 1000, "royalty bound mismatch");
    }

    #[test]
    #[should_panic(expected: 'Invalid signature')]
    fn test_register_rejects_invalid_signature() {
        let env = setup();
        let params = listing_params(@env);
        // Signed by the fulfiller's key, not the offerer's.
        let order = signed_order(@env, params, env.fulfiller_sk);
        env.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: 'Wrong marketplace')]
    fn test_register_rejects_wrong_marketplace() {
        let env = setup();
        let mut params = listing_params(@env);
        // Order targets a different deployment (S1 replay protection).
        params.marketplace = 0xdead.try_into().unwrap();
        let order = signed_order(@env, params, env.offerer_sk);
        env.medialane.register_order(order);
    }

    #[test]
    #[should_panic(expected: 'Invalid counter')]
    fn test_register_rejects_stale_counter() {
        let env = setup();
        let mut params = listing_params(@env);
        params.counter = 5; // contract counter for offerer is 0
        let order = signed_order(@env, params, env.offerer_sk);
        env.medialane.register_order(order);
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
        let order = signed_order(@env, params, env.offerer_sk);
        env.medialane.register_order(order);
    }

    // --- shape allowlist + item validation ---

    #[test]
    fn test_register_accepts_bid() {
        let env = setup();
        let params = bid_params(@env);
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Created,
            "bid should register",
        );
    }

    #[test]
    fn test_register_allows_zero_price() {
        // F9: a free listing (price 0) is a valid order; only token/recipient/NFT
        // quantity must be non-zero.
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
    #[should_panic(expected: 'Unsupported trade shape')]
    fn test_register_rejects_nft_for_nft() {
        let env = setup();
        let mut params = listing_params(@env);
        params.consideration.item_type = 'ERC721';
        params.consideration.amount = 1;
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Token address cannot be zero')]
    fn test_register_rejects_zero_nft_token() {
        let env = setup();
        let mut params = listing_params(@env);
        params.offer.token = 0.try_into().unwrap();
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));
    }

    #[test]
    #[should_panic(expected: 'Invalid amount')]
    fn test_register_rejects_erc721_amount_not_one() {
        let env = setup();
        let mut params = listing_params(@env);
        params.offer.amount = 2;
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
        // NATIVE must carry a zero token field.
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

    // --- time window ---

    #[test]
    #[should_panic(expected: 'Order expired')]
    fn test_register_rejects_expired() {
        let env = setup();
        let mut params = listing_params(@env);
        params.start_time = 0;
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

    #[test]
    fn test_fulfill_bid_pays_royalty() {
        // Royalty is paid on the bid direction too (seller = fulfiller).
        let env = setup();
        let owner: ContractAddress = OWNER.try_into().unwrap();
        let receiver: ContractAddress = ROYALTY_RECEIVER.try_into().unwrap();
        let medialane = env.medialane.contract_address;

        let roy = IMockERC721RoyaltyDispatcher {
            contract_address: declare_and_deploy(
                "MockERC721Royalty", array![owner.into(), receiver.into(), 500],
            ),
        };
        // Seller (fulfiller) owns the NFT + approves.
        call_as(roy.contract_address, owner);
        roy.mint_token(env.fulfiller, TOKEN_ID.into());
        call_as(roy.contract_address, env.fulfiller);
        roy.approve_token(medialane, TOKEN_ID.into());
        // Bidder (offerer) funds + approves the ERC20.
        call_as(env.erc20.contract_address, owner);
        env.erc20.mint_token(env.offerer, PRICE.into());
        call_as(env.erc20.contract_address, env.offerer);
        env.erc20.approve_token(medialane, PRICE.into());

        let mut params = bid_params(@env);
        params.consideration.token = roy.contract_address;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash);

        let royalty: u256 = 50000; // 5% of PRICE
        assert!(env.erc20.get_balance(receiver) == royalty, "creator royalty on bid");
        assert!(env.erc20.get_balance(env.fulfiller) == PRICE.into() - royalty, "seller net");
    }

    #[test]
    fn test_fulfill_zero_price() {
        // A free listing (price 0) transfers the NFT with no payment.
        let env = setup();
        let medialane = env.medialane.contract_address;
        call_as(env.erc721.contract_address, OWNER.try_into().unwrap());
        env.erc721.mint_token(env.offerer, TOKEN_ID.into());
        call_as(env.erc721.contract_address, env.offerer);
        env.erc721.approve_token(medialane, TOKEN_ID.into());

        let mut params = listing_params(@env);
        params.consideration.amount = 0;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash);

        assert!(env.erc721.get_owner(TOKEN_ID.into()) == env.fulfiller, "free transfer to buyer");
        assert!(
            env.medialane.get_order_details(hash).order_status == OrderStatus::Filled,
            "should be Filled",
        );
    }

    #[test]
    #[should_panic]
    fn test_fulfill_phantom_order_reverts() {
        // Order registered for an NFT the offerer neither owns nor approved →
        // fulfilment reverts at NFT delivery (payment is rolled back atomically).
        let env = setup();
        let medialane = env.medialane.contract_address;
        // Fund the buyer so payment succeeds and we reach the NFT transfer.
        call_as(env.erc20.contract_address, OWNER.try_into().unwrap());
        env.erc20.mint_token(env.fulfiller, PRICE.into());
        call_as(env.erc20.contract_address, env.fulfiller);
        env.erc20.approve_token(medialane, PRICE.into());

        let params = listing_params(@env); // offerer never minted/approved the NFT
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash);
    }

    #[test]
    #[should_panic(expected: 'Reentrant call')]
    fn test_fulfill_reentrancy_blocked() {
        // A listing whose payment token reenters fulfill_order during settlement.
        // The guard must abort the reentrant call.
        let env = setup();
        let medialane = env.medialane.contract_address;

        let malicious = IMaliciousERC20Dispatcher {
            contract_address: declare_and_deploy("MaliciousERC20", array![]),
        };

        // Offerer owns + approves the NFT (registration is valid).
        call_as(env.erc721.contract_address, OWNER.try_into().unwrap());
        env.erc721.mint_token(env.offerer, TOKEN_ID.into());
        call_as(env.erc721.contract_address, env.offerer);
        env.erc721.approve_token(medialane, TOKEN_ID.into());

        // Consideration token = the malicious reentrant ERC20.
        let mut params = listing_params(@env);
        params.consideration.token = malicious.contract_address;
        let hash = env.medialane.get_order_hash(params, params.offerer);
        env.medialane.register_order(signed_order(@env, params, env.offerer_sk));

        malicious.set_attack(medialane, hash);

        call_as(medialane, env.fulfiller);
        env.medialane.fulfill_order(hash); // _pay -> malicious.transfer_from -> reenter
    }
}
