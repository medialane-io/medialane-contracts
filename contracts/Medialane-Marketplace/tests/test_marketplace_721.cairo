use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare,
    start_cheat_block_timestamp, stop_cheat_block_timestamp,
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
    CancelRequest, ConsiderationItem, FulfillmentRequest, OfferItem, Order,
    OrderCancellation, OrderFulfillment, OrderParameters, OrderStatus,
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

#[test]
fn fulfill_order_pays_erc2981_royalty() {
    // The NFT is a collection that declares a flat 5% ERC-2981 royalty; the
    // royalty receiver must be paid before the seller gets the rest.
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let fulfiller = deploy("MockAccount", array![2]);
    let nft = deploy("MockRoyaltyNFT", array![]);
    let currency = deploy("MockERC20", array![]);

    // IMockERC721Dispatcher works against MockRoyaltyNFT — same entrypoint selectors.
    let nft_dispatcher = IMockERC721Dispatcher { contract_address: nft };
    nft_dispatcher.mint(offerer, 99_u256);
    let erc20_dispatcher = IMockERC20Dispatcher { contract_address: currency };
    erc20_dispatcher.mint(fulfiller, 1_000_000_u256);

    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC721', token: nft, token_id: 99, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20',
            token: currency,
            token_id: 0,
            amount: 1_000_000,
            recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xa11ce,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let fulfillment = OrderFulfillment { order_hash, fulfiller, salt: 0xb0b };
    start_cheat_caller_address(marketplace, fulfiller);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);

    // 5% royalty of 1_000_000 = 50_000. Seller gets the remaining 950_000.
    let royalty_receiver: ContractAddress = 0xcafe.try_into().unwrap();
    assert!(nft_dispatcher.owner_of(99_u256) == fulfiller, "NFT delivered to fulfiller");
    assert!(
        erc20_dispatcher.balance_of(royalty_receiver) == 50_000_u256,
        "5% royalty paid to the creator",
    );
    assert!(erc20_dispatcher.balance_of(offerer) == 950_000_u256, "seller paid net of royalty");
    assert!(erc20_dispatcher.balance_of(fulfiller) == 0_u256, "fulfiller paid out in full");
}

#[test]
#[should_panic(expected: ('Unsupported order shape', 'ENTRYPOINT_FAILED'))]
fn register_order_rejects_unsupported_shape() {
    // ERC-20 ↔ ERC-20 has no NFT leg and isn't supported — must be rejected
    // at registration so we never persist an order the contract cannot settle.
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let token_a: ContractAddress = 0xa.try_into().unwrap();
    let token_b: ContractAddress = 0xb.try_into().unwrap();

    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC20', token: token_a, token_id: 0, amount: 100 },
        consideration: ConsiderationItem {
            item_type: 'ERC20',
            token: token_b,
            token_id: 0,
            amount: 200,
            recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0x1,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    dispatcher.register_order(Order { parameters: params, signature: array![] });
}

#[test]
fn fulfill_order_erc721_swap_settles_both_nfts() {
    // The architecture explicitly supports ERC-721 ↔ ERC-721 swaps (no payment).
    let marketplace = deploy("Medialane721", array![]);
    let alice = deploy("MockAccount", array![1]);
    let bob = deploy("MockAccount", array![2]);
    let nft_a = deploy("MockERC721", array![]);
    let nft_b = deploy("MockERC721", array![]);

    let a_dispatcher = IMockERC721Dispatcher { contract_address: nft_a };
    let b_dispatcher = IMockERC721Dispatcher { contract_address: nft_b };
    a_dispatcher.mint(alice, 1_u256);  // Alice owns A#1
    b_dispatcher.mint(bob, 2_u256);    // Bob owns B#2

    let params = OrderParameters {
        offerer: alice,
        offer: OfferItem { item_type: 'ERC721', token: nft_a, token_id: 1, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC721',
            token: nft_b,
            token_id: 2,
            amount: 1,
            recipient: alice,    // Alice asks to receive B#2.
        },
        start_time: 0,
        end_time: 0,
        salt: 0xabc1,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, alice);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let fulfillment = OrderFulfillment { order_hash, fulfiller: bob, salt: 0xabc2 };
    start_cheat_caller_address(marketplace, bob);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);

    assert!(a_dispatcher.owner_of(1_u256) == bob, "nft_a should now belong to bob");
    assert!(b_dispatcher.owner_of(2_u256) == alice, "nft_b should now belong to alice");
    let details = dispatcher.get_order_details(order_hash);
    assert!(details.order_status == OrderStatus::Filled, "swap should be Filled");
}

#[test]
fn cancel_order_marks_the_order_cancelled() {
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);

    let nft_token: ContractAddress = 0xabcdef.try_into().unwrap();
    let currency: ContractAddress = 0x123456.try_into().unwrap();

    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC721', token: nft_token, token_id: 11, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20',
            token: currency,
            token_id: 0,
            amount: 500_000,
            recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xdeadbeef,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let cancellation = OrderCancellation { order_hash, offerer, salt: 0xc0c0 };
    dispatcher.cancel_order(CancelRequest { cancellation, signature: array![] });

    let details = dispatcher.get_order_details(order_hash);
    assert!(details.order_status == OrderStatus::Cancelled, "order should be Cancelled");
}

// ─── Regression-guard tests for the security invariants ──────────────────────
// These exercise the existing asserts so any future change that weakens a
// guard fails loudly. Each one is the minimum reproduction of a known attack.

#[test]
#[should_panic(expected: "Cannot fill own order")]
fn fulfill_order_rejects_self_fill() {
    // F2 — an offerer must not be allowed to fill their own listing (wash trading).
    let marketplace = deploy("Medialane721", array![]);
    let alice = deploy("MockAccount", array![1]);
    let nft = deploy("MockERC721", array![]);
    let currency = deploy("MockERC20", array![]);

    IMockERC721Dispatcher { contract_address: nft }.mint(alice, 1_u256);

    let params = OrderParameters {
        offerer: alice,
        offer: OfferItem { item_type: 'ERC721', token: nft, token_id: 1, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20', token: currency, token_id: 0, amount: 1, recipient: alice,
        },
        start_time: 0, end_time: 0, salt: 0x1,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, alice);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    // Alice tries to fulfill her own order — caller == offerer == fulfiller.
    let fulfillment = OrderFulfillment { order_hash, fulfiller: alice, salt: 0x2 };
    start_cheat_caller_address(marketplace, alice);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);
}

#[test]
#[should_panic(expected: "Order is not active")]
fn fulfill_order_rejects_cancelled_order() {
    // A cancelled order must not be fulfillable.
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let fulfiller = deploy("MockAccount", array![2]);
    let nft = deploy("MockERC721", array![]);
    let currency = deploy("MockERC20", array![]);

    IMockERC721Dispatcher { contract_address: nft }.mint(offerer, 1_u256);
    IMockERC20Dispatcher { contract_address: currency }.mint(fulfiller, 1_u256);

    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC721', token: nft, token_id: 1, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20', token: currency, token_id: 0, amount: 1, recipient: offerer,
        },
        start_time: 0, end_time: 0, salt: 0xff,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });

    // Cancel first…
    let cancellation = OrderCancellation { order_hash, offerer, salt: 0xc };
    dispatcher.cancel_order(CancelRequest { cancellation, signature: array![] });

    // …then try to fulfill the cancelled order.
    let fulfillment = OrderFulfillment { order_hash, fulfiller, salt: 0xfa };
    start_cheat_caller_address(marketplace, fulfiller);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);
}

#[test]
#[should_panic(expected: "Invalid signature")]
fn register_order_rejects_invalid_signature() {
    // The offerer's account returns a non-VALIDATED magic — the marketplace
    // must refuse to register the order.
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockBadAccount", array![1]);

    let nft_token: ContractAddress = 0xabc.try_into().unwrap();
    let currency: ContractAddress = 0xdef.try_into().unwrap();
    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC721', token: nft_token, token_id: 1, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20', token: currency, token_id: 0, amount: 1, recipient: offerer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xbad,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    dispatcher.register_order(Order { parameters: params, signature: array![] });
}

#[test]
#[should_panic(expected: "Order has expired")]
fn fulfill_order_rejects_expired_order() {
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![1]);
    let fulfiller = deploy("MockAccount", array![2]);
    let nft = deploy("MockERC721", array![]);
    let currency = deploy("MockERC20", array![]);

    IMockERC721Dispatcher { contract_address: nft }.mint(offerer, 1_u256);
    IMockERC20Dispatcher { contract_address: currency }.mint(fulfiller, 1_u256);

    // Register at t=100 with end_time=200.
    start_cheat_block_timestamp(marketplace, 100);
    let params = OrderParameters {
        offerer,
        offer: OfferItem { item_type: 'ERC721', token: nft, token_id: 1, amount: 1 },
        consideration: ConsiderationItem {
            item_type: 'ERC20', token: currency, token_id: 0, amount: 1, recipient: offerer,
        },
        start_time: 100, end_time: 200, salt: 0xee,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, offerer);
    dispatcher.register_order(Order { parameters: params, signature: array![] });
    stop_cheat_block_timestamp(marketplace);

    // Move past the expiry and try to fulfill.
    start_cheat_block_timestamp(marketplace, 500);
    let fulfillment = OrderFulfillment { order_hash, fulfiller, salt: 0xef };
    start_cheat_caller_address(marketplace, fulfiller);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);
    stop_cheat_block_timestamp(marketplace);
}

#[test]
fn fulfill_order_bid_settles_atomically() {
    // Bid: buyer offers ERC-20, wants an ERC-721 delivered to themselves.
    let marketplace = deploy("Medialane721", array![]);
    let buyer = deploy("MockAccount", array![1]);   // signs the bid (offerer)
    let seller = deploy("MockAccount", array![2]);  // holds the NFT (fulfiller)
    let nft = deploy("MockERC721", array![]);
    let currency = deploy("MockERC20", array![]);

    let nft_dispatcher = IMockERC721Dispatcher { contract_address: nft };
    nft_dispatcher.mint(seller, 42_u256);
    let erc20_dispatcher = IMockERC20Dispatcher { contract_address: currency };
    erc20_dispatcher.mint(buyer, 750_000_u256);

    let params = OrderParameters {
        offerer: buyer,
        offer: OfferItem {
            item_type: 'ERC20',
            token: currency,
            token_id: 0,
            amount: 750_000,
        },
        consideration: ConsiderationItem {
            item_type: 'ERC721',
            token: nft,
            token_id: 42,
            amount: 1,
            recipient: buyer,
        },
        start_time: 0,
        end_time: 0,
        salt: 0xb1d,
    };
    let dispatcher = IMedialane721Dispatcher { contract_address: marketplace };
    let order_hash = dispatcher.get_order_hash(params, buyer);

    dispatcher.register_order(Order { parameters: params, signature: array![] });

    let fulfillment = OrderFulfillment { order_hash, fulfiller: seller, salt: 0xb1d2 };
    start_cheat_caller_address(marketplace, seller);
    dispatcher.fulfill_order(FulfillmentRequest { fulfillment, signature: array![] });
    stop_cheat_caller_address(marketplace);

    assert!(nft_dispatcher.owner_of(42_u256) == buyer, "NFT delivered to buyer");
    assert!(erc20_dispatcher.balance_of(seller) == 750_000_u256, "seller received the bid");
    assert!(erc20_dispatcher.balance_of(buyer) == 0_u256, "buyer paid out");
    let details = dispatcher.get_order_details(order_hash);
    assert!(details.order_status == OrderStatus::Filled, "order should be Filled");
}
