// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// Medialane1155 — immutable ERC1155 marketplace venue for signed orders, with
/// partial fills and per-unit pricing.
///
/// Safety model — every check is on-chain and falls in exactly one bucket:
///   1. Statically determinable from the signed order → validated at
///      registration, fail-fast.
///   2. Mutable on-chain state (ownership, approval, balance, live ERC-2981)
///      → not pre-simulated; enforced by atomic revert at fill. Settlement
///      pulls payment before delivering the units, under a reentrancy guard.
///      Per-unit pricing (sale = price-per-unit * quantity) is
///      overflow-checked.
///
/// No owner, admin, upgrade, or pause.
contract Medialane1155 is EIP712 {
    enum ItemType {
        NATIVE,
        ERC20,
        ERC1155
    }

    enum OrderStatus {
        None,
        Created,
        Filled,
        Cancelled
    }

    /// A single item. For an ERC1155 leg, `amount` is the quantity of units.
    /// For a payment leg, `amount` is the price PER UNIT
    /// (sale = price-per-unit * quantity). `identifier` carries the ERC1155
    /// token id.
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

    /// Stored order record. `remainingAmount` tracks unfilled ERC1155 units
    /// for partial fills.
    struct OrderDetails {
        address offerer;
        OfferItem offer;
        ConsiderationItem consideration;
        uint256 royaltyMaxBps;
        uint256 remainingAmount;
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
    /// (ownership, approval, balance) is enforced at fill. The ERC1155 leg's
    /// quantity seeds `remainingAmount` for partial fills.
    function registerOrder(OrderParameters calldata parameters, bytes calldata signature) external {
        address offerer = parameters.offerer;
        if (offerer == address(0)) revert InvalidOfferer();
        if (parameters.counter != _cancelCounter[offerer]) revert InvalidCounter();
        if (parameters.royaltyMaxBps > BPS_DENOMINATOR) revert RoyaltyBpsTooHigh();

        uint256 erc1155Amount = _validateOrderShape(parameters.offer, parameters.consideration);

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
            remainingAmount: erc1155Amount,
            startTime: uint64(parameters.startTime),
            endTime: uint64(parameters.endTime),
            status: OrderStatus.Created,
            counter: parameters.counter
        });
        emit OrderCreated(orderHash, offerer);
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

    function getOrderDetails(bytes32 orderHash) external view returns (OrderDetails memory) {
        return _orders[orderHash];
    }

    function getCounter(address offerer) external view returns (uint256) {
        return _cancelCounter[offerer];
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /// Enforces the venue's trade shape: exactly one side is the ERC1155 and
    /// the other is a payment. Listings (offer units) may be paid in NATIVE or
    /// ERC20; bids (offer payment) are ERC20 only — native value cannot be
    /// pulled from a signer at fill. Returns the ERC1155 quantity, which seeds
    /// `remainingAmount`.
    function _validateOrderShape(OfferItem calldata offer, ConsiderationItem calldata consideration)
        private
        pure
        returns (uint256 erc1155Amount)
    {
        if (consideration.recipient == address(0)) revert InvalidRecipient();

        if (offer.itemType == ItemType.ERC1155) {
            _validateErc1155Item(offer.token, offer.amount);
            _validatePaymentItem(consideration.itemType, consideration.token, consideration.identifier);
            if (consideration.itemType == ItemType.ERC20 && consideration.token == offer.token) {
                revert PaymentTokenIsNft();
            }
            erc1155Amount = offer.amount;
        } else if (offer.itemType == ItemType.ERC20) {
            _validatePaymentItem(offer.itemType, offer.token, offer.identifier);
            if (consideration.itemType != ItemType.ERC1155) revert UnsupportedShape();
            _validateErc1155Item(consideration.token, consideration.amount);
            if (consideration.token == offer.token) revert PaymentTokenIsNft();
            erc1155Amount = consideration.amount;
        } else {
            revert NativeBidUnsupported();
        }
    }

    function _validateErc1155Item(address token, uint256 amount) private pure {
        if (token == address(0)) revert InvalidTokenAddress();
        if (amount == 0) revert InvalidAmount();
    }

    /// Validates a payment leg. `amount` (the price per unit) may be zero
    /// (free orders allowed).
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
}
