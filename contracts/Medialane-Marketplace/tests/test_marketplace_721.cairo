use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use medialane_marketplace::marketplace_721::{
    IMedialane721Dispatcher, IMedialane721DispatcherTrait,
};
use medialane_marketplace::types::{
    ConsiderationItem, OfferItem, Order, OrderParameters, OrderStatus,
};

fn deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let class = declare(name).unwrap().contract_class();
    let (address, _) = class.deploy(@calldata).unwrap();
    address
}

#[test]
fn register_order_stores_a_created_order() {
    let marketplace = deploy("Medialane721", array![]);
    let offerer = deploy("MockAccount", array![]);

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
