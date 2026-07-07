// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Medialane1155} from "../src/Medialane1155.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";

/// Drives random register/partial-fulfill/cancel/incrementCounter sequences
/// and checks the venue's conservation properties.
contract Venue1155Handler is Test {
    Medialane1155 public venue;
    MockERC20 public erc20;
    MockERC1155 public nft;
    uint256 internal sellerPk = 0xA11CE;
    address public seller;
    address public buyer = address(0xB0B1);
    bytes32[] public hashes;
    mapping(bytes32 => uint256) public originalAmount;
    uint256 public unitsFilled;
    uint256 public nextTokenId = 1;

    constructor(Medialane1155 venue_, MockERC20 erc20_, MockERC1155 nft_) {
        venue = venue_;
        erc20 = erc20_;
        nft = nft_;
        seller = vm.addr(sellerPk);
        vm.prank(seller);
        nft.setApprovalForAll(address(venue), true);
        vm.prank(buyer);
        erc20.approve(address(venue), type(uint256).max);
    }

    function register(uint96 pricePerUnit, uint8 units) external {
        uint256 tokenId = nextTokenId++;
        uint256 quantity = bound(uint256(units), 1, 100);
        nft.mint(seller, tokenId, quantity);
        Medialane1155.OrderParameters memory params = Medialane1155.OrderParameters({
            offerer: seller,
            offer: Medialane1155.OfferItem(Medialane1155.ItemType.ERC1155, address(nft), tokenId, quantity),
            consideration: Medialane1155.ConsiderationItem(
                Medialane1155.ItemType.ERC20, address(erc20), 0, uint256(pricePerUnit), seller
            ),
            royaltyMaxBps: 500,
            startTime: block.timestamp,
            endTime: 0,
            salt: tokenId,
            counter: venue.getCounter(seller)
        });
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, orderHash);
        try venue.registerOrder(params, abi.encodePacked(r, s, v)) {
            hashes.push(orderHash);
            originalAmount[orderHash] = quantity;
        } catch {}
    }

    function fulfill(uint256 index, uint8 quantity) external {
        if (hashes.length == 0) return;
        bytes32 orderHash = hashes[index % hashes.length];
        Medialane1155.OrderDetails memory details = venue.getOrderDetails(orderHash);
        if (details.remainingAmount == 0) return;
        uint256 q = bound(uint256(quantity), 1, details.remainingAmount);
        erc20.mint(buyer, details.consideration.amount * q);
        vm.prank(buyer);
        try venue.fulfillOrder(orderHash, q) {
            unitsFilled += q;
        } catch {}
    }

    function cancel(uint256 index) external {
        if (hashes.length == 0) return;
        bytes32 orderHash = hashes[index % hashes.length];
        vm.prank(seller);
        try venue.cancelOrder(orderHash) {} catch {}
    }

    function bump() external {
        vm.prank(seller);
        venue.incrementCounter();
    }

    function hashCount() external view returns (uint256) {
        return hashes.length;
    }
}

contract Medialane1155InvariantTest is Test {
    Medialane1155 internal venue;
    MockERC20 internal erc20;
    MockERC1155 internal nft;
    Venue1155Handler internal handler;

    function setUp() public {
        vm.warp(1_000_000_000);
        venue = new Medialane1155();
        erc20 = new MockERC20();
        nft = new MockERC1155();
        handler = new Venue1155Handler(venue, erc20, nft);
        targetContract(address(handler));
    }

    /// Every successful fill moved exactly its quantity of units to the buyer.
    function invariant_unitsConserved() public view {
        uint256 buyerUnits;
        for (uint256 id = 1; id < handler.nextTokenId(); id++) {
            buyerUnits += nft.balanceOf(handler.buyer(), id);
        }
        assertEq(buyerUnits, handler.unitsFilled());
    }

    /// remaining never exceeds the original quantity, and the status is
    /// coherent with it: Filled iff zero remaining (unless Cancelled).
    function invariant_remainingAndStatusCoherent() public view {
        for (uint256 i = 0; i < handler.hashCount(); i++) {
            bytes32 orderHash = handler.hashes(i);
            Medialane1155.OrderDetails memory details = venue.getOrderDetails(orderHash);
            assertLe(details.remainingAmount, handler.originalAmount(orderHash));
            if (details.status == Medialane1155.OrderStatus.Filled) {
                assertEq(details.remainingAmount, 0);
            }
            if (details.status == Medialane1155.OrderStatus.Created) {
                assertGt(details.remainingAmount, 0);
            }
        }
    }
}
