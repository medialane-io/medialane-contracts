use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use medialane_marketplace::marketplace_721::{
    IMedialane721Dispatcher, IMedialane721DispatcherTrait,
};
use medialane_marketplace::mocks::{
    IMockERC20Dispatcher, IMockERC20DispatcherTrait,
    IMockERC721Dispatcher, IMockERC721DispatcherTrait,
};
use medialane_marketplace::types::{
    ConsiderationItem, FulfillmentRequest, OfferItem, Order, OrderFulfillment,
    OrderParameters, OrderStatus,
};

fn deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let class = declare(name).unwrap().contract_class();
    let (address, _) = class.deploy(@calldata).unwrap();
    address
}

#[test]
fn register_order_stores_a_created_order() {
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);

    let nft_token: ContractAddress = 0xabcdef.try_into().unwrap();
    let currency: ContractAddress = 0x123456.try_into().unwrap();

    let params = OrderParameters {
        offerer,
        offer: OfferItem {
            item_type: 'ERC721',
            token: nft_token,
            token_id: 7,
            amount: 1,
        },
        consideration: ConsiderationItem {
            item_type: 'ERC20',
            token: currency,
            token_id: 0,
            amount: 1_000_000,
            recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xc0ffee,
    };

    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);

    let order = Order { parameters: params, signature: array![] };
    dispatcher.register_order(order);

    let details = dispatcher.get_order_details(order_hash);
    assert!(details.order_status == OrderStatus::Created, "order should be Created");
    assert!(details.offerer == offerer, "offerer should be stored");
}

#[test]
fn fulfill_order_listing_settles_atomically() {
    // Setup: marketplace + two distinct mock accounts + NFT + currency mocks.
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let fulfiller = deploy("MockAccount", array![2]);
    let nft = deploy("MockERC721", array![]);
    let currency = deploy("MockERC20", array![]);

    // Offerer owns NFT #7; fulfiller has 1_000_000 currency tokens.
    let nft_dispatcher = IMockERC721Dispatcher { contract_address: nft };
    nft_dispatcher.mint(offerer, 7_u256);
    let erc20_dispatcher = IMockERC20Dispatcher { contract_address: currency };
    erc20_dispatcher.mint(fulfiller, 1_000_000_u256);

    // Build a listing: offerer offers NFT #7, wants 1_000_000 currency to themselves.
    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC721', token: nft, token_id: 7, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20',
            token: currency,
            token_id: 0,
            amount: 1_000_000,
            recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xaaaa,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);

    dispatcher.register_order(Order { parameters: params, signature: array![] });

    // Fulfill — caller must be the fulfiller (front-run protection).
    let fulfillment = OrderFulfillment { order_hash, fulfiller, salt: 0xbbbb };
    start_cheat_caller_address(marketplace, fulfiller);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);

    // Atomic settlement: NFT moved, payment moved, status Filled.
    assert!(nft_dispatcher.owner_of(7_u256) == fulfiller, "NFT should be with fulfiller");
    assert!(erc20_dispatcher.balance_of(offerer) == 1_000_000_u256, "offerer paid in full");
    assert!(erc20_dispatcher.balance_of(fulfiller) == 0_u256, "fulfiller paid out");
    let details = dispatcher.get_order_details(order_hash);
    assert!(details.order_status == OrderStatus::Filled, "order should be Filled");
}
