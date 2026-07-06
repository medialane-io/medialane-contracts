// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

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
