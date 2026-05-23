//! Immutable ERC-721 marketplace.
//!
//! Zero-argument constructor, no admin, no upgrade, no fee — a neutral
//! settlement primitive. Orders are SNIP-12 signed off-chain and registered
//! on-chain; settlement is atomic, fee-free, honoring ERC-2981 royalty when
//! the traded collection declares it.

use crate::types::{
    CancelRequest, FulfillmentRequest, Order, OrderDetails, OrderParameters,
};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMedialane721<TContractState> {
    fn register_order(ref self: TContractState, order: Order);
    fn fulfill_order(ref self: TContractState, fulfillment_request: FulfillmentRequest);
    fn cancel_order(ref self: TContractState, cancel_request: CancelRequest);
    fn get_order_details(self: @TContractState, order_hash: felt252) -> OrderDetails;
    fn get_order_hash(
        self: @TContractState, parameters: OrderParameters, signer: ContractAddress,
    ) -> felt252;
}

#[starknet::contract]
pub mod Medialane721 {
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_utils::snip12::{OffchainMessageHash, SNIP12Metadata};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::settlement::{get_royalty, seller_proceeds};
    use crate::types::{
        CancelRequest, FulfillmentRequest, ItemType, Order, OrderDetails, OrderParameters,
        OrderStatus,
    };

    #[storage]
    struct Storage {
        /// The on-chain order book — keyed by SNIP-12 order hash.
        orders: Map<felt252, OrderDetails>,
        /// Unordered replay guard for consumed fulfillment + cancellation hashes (F1).
        consumed_intents: Map<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OrderCreated: OrderCreated,
        OrderFulfilled: OrderFulfilled,
        OrderCancelled: OrderCancelled,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderCreated {
        #[key]
        pub order_hash: felt252,
        #[key]
        pub offerer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderFulfilled {
        #[key]
        pub order_hash: felt252,
        pub offerer: ContractAddress,
        pub fulfiller: ContractAddress,
        pub sale_amount: u256,
        pub royalty_receiver: ContractAddress,
        pub royalty_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderCancelled {
        #[key]
        pub order_hash: felt252,
        pub offerer: ContractAddress,
    }

    pub impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'MedialaneMarketplace'
        }
        fn version() -> felt252 {
            '1'
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState) { // Intentionally zero-argument — no hardcoded addresses, no fee, no admin.
    }

    #[abi(embed_v0)]
    impl Medialane721Impl of super::IMedialane721<ContractState> {
        fn register_order(ref self: ContractState, order: Order) {
            let params = order.parameters;
            let signature = order.signature;
            let offerer = params.offerer;

            // F3 — validate the order shape at registration. Persist only orders
            // the contract knows how to settle: listing (ERC-721↔ERC-20),
            // bid (ERC-20↔ERC-721), or ERC-721↔ERC-721 swap.
            let offer_type: Option<ItemType> = params.offer.item_type.try_into();
            let cons_type: Option<ItemType> = params.consideration.item_type.try_into();
            assert(offer_type.is_some(), 'Invalid offer item type');
            assert(cons_type.is_some(), 'Invalid consideration type');
            let ot = offer_type.unwrap();
            let ct = cons_type.unwrap();
            let supported = (ot == ItemType::ERC721 && ct == ItemType::ERC20)
                || (ot == ItemType::ERC20 && ct == ItemType::ERC721)
                || (ot == ItemType::ERC721 && ct == ItemType::ERC721);
            assert(supported, 'Unsupported order shape');

            let order_hash = params.get_message_hash(offerer);

            // Replay guard — an order hash can be registered exactly once.
            let existing = self.orders.read(order_hash);
            assert!(existing.order_status == OrderStatus::None, "Order already exists");

            // Verify the offerer's SNIP-12 signature via SRC-6.
            let valid = ISRC6Dispatcher { contract_address: offerer }
                .is_valid_signature(order_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid signature");

            let start_time: u64 = params.start_time.try_into().expect('start_time out of range');
            let end_time: u64 = params.end_time.try_into().expect('end_time out of range');

            let details = OrderDetails {
                offerer,
                offer: params.offer,
                consideration: params.consideration,
                start_time,
                end_time,
                order_status: OrderStatus::Created,
            };
            self.orders.write(order_hash, details);

            self.emit(Event::OrderCreated(OrderCreated { order_hash, offerer }));
        }

        fn fulfill_order(ref self: ContractState, fulfillment_request: FulfillmentRequest) {
            let fulfillment = fulfillment_request.fulfillment;
            let signature = fulfillment_request.signature;
            let order_hash = fulfillment.order_hash;
            let fulfiller = fulfillment.fulfiller;

            // Front-run protection — only the named fulfiller may submit.
            assert!(get_caller_address() == fulfiller, "Caller is not the fulfiller");

            // Order must be live.
            let mut details = self.orders.read(order_hash);
            assert!(details.order_status == OrderStatus::Created, "Order is not active");

            // F2: no self-fill / wash trading.
            assert!(fulfiller != details.offerer, "Cannot fill own order");

            // Active window. `end_time == 0` means no expiry.
            let now = get_block_timestamp();
            assert!(now >= details.start_time, "Order not yet active");
            if details.end_time != 0 {
                assert!(now < details.end_time, "Order has expired");
            }

            // Verify the fulfiller's SNIP-12 signature on the fulfillment intent.
            let fulfillment_hash = fulfillment.get_message_hash(fulfiller);
            let valid = ISRC6Dispatcher { contract_address: fulfiller }
                .is_valid_signature(fulfillment_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid fulfillment signature");

            // F1: unordered replay guard on the fulfillment intent itself.
            assert!(
                !self.consumed_intents.read(fulfillment_hash),
                "Fulfillment already consumed",
            );
            self.consumed_intents.write(fulfillment_hash, true);

            // CEI — mark Filled before any external token call.
            details.order_status = OrderStatus::Filled;
            self.orders.write(order_hash, details);

            // Resolve the trade direction. Three supported shapes:
            //   - Listing: offer = ERC-721, consideration = ERC-20.
            //   - Bid:     offer = ERC-20,  consideration = ERC-721.
            //   - Swap:    offer = ERC-721, consideration = ERC-721 (no payment).
            let offer_type: ItemType = details.offer.item_type
                .try_into()
                .expect('Bad offer item type');
            let cons_type: ItemType = details.consideration.item_type
                .try_into()
                .expect('Bad consideration type');

            // Swap path — two NFTs, no payment, no royalty. Settle and return.
            if offer_type == ItemType::ERC721 && cons_type == ItemType::ERC721 {
                let offer_token_id: u256 = details.offer.token_id.into();
                let cons_token_id: u256 = details.consideration.token_id.into();

                IERC721Dispatcher { contract_address: details.offer.token }
                    .transfer_from(details.offerer, fulfiller, offer_token_id);
                IERC721Dispatcher { contract_address: details.consideration.token }
                    .transfer_from(
                        fulfiller, details.consideration.recipient, cons_token_id,
                    );

                let zero: ContractAddress = 0.try_into().unwrap();
                self
                    .emit(
                        Event::OrderFulfilled(
                            OrderFulfilled {
                                order_hash,
                                offerer: details.offerer,
                                fulfiller,
                                sale_amount: 0,
                                royalty_receiver: zero,
                                royalty_amount: 0,
                            },
                        ),
                    );
                return;
            }

            // The match returns only primitive types so the arms unify cleanly.
            // Tuple: (nft_token, nft_owner, nft_recipient, token_id,
            //         payment_token, payment_payer, payment_recipient, sale_amount)
            let (
                nft_token,
                nft_owner,
                nft_recipient,
                token_id,
                payment_token,
                payment_payer,
                payment_recipient,
                sale_amount,
            ) =
                if offer_type == ItemType::ERC721 && cons_type == ItemType::ERC20 {
                    // Listing — offerer sells NFT, fulfiller pays.
                    let token_id: u256 = details.offer.token_id.into();
                    let sale_amount: u256 = details.consideration.amount.into();
                    (
                        details.offer.token,
                        details.offerer,
                        fulfiller,
                        token_id,
                        details.consideration.token,
                        fulfiller,
                        details.consideration.recipient,
                        sale_amount,
                    )
                } else if offer_type == ItemType::ERC20 && cons_type == ItemType::ERC721 {
                    // Bid — offerer pays ERC-20, fulfiller delivers NFT to the
                    // consideration recipient; the seller (fulfiller) receives
                    // the payment.
                    let token_id: u256 = details.consideration.token_id.into();
                    let sale_amount: u256 = details.offer.amount.into();
                    (
                        details.consideration.token,
                        fulfiller,
                        details.consideration.recipient,
                        token_id,
                        details.offer.token,
                        details.offerer,
                        fulfiller,
                        sale_amount,
                    )
                } else {
                    panic!("Unsupported order shape")
                };

            // Royalty is best-effort; collections without ERC-2981 → (0, 0).
            let (royalty_receiver, royalty_amount) = get_royalty(
                nft_token, token_id, sale_amount,
            );
            let seller_amount = seller_proceeds(sale_amount, royalty_amount);

            // F5: pull payment BEFORE releasing the NFT.
            let payment = IERC20Dispatcher { contract_address: payment_token };
            if royalty_amount > 0 {
                let ok = payment.transfer_from(payment_payer, royalty_receiver, royalty_amount);
                assert!(ok, "Royalty transfer failed");
            }
            if seller_amount > 0 {
                let ok = payment.transfer_from(payment_payer, payment_recipient, seller_amount);
                assert!(ok, "Payment transfer failed");
            }

            // Then transfer the NFT.
            IERC721Dispatcher { contract_address: nft_token }
                .transfer_from(nft_owner, nft_recipient, token_id);

            self
                .emit(
                    Event::OrderFulfilled(
                        OrderFulfilled {
                            order_hash,
                            offerer: details.offerer,
                            fulfiller,
                            sale_amount,
                            royalty_receiver,
                            royalty_amount,
                        },
                    ),
                );
        }

        fn cancel_order(ref self: ContractState, cancel_request: CancelRequest) {
            let cancellation = cancel_request.cancellation;
            let signature = cancel_request.signature;
            let order_hash = cancellation.order_hash;
            let offerer = cancellation.offerer;

            // Order must be live.
            let mut details = self.orders.read(order_hash);
            assert!(details.order_status == OrderStatus::Created, "Order is not active");

            // Only the order's original offerer can cancel it. Anyone may submit
            // the transaction — the signature is the authority.
            assert!(offerer == details.offerer, "Not the order's offerer");

            // Verify the offerer's SNIP-12 signature on the cancellation intent.
            let cancellation_hash = cancellation.get_message_hash(offerer);
            let valid = ISRC6Dispatcher { contract_address: offerer }
                .is_valid_signature(cancellation_hash, signature);
            assert!(valid == starknet::VALIDATED || valid == 1, "Invalid cancellation signature");

            // F1: unordered replay guard.
            assert!(
                !self.consumed_intents.read(cancellation_hash),
                "Cancellation already consumed",
            );
            self.consumed_intents.write(cancellation_hash, true);

            details.order_status = OrderStatus::Cancelled;
            self.orders.write(order_hash, details);

            self.emit(Event::OrderCancelled(OrderCancelled { order_hash, offerer }));
        }

        fn get_order_details(self: @ContractState, order_hash: felt252) -> OrderDetails {
            self.orders.read(order_hash)
        }

        fn get_order_hash(
            self: @ContractState, parameters: OrderParameters, signer: ContractAddress,
        ) -> felt252 {
            parameters.get_message_hash(signer)
        }
    }
}
