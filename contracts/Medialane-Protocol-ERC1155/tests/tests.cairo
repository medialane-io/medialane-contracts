#[cfg(test)]
mod test {
    use medialane_erc1155::core::interface::{
        IMedialane1155Dispatcher, IMedialane1155DispatcherTrait,
    };
    use medialane_erc1155::core::types::*;
    use medialane_erc1155::mocks::erc1155::{IMockERC1155Dispatcher, IMockERC1155DispatcherTrait};
    use medialane_erc1155::mocks::erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
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
}
