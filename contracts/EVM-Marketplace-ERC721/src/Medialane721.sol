// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// Medialane721 — immutable ERC721 marketplace venue for signed orders.
///
/// Safety model — every check is on-chain and falls in exactly one bucket:
///   1. Statically determinable from the signed order → validated at
///      registration, fail-fast.
///   2. Mutable on-chain state (ownership, approval, balance, live ERC-2981)
///      → not pre-simulated; enforced by atomic revert at fill. Settlement
///      pulls payment before delivering the NFT, under a reentrancy guard.
///
/// No owner, admin, upgrade, or pause.
contract Medialane721 is EIP712 {
    enum ItemType {
        NATIVE,
        ERC20,
        ERC721
    }

    enum OrderStatus {
        None,
        Created,
        Filled,
        Cancelled
    }

    /// A single fixed-price item. `amount` is the quantity (1 for ERC721, the
    /// wei amount for NATIVE/ERC20). `identifier` carries the ERC721 token id.
    struct OfferItem {
        ItemType itemType;
        address token;
        uint256 identifier;
        uint256 amount;
    }

    struct ConsiderationItem {
        ItemType itemType;
        address token;
        uint256 identifier;
        uint256 amount;
        address recipient;
    }

    /// The signed order. The deployment and chain are bound by the EIP-712
    /// domain, so a signature for one deployment cannot be replayed on
    /// another. `royaltyMaxBps` is the seller-signed cap on the ERC-2981
    /// royalty paid at fill. `counter` is the offerer's bulk-cancel epoch.
    /// `salt` gives economically-identical orders distinct hashes.
    struct OrderParameters {
        address offerer;
        OfferItem offer;
        ConsiderationItem consideration;
        uint256 royaltyMaxBps;
        uint256 startTime;
        uint256 endTime;
        uint256 salt;
        uint256 counter;
    }

    /// Stored order record.
    struct OrderDetails {
        address offerer;
        OfferItem offer;
        ConsiderationItem consideration;
        uint256 royaltyMaxBps;
        uint64 startTime;
        uint64 endTime;
        OrderStatus status;
        uint256 counter;
    }

    uint256 private constant BPS_DENOMINATOR = 10_000;

    mapping(bytes32 orderHash => OrderDetails) private _orders;
    mapping(address offerer => uint256) private _cancelCounter;

    event OrderCreated(bytes32 indexed orderHash, address indexed offerer);

    error InvalidOfferer();
    error InvalidCounter();
    error RoyaltyBpsTooHigh();
    error UnsupportedShape();
    error InvalidTokenAddress();
    error InvalidAmount();
    error NonzeroNativeToken();
    error InvalidIdentifier();
    error InvalidRecipient();
    error PaymentTokenIsNft();
    error NativeBidUnsupported();
    error InvalidTimeWindow();
    error OrderExpired();
    error OrderAlreadyExists();
    error InvalidSignature();

    bytes32 private constant OFFER_ITEM_TYPEHASH = keccak256(
        "OfferItem(uint8 itemType,address token,uint256 identifier,uint256 amount)"
    );
    bytes32 private constant CONSIDERATION_ITEM_TYPEHASH = keccak256(
        "ConsiderationItem(uint8 itemType,address token,uint256 identifier,uint256 amount,address recipient)"
    );
    bytes32 private constant ORDER_PARAMETERS_TYPEHASH = keccak256(
        "OrderParameters(address offerer,OfferItem offer,ConsiderationItem consideration,uint256 royaltyMaxBps,uint256 startTime,uint256 endTime,uint256 salt,uint256 counter)ConsiderationItem(uint8 itemType,address token,uint256 identifier,uint256 amount,address recipient)OfferItem(uint8 itemType,address token,uint256 identifier,uint256 amount)"
    );

    constructor() EIP712("Medialane", "1") {}

    /// Register a maker's signed order. Validates everything statically
    /// determinable from the order itself, fail-fast; mutable state
    /// (ownership, approval, balance) is enforced at fill.
    function registerOrder(OrderParameters calldata parameters, bytes calldata signature) external {
        address offerer = parameters.offerer;
        if (offerer == address(0)) revert InvalidOfferer();
        if (parameters.counter != _cancelCounter[offerer]) revert InvalidCounter();
        if (parameters.royaltyMaxBps > BPS_DENOMINATOR) revert RoyaltyBpsTooHigh();

        _validateOrderShape(parameters.offer, parameters.consideration);

        if (parameters.startTime > type(uint64).max || parameters.endTime > type(uint64).max) {
            revert InvalidTimeWindow();
        }
        if (parameters.endTime != 0) {
            if (parameters.startTime >= parameters.endTime) revert InvalidTimeWindow();
            if (block.timestamp >= parameters.endTime) revert OrderExpired();
        }

        bytes32 orderHash = getOrderHash(parameters);
        if (_orders[orderHash].status != OrderStatus.None) revert OrderAlreadyExists();
        if (!SignatureChecker.isValidSignatureNow(offerer, orderHash, signature)) revert InvalidSignature();

        _orders[orderHash] = OrderDetails({
            offerer: offerer,
            offer: parameters.offer,
            consideration: parameters.consideration,
            royaltyMaxBps: parameters.royaltyMaxBps,
            startTime: uint64(parameters.startTime),
            endTime: uint64(parameters.endTime),
            status: OrderStatus.Created,
            counter: parameters.counter
        });
        emit OrderCreated(orderHash, offerer);
    }

    function getOrderDetails(bytes32 orderHash) external view returns (OrderDetails memory) {
        return _orders[orderHash];
    }

    function getCounter(address offerer) external view returns (uint256) {
        return _cancelCounter[offerer];
    }

    /// Enforces the venue's trade shape: exactly one side is the ERC721 and
    /// the other is a payment. Listings (offer NFT) may be paid in NATIVE or
    /// ERC20; bids (offer payment) are ERC20 only — native value cannot be
    /// pulled from a signer at fill.
    function _validateOrderShape(OfferItem calldata offer, ConsiderationItem calldata consideration) private pure {
        if (consideration.recipient == address(0)) revert InvalidRecipient();

        if (offer.itemType == ItemType.ERC721) {
            _validateErc721Item(offer.token, offer.amount);
            _validatePaymentItem(consideration.itemType, consideration.token, consideration.identifier);
            if (consideration.itemType == ItemType.ERC20 && consideration.token == offer.token) {
                revert PaymentTokenIsNft();
            }
        } else if (offer.itemType == ItemType.ERC20) {
            _validatePaymentItem(offer.itemType, offer.token, offer.identifier);
            if (consideration.itemType != ItemType.ERC721) revert UnsupportedShape();
            _validateErc721Item(consideration.token, consideration.amount);
            if (consideration.token == offer.token) revert PaymentTokenIsNft();
        } else {
            revert NativeBidUnsupported();
        }
    }

    function _validateErc721Item(address token, uint256 amount) private pure {
        if (token == address(0)) revert InvalidTokenAddress();
        if (amount != 1) revert InvalidAmount();
    }

    /// Validates a payment leg. `amount` may be zero (free orders allowed).
    function _validatePaymentItem(ItemType itemType, address token, uint256 identifier) private pure {
        if (itemType == ItemType.NATIVE) {
            if (token != address(0)) revert NonzeroNativeToken();
            if (identifier != 0) revert InvalidIdentifier();
        } else if (itemType == ItemType.ERC20) {
            if (token == address(0)) revert InvalidTokenAddress();
            if (identifier != 0) revert InvalidIdentifier();
        } else {
            revert UnsupportedShape();
        }
    }

    /// Full EIP-712 digest for an order under this deployment's domain.
    function getOrderHash(OrderParameters calldata parameters) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_PARAMETERS_TYPEHASH,
                    parameters.offerer,
                    keccak256(
                        abi.encode(
                            OFFER_ITEM_TYPEHASH,
                            parameters.offer.itemType,
                            parameters.offer.token,
                            parameters.offer.identifier,
                            parameters.offer.amount
                        )
                    ),
                    keccak256(
                        abi.encode(
                            CONSIDERATION_ITEM_TYPEHASH,
                            parameters.consideration.itemType,
                            parameters.consideration.token,
                            parameters.consideration.identifier,
                            parameters.consideration.amount,
                            parameters.consideration.recipient
                        )
                    ),
                    parameters.royaltyMaxBps,
                    parameters.startTime,
                    parameters.endTime,
                    parameters.salt,
                    parameters.counter
                )
            )
        );
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
