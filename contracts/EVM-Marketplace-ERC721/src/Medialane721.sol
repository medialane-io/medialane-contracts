// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
contract Medialane721 is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    event OrderFulfilled(
        bytes32 indexed orderHash,
        address indexed offerer,
        address indexed fulfiller,
        uint256 saleAmount,
        address royaltyReceiver,
        uint256 royaltyAmount
    );
    event CounterIncremented(address indexed offerer, uint256 newCounter);
    event OrderCancelled(bytes32 indexed orderHash, address indexed offerer);

    error OrderNotFound();
    error OrderAlreadyFilled();
    error OrderCancelledError();
    error SelfFill();
    error OrderNotYetValid();
    error WrongNativeValue();
    error RoyaltyExceedsSale();
    error NativeTransferFailed();
    error CallerNotOfferer();
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
    /// (ownership, approval, balance) is enforced at fill. Guarded: lifecycle
    /// mutations may not run inside a fill's settlement window.
    function registerOrder(OrderParameters calldata parameters, bytes calldata signature) external nonReentrant {
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

    /// Fulfil an open order. The caller IS the fulfiller — no fulfiller
    /// signature is required. For NATIVE-priced listings the caller sends the
    /// exact sale amount as msg.value; all other fills send no value.
    function fulfillOrder(bytes32 orderHash) external payable nonReentrant {
        OrderDetails memory details = _orders[orderHash];
        if (details.status == OrderStatus.None) revert OrderNotFound();
        if (details.status == OrderStatus.Filled) revert OrderAlreadyFilled();
        if (details.status == OrderStatus.Cancelled) revert OrderCancelledError();

        address fulfiller = msg.sender;
        if (fulfiller == details.offerer) revert SelfFill();
        if (details.counter != _cancelCounter[details.offerer]) revert InvalidCounter();
        if (block.timestamp < details.startTime) revert OrderNotYetValid();
        if (details.endTime != 0 && block.timestamp >= details.endTime) revert OrderExpired();

        // Terminal state persists before any external call.
        _orders[orderHash].status = OrderStatus.Filled;

        (uint256 saleAmount, address royaltyReceiver, uint256 royaltyAmount) =
            _executeTransfers(details, fulfiller);

        emit OrderFulfilled(orderHash, details.offerer, fulfiller, saleAmount, royaltyReceiver, royaltyAmount);
    }

    /// Cancel a single open order. Only the order's offerer may cancel; the
    /// sender IS the authorization (no signature round-trip). Guarded:
    /// lifecycle mutations may not run inside a fill's settlement window.
    function cancelOrder(bytes32 orderHash) external nonReentrant {
        OrderDetails memory details = _orders[orderHash];
        if (details.status == OrderStatus.None) revert OrderNotFound();
        if (details.status == OrderStatus.Filled) revert OrderAlreadyFilled();
        if (details.status == OrderStatus.Cancelled) revert OrderCancelledError();
        if (msg.sender != details.offerer) revert CallerNotOfferer();

        _orders[orderHash].status = OrderStatus.Cancelled;
        emit OrderCancelled(orderHash, details.offerer);
    }

    /// Bulk-cancel: bump the caller's counter, invalidating all of their
    /// outstanding orders signed under the previous counter.
    function incrementCounter() external {
        uint256 newCounter = ++_cancelCounter[msg.sender];
        emit CounterIncremented(msg.sender, newCounter);
    }

    /// Settles an order: pulls payment from the payer (royalty first, then the
    /// seller's remainder) and only THEN delivers the NFT.
    function _executeTransfers(OrderDetails memory details, address fulfiller)
        private
        returns (uint256 saleAmount, address royaltyReceiver, uint256 royaltyAmount)
    {
        if (details.offer.itemType == ItemType.ERC721) {
            // Listing: buyer (fulfiller) pays; NFT goes offerer -> fulfiller.
            saleAmount = details.consideration.amount;
            (royaltyReceiver, royaltyAmount) = _pay(
                details.consideration.itemType,
                details.consideration.token,
                fulfiller,
                details.consideration.recipient,
                details.offer.token,
                details.offer.identifier,
                saleAmount,
                details.royaltyMaxBps
            );
            IERC721(details.offer.token).transferFrom(details.offerer, fulfiller, details.offer.identifier);
        } else {
            // Bid: bidder (offerer) pays; NFT goes fulfiller -> recipient.
            saleAmount = details.offer.amount;
            (royaltyReceiver, royaltyAmount) = _pay(
                details.offer.itemType,
                details.offer.token,
                details.offerer,
                fulfiller,
                details.consideration.token,
                details.consideration.identifier,
                saleAmount,
                details.royaltyMaxBps
            );
            IERC721(details.consideration.token).transferFrom(
                fulfiller, details.consideration.recipient, details.consideration.identifier
            );
        }
    }

    /// Pays `saleAmount`: the (capped) ERC-2981 royalty to the creator, the
    /// remainder to `sellerRecipient`. NATIVE settles from msg.value (exact);
    /// ERC20 pulls from the payer.
    function _pay(
        ItemType paymentType,
        address paymentToken,
        address payer,
        address sellerRecipient,
        address nft,
        uint256 tokenId,
        uint256 saleAmount,
        uint256 royaltyMaxBps
    ) private returns (address royaltyReceiver, uint256 royaltyAmount) {
        (royaltyReceiver, royaltyAmount) = _getRoyalty(nft, tokenId, saleAmount, royaltyMaxBps);
        if (royaltyAmount > saleAmount) revert RoyaltyExceedsSale();
        uint256 sellerAmount = saleAmount - royaltyAmount;

        if (paymentType == ItemType.NATIVE) {
            if (msg.value != saleAmount) revert WrongNativeValue();
            if (royaltyAmount > 0) _sendNative(royaltyReceiver, royaltyAmount);
            if (sellerAmount > 0) _sendNative(sellerRecipient, sellerAmount);
        } else {
            if (msg.value != 0) revert WrongNativeValue();
            if (royaltyAmount > 0) IERC20(paymentToken).safeTransferFrom(payer, royaltyReceiver, royaltyAmount);
            if (sellerAmount > 0) IERC20(paymentToken).safeTransferFrom(payer, sellerRecipient, sellerAmount);
        }
    }

    function _sendNative(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }

    /// ERC-2981 royalty for the NFT on `saleAmount`, capped at the
    /// seller-signed `royaltyMaxBps`. A non-2981 NFT, a failing call,
    /// malformed return data, a zero receiver, or a zero amount yields no
    /// royalty — a broken royalty implementation never blocks a fill. Raw
    /// staticcalls because try/catch does not survive return-data decoding
    /// failures.
    function _getRoyalty(address nft, uint256 tokenId, uint256 saleAmount, uint256 royaltyMaxBps)
        private
        view
        returns (address, uint256)
    {
        if (saleAmount == 0) return (address(0), 0);

        (bool ok, bytes memory ret) =
            nft.staticcall(abi.encodeCall(IERC165.supportsInterface, (type(IERC2981).interfaceId)));
        if (!ok || ret.length < 32) return (address(0), 0);
        bytes32 supportedWord;
        assembly ("memory-safe") {
            supportedWord := mload(add(ret, 0x20))
        }
        if (supportedWord == bytes32(0)) return (address(0), 0);

        (ok, ret) = nft.staticcall(abi.encodeCall(IERC2981.royaltyInfo, (tokenId, saleAmount)));
        if (!ok || ret.length < 64) return (address(0), 0);
        bytes32 receiverWord;
        bytes32 amountWord;
        assembly ("memory-safe") {
            receiverWord := mload(add(ret, 0x20))
            amountWord := mload(add(ret, 0x40))
        }
        if (uint256(receiverWord) > type(uint160).max) return (address(0), 0);
        address receiver = address(uint160(uint256(receiverWord)));
        uint256 rawAmount = uint256(amountWord);

        if (receiver == address(0) || rawAmount == 0) return (address(0), 0);
        uint256 maxAmount = saleAmount * royaltyMaxBps / BPS_DENOMINATOR;
        uint256 capped = rawAmount > maxAmount ? maxAmount : rawAmount;
        if (capped == 0) return (address(0), 0);
        return (receiver, capped);
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
