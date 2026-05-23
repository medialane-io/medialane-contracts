use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use medialane_marketplace::marketplace_1155::{
    IMedialane1155Dispatcher, IMedialane1155DispatcherTrait,
};
use medialane_marketplace::mocks::{
    IMockERC1155Dispatcher, IMockERC1155DispatcherTrait,
    IMockERC20Dispatcher, IMockERC20DispatcherTrait,
};
use medialane_marketplace::types::{
    ConsiderationItem, FulfillmentRequest1155, OfferItem, Order, OrderFulfillment1155,
    OrderParameters, OrderStatus,
};

fn deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let class = declare(name).unwrap().contract_class();
    let (address, _) = class.deploy(@calldata).unwrap();
    address
}

#[test]
fn fulfill_order_1155_supports_partial_fills() {
    // A 10-unit ERC-1155 listing at 100/unit, filled in two parts (3 + 7) by
    // two different buyers. Order stays Created until fully consumed.
    let marketplace = deploy("Medialane1155", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let buyer1 = deploy("MockAccount", array![2]);
    let buyer2 = deploy("MockAccount", array![3]);
    let nft = deploy("MockERC1155", array![]);
    let currency = deploy("MockERC20", array![]);

    let nft_dispatcher = IMockERC1155Dispatcher { contract_address: nft };
    let erc20_dispatcher = IMockERC20Dispatcher { contract_address: currency };
    nft_dispatcher.mint(offerer, 5_u256, 10_u256);
    erc20_dispatcher.mint(buyer1, 300_u256);
    erc20_dispatcher.mint(buyer2, 700_u256);

    let params = OrderParameters {
        offerer,
        offer: OfferItem {
            item_type: 'ERC1155',
            token: nft,
            token_id: 5,
            amount: 10,  // total units offered
        },
        consideration: ConsiderationItem {
            item_type: 'ERC20',
            token: currency,
            token_id: 0,
            amount: 100,  // PER-UNIT price (F4 — documented)
            recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xe1155,
    };
    let dispatcher = IMedialane1155Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    // First partial fill: buyer1 takes 3 units → pays 300.
    let f1 = OrderFulfillment1155 {
        order_hash, fulfiller: buyer1, quantity: 3, salt: 0xfa1,
    };
    start_cheat_caller_address(marketplace, buyer1);
    dispatcher.fulfill_order(FulfillmentRequest1155 { fulfillment: f1, signature: array![] });
    stop_cheat_caller_address(marketplace);

    assert!(nft_dispatcher.balance_of(buyer1, 5_u256) == 3_u256, "buyer1 received 3 NFTs");
    assert!(erc20_dispatcher.balance_of(offerer) == 300_u256, "offerer received 300");
    let after_first = dispatcher.get_order_details(order_hash);
    assert!(after_first.remaining_amount == 7_u256, "7 units remaining");
    assert!(after_first.order_status == OrderStatus::Created, "order still open");

    // Second partial fill: buyer2 takes the remaining 7 units → pays 700.
    let f2 = OrderFulfillment1155 {
        order_hash, fulfiller: buyer2, quantity: 7, salt: 0xfa2,
    };
    start_cheat_caller_address(marketplace, buyer2);
    dispatcher.fulfill_order(FulfillmentRequest1155 { fulfillment: f2, signature: array![] });
    stop_cheat_caller_address(marketplace);

    assert!(nft_dispatcher.balance_of(buyer2, 5_u256) == 7_u256, "buyer2 received 7 NFTs");
    assert!(erc20_dispatcher.balance_of(offerer) == 1000_u256, "offerer received 1000 total");
    let final_state = dispatcher.get_order_details(order_hash);
    assert!(final_state.remaining_amount == 0_u256, "fully consumed");
    assert!(final_state.order_status == OrderStatus::Filled, "order is Filled");
}

// ─── 1155-specific negative coverage ─────────────────────────────────────────

fn standard_listing(
    offerer: ContractAddress, nft: ContractAddress, currency: ContractAddress, total: felt252,
) -> OrderParameters {
    OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC1155', token: nft, token_id: 5, amount: total },
        consideration: ConsiderationItem {
            item_type: 'ERC20', token: currency, token_id: 0, amount: 100, recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0x1155,
    }
}

#[test]
#[should_panic(expected: "Insufficient remaining units")]
fn fulfill_order_1155_rejects_overfill() {
    // Trying to take 6 units from an order with only 5 available must revert.
    let marketplace = deploy("Medialane1155", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let buyer = deploy("MockAccount", array![2]);
    let nft = deploy("MockERC1155", array![]);
    let currency = deploy("MockERC20", array![]);

    IMockERC1155Dispatcher { contract_address: nft }.mint(offerer, 5_u256, 5_u256);
    IMockERC20Dispatcher { contract_address: currency }.mint(buyer, 1_000_u256);

    let params = standard_listing(offerer, nft, currency, 5);
    let dispatcher = IMedialane1155Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let oversized = OrderFulfillment1155 {
        order_hash, fulfiller: buyer, quantity: 6, salt: 0xff,
    };
    start_cheat_caller_address(marketplace, buyer);
    dispatcher.fulfill_order(FulfillmentRequest1155 {
        fulfillment: oversized, signature: array![],
    });
    stop_cheat_caller_address(marketplace);
}

#[test]
#[should_panic(expected: "Fulfillment already consumed")]
fn fulfill_order_1155_rejects_replay() {
    // The F1 guard at work: re-submitting the same partial-fill intent against
    // a still-open order must revert. This is the case the consumed-hash map
    // was designed for — status stays Created across fills.
    let marketplace = deploy("Medialane1155", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let buyer = deploy("MockAccount", array![2]);
    let nft = deploy("MockERC1155", array![]);
    let currency = deploy("MockERC20", array![]);

    IMockERC1155Dispatcher { contract_address: nft }.mint(offerer, 5_u256, 10_u256);
    IMockERC20Dispatcher { contract_address: currency }.mint(buyer, 1_000_u256);

    let params = standard_listing(offerer, nft, currency, 10);
    let dispatcher = IMedialane1155Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let fulfillment = OrderFulfillment1155 {
        order_hash, fulfiller: buyer, quantity: 3, salt: 0xfeed,
    };
    start_cheat_caller_address(marketplace, buyer);
    dispatcher.fulfill_order(FulfillmentRequest1155 {
        fulfillment, signature: array![],
    });
    // Order still has 7 remaining — status is Created. Same intent must not replay.
    dispatcher.fulfill_order(FulfillmentRequest1155 {
        fulfillment, signature: array![],
    });
    stop_cheat_caller_address(marketplace);
}

#[test]
#[should_panic(expected: "Cannot fill own order")]
fn fulfill_order_1155_rejects_self_fill() {
    let marketplace = deploy("Medialane1155", array![]);
    let alice = deploy("MockAccount", array![1]);
    let nft = deploy("MockERC1155", array![]);
    let currency = deploy("MockERC20", array![]);

    IMockERC1155Dispatcher { contract_address: nft }.mint(alice, 5_u256, 10_u256);

    let params = standard_listing(alice, nft, currency, 10);
    let dispatcher = IMedialane1155Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, alice);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let fulfillment = OrderFulfillment1155 {
        order_hash, fulfiller: alice, quantity: 1, salt: 0x5e1f,
    };
    start_cheat_caller_address(marketplace, alice);
    dispatcher.fulfill_order(FulfillmentRequest1155 {
        fulfillment, signature: array![],
    });
    stop_cheat_caller_address(marketplace);
}
