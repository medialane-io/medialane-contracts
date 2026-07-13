// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Medialane1155} from "../src/Medialane1155.sol";
import {BrokenRoyaltyERC1155} from "./mocks/BrokenRoyaltyERC1155.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {ReentrantERC1155} from "./mocks/ReentrantERC1155.sol";

contract Medialane1155FulfillTest is Test {
    Medialane1155 internal venue;
    MockERC20 internal erc20;
    MockERC1155 internal nft;
    uint256 internal sellerPk = 0xA11CE;
    address internal seller;
    address internal buyer = makeAddr("buyer");
    address internal royaltyReceiver = makeAddr("royalties");

    event OrderFulfilled(
        bytes32 indexed orderHash,
        address indexed offerer,
        address indexed fulfiller,
        uint256 quantity,
        uint256 remainingAmount,
        uint256 saleAmount,
        address royaltyReceiver,
        uint256 royaltyAmount
    );

    function setUp() public {
        venue = new Medialane1155();
        erc20 = new MockERC20();
        nft = new MockERC1155();
        seller = vm.addr(sellerPk);
        vm.warp(1_000_000_000);
        nft.mint(seller, 7, 50);
        vm.prank(seller);
        nft.setApprovalForAll(address(venue), true);
        erc20.mint(buyer, 1000e18);
        vm.prank(buyer);
        erc20.approve(address(venue), type(uint256).max);
    }

    /// Listing: 50 units of edition 7 at 1e18 per unit.
    function _listing(Medialane1155.ItemType payType, address payToken, uint256 pricePerUnit)
        internal
        view
        returns (Medialane1155.OrderParameters memory)
    {
        return Medialane1155.OrderParameters({
            offerer: seller,
            offer: Medialane1155.OfferItem(Medialane1155.ItemType.ERC1155, address(nft), 7, 50),
            consideration: Medialane1155.ConsiderationItem(payType, payToken, 0, pricePerUnit, seller),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: block.timestamp + 3600,
            salt: 42,
            counter: 0
        });
    }

    function _register(Medialane1155.OrderParameters memory params) internal returns (bytes32 orderHash) {
        orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
    }

    function test_fulfill_fullInOneCall() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(orderHash, seller, buyer, 50, 0, 50e18, address(0), 0);
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 50);
        assertEq(nft.balanceOf(buyer, 7), 50);
        assertEq(erc20.balanceOf(seller), 50e18);
        assertEq(uint8(venue.getOrderDetails(orderHash).status), uint8(Medialane1155.OrderStatus.Filled));
        assertEq(venue.getOrderDetails(orderHash).remainingAmount, 0);
    }

    function test_fulfill_twoPartialFills() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 20);
        Medialane1155.OrderDetails memory details = venue.getOrderDetails(orderHash);
        assertEq(uint8(details.status), uint8(Medialane1155.OrderStatus.Created));
        assertEq(details.remainingAmount, 30);
        assertEq(nft.balanceOf(buyer, 7), 20);
        assertEq(erc20.balanceOf(seller), 20e18);
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 30);
        details = venue.getOrderDetails(orderHash);
        assertEq(uint8(details.status), uint8(Medialane1155.OrderStatus.Filled));
        assertEq(details.remainingAmount, 0);
        assertEq(nft.balanceOf(buyer, 7), 50);
        assertEq(erc20.balanceOf(seller), 50e18);
    }

    function test_fulfill_overfillReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.InsufficientRemaining.selector);
        venue.fulfillOrder(orderHash, 51);
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 40);
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.InsufficientRemaining.selector);
        venue.fulfillOrder(orderHash, 11);
    }

    function test_fulfill_zeroQuantityReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.InvalidQuantity.selector);
        venue.fulfillOrder(orderHash, 0);
    }

    function test_fulfill_afterFullReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 50);
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.OrderAlreadyFilled.selector);
        venue.fulfillOrder(orderHash, 1);
    }

    function test_fulfill_nativePartialExactValue() public {
        nft.setRoyalty(royaltyReceiver, 500);
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.NATIVE, address(0), 1e18));
        vm.deal(buyer, 100e18);
        vm.prank(buyer);
        venue.fulfillOrder{value: 20e18}(orderHash, 20);
        assertEq(nft.balanceOf(buyer, 7), 20);
        assertEq(royaltyReceiver.balance, 1e18); // 5% of 20e18
        assertEq(seller.balance, 19e18);
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.WrongNativeValue.selector);
        venue.fulfillOrder{value: 5e18}(orderHash, 10);
    }

    function test_fulfill_erc20WithValueReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.deal(buyer, 1e18);
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.WrongNativeValue.selector);
        venue.fulfillOrder{value: 1e18}(orderHash, 10);
    }

    function test_fulfill_bidErc20Partial() public {
        uint256 bidderPk = 0xB0B;
        address bidder = vm.addr(bidderPk);
        Medialane1155.OrderParameters memory params = Medialane1155.OrderParameters({
            offerer: bidder,
            offer: Medialane1155.OfferItem(Medialane1155.ItemType.ERC20, address(erc20), 0, 2e18),
            consideration: Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC1155, address(nft), 7, 40, bidder),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: block.timestamp + 3600,
            salt: 43,
            counter: 0
        });
        erc20.mint(bidder, 80e18);
        vm.prank(bidder);
        erc20.approve(address(venue), type(uint256).max);
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bidderPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
        vm.prank(seller);
        venue.fulfillOrder(orderHash, 15);
        assertEq(nft.balanceOf(bidder, 7), 15);
        assertEq(erc20.balanceOf(seller), 30e18); // 15 units at 2e18/unit
        assertEq(venue.getOrderDetails(orderHash).remainingAmount, 25);
    }

    function test_fulfill_royaltyCappedPerFill() public {
        nft.setRoyalty(royaltyReceiver, 2000); // 20%, above the signed 10% cap
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 10);
        assertEq(erc20.balanceOf(royaltyReceiver), 1e18); // capped: 10% of 10e18
        assertEq(erc20.balanceOf(seller), 9e18);
    }

    function test_fulfill_selfFillReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(seller);
        vm.expectRevert(Medialane1155.SelfFill.selector);
        venue.fulfillOrder(orderHash, 1);
    }

    function test_fulfill_staleCounterAfterPartialReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 20);
        vm.prank(seller);
        venue.incrementCounter();
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.InvalidCounter.selector);
        venue.fulfillOrder(orderHash, 10);
    }

    function test_fulfill_expiryReverts() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 1e18));
        vm.warp(block.timestamp + 3601);
        vm.prank(buyer);
        vm.expectRevert(Medialane1155.OrderExpired.selector);
        venue.fulfillOrder(orderHash, 1);
    }

    function test_fulfill_freeOrder() public {
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), 0));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 50);
        assertEq(nft.balanceOf(buyer, 7), 50);
        assertEq(erc20.balanceOf(seller), 0);
    }

    function testFuzz_fulfill_partialSplitsConserve(uint96 pricePerUnit, uint8 firstQty) public {
        uint256 price = bound(uint256(pricePerUnit), 0, 1e24);
        uint256 first = bound(uint256(firstQty), 1, 49);
        nft.setRoyalty(royaltyReceiver, 700); // 7%, under the 10% cap
        erc20.mint(buyer, price * 50);
        bytes32 orderHash = _register(_listing(Medialane1155.ItemType.ERC20, address(erc20), price));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, first);
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 50 - first);
        assertEq(nft.balanceOf(buyer, 7), 50);
        uint256 total = erc20.balanceOf(royaltyReceiver) + erc20.balanceOf(seller);
        assertEq(total, price * 50);
        assertLe(erc20.balanceOf(royaltyReceiver), price * 50 * 1000 / 10_000);
    }

    function _armedEvilOrder(ReentrantERC1155.Action action) internal returns (ReentrantERC1155, bytes32) {
        ReentrantERC1155 evil = new ReentrantERC1155();
        uint256 evilSellerPk = 0xEE;
        address evilSeller = vm.addr(evilSellerPk);
        evil.mint(evilSeller, 1, 10);
        vm.prank(evilSeller);
        evil.setApprovalForAll(address(venue), true);
        Medialane1155.OrderParameters memory params = Medialane1155.OrderParameters({
            offerer: evilSeller,
            offer: Medialane1155.OfferItem(Medialane1155.ItemType.ERC1155, address(evil), 1, 10),
            consideration: Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC20, address(erc20), 0, 1e18, evilSeller),
            royaltyMaxBps: 0,
            startTime: block.timestamp,
            endTime: 0,
            salt: 1,
            counter: 0
        });
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(evilSellerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
        evil.armAction(venue, orderHash, action);
        return (evil, orderHash);
    }

    function test_fulfill_fulfillDuringSettlementBlocked() public {
        (, bytes32 orderHash) = _armedEvilOrder(ReentrantERC1155.Action.Fulfill);
        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        venue.fulfillOrder(orderHash, 5);
    }

    function test_fulfill_registerDuringSettlementBlocked() public {
        (, bytes32 orderHash) = _armedEvilOrder(ReentrantERC1155.Action.Register);
        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        venue.fulfillOrder(orderHash, 5);
    }

    function test_fulfill_cancelDuringSettlementBlocked() public {
        (, bytes32 orderHash) = _armedEvilOrder(ReentrantERC1155.Action.Cancel);
        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        venue.fulfillOrder(orderHash, 5);
    }

    function _brokenRoyaltyFill(BrokenRoyaltyERC1155.Mode mode) internal {
        BrokenRoyaltyERC1155 broken = new BrokenRoyaltyERC1155();
        broken.setMode(mode);
        uint256 brokenSellerPk = 0xB0B;
        address brokenSeller = vm.addr(brokenSellerPk);
        broken.mint(brokenSeller, 1, 10);
        vm.prank(brokenSeller);
        broken.setApprovalForAll(address(venue), true);
        Medialane1155.OrderParameters memory params = Medialane1155.OrderParameters({
            offerer: brokenSeller,
            offer: Medialane1155.OfferItem(Medialane1155.ItemType.ERC1155, address(broken), 1, 10),
            consideration: Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC20, address(erc20), 0, 1e18, brokenSeller),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: 0,
            salt: 2,
            counter: 0
        });
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(brokenSellerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash, 10);
        // Broken royalty never blocks a fill; the seller keeps the full amount.
        assertEq(broken.balanceOf(buyer, 1), 10);
        assertEq(erc20.balanceOf(brokenSeller), 10e18);
    }

    function test_fulfill_brokenRoyaltyReverting() public {
        _brokenRoyaltyFill(BrokenRoyaltyERC1155.Mode.Revert);
    }

    function test_fulfill_brokenRoyaltyShortReturn() public {
        _brokenRoyaltyFill(BrokenRoyaltyERC1155.Mode.ShortReturn);
    }

    function test_fulfill_brokenRoyaltyBadReceiver() public {
        _brokenRoyaltyFill(BrokenRoyaltyERC1155.Mode.BadReceiver);
    }
}
