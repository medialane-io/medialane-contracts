// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Medialane721} from "../src/Medialane721.sol";
import {BrokenRoyaltyERC721} from "./mocks/BrokenRoyaltyERC721.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {ReentrantERC721} from "./mocks/ReentrantERC721.sol";

contract Medialane721FulfillTest is Test {
    Medialane721 internal venue;
    MockERC20 internal erc20;
    MockERC721 internal nft;
    uint256 internal sellerPk = 0xA11CE;
    address internal seller;
    address internal buyer = makeAddr("buyer");
    address internal royaltyReceiver = makeAddr("royalties");

    event OrderFulfilled(
        bytes32 indexed orderHash,
        address indexed offerer,
        address indexed fulfiller,
        uint256 saleAmount,
        address royaltyReceiver,
        uint256 royaltyAmount
    );

    function setUp() public {
        venue = new Medialane721();
        erc20 = new MockERC20();
        nft = new MockERC721();
        seller = vm.addr(sellerPk);
        vm.warp(1_000_000_000);
        nft.mint(seller, 7);
        vm.prank(seller);
        nft.setApprovalForAll(address(venue), true);
        erc20.mint(buyer, 100e18);
        vm.prank(buyer);
        erc20.approve(address(venue), type(uint256).max);
    }

    function _listing(Medialane721.ItemType payType, address payToken, uint256 price)
        internal
        view
        returns (Medialane721.OrderParameters memory)
    {
        return Medialane721.OrderParameters({
            offerer: seller,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, address(nft), 7, 1),
            consideration: Medialane721.ConsiderationItem(payType, payToken, 0, price, seller),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: block.timestamp + 3600,
            salt: 42,
            counter: 0
        });
    }

    function _register(Medialane721.OrderParameters memory params) internal returns (bytes32 orderHash) {
        orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
    }

    function test_fulfill_listingErc20_noRoyalty() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(orderHash, seller, buyer, 10e18, address(0), 0);
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        assertEq(nft.ownerOf(7), buyer);
        assertEq(erc20.balanceOf(seller), 10e18);
        assertEq(uint8(venue.getOrderDetails(orderHash).status), uint8(Medialane721.OrderStatus.Filled));
    }

    function test_fulfill_listingErc20_royaltyCapped() public {
        nft.setRoyalty(royaltyReceiver, 2000); // 20%, above the signed 10% cap
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        assertEq(erc20.balanceOf(royaltyReceiver), 1e18); // capped at 10%
        assertEq(erc20.balanceOf(seller), 9e18);
    }

    function test_fulfill_listingErc20_royaltyUnderCap() public {
        nft.setRoyalty(royaltyReceiver, 500); // 5%, under the 10% cap
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        assertEq(erc20.balanceOf(royaltyReceiver), 0.5e18);
        assertEq(erc20.balanceOf(seller), 9.5e18);
    }

    function test_fulfill_listingNative() public {
        nft.setRoyalty(royaltyReceiver, 500);
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.NATIVE, address(0), 10e18));
        vm.deal(buyer, 10e18);
        vm.prank(buyer);
        venue.fulfillOrder{value: 10e18}(orderHash);
        assertEq(nft.ownerOf(7), buyer);
        assertEq(seller.balance, 9.5e18);
        assertEq(royaltyReceiver.balance, 0.5e18);
    }

    function test_fulfill_listingNative_wrongValueReverts() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.NATIVE, address(0), 10e18));
        vm.deal(buyer, 10e18);
        vm.prank(buyer);
        vm.expectRevert(Medialane721.WrongNativeValue.selector);
        venue.fulfillOrder{value: 9e18}(orderHash);
    }

    function test_fulfill_erc20WithValueReverts() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.deal(buyer, 1e18);
        vm.prank(buyer);
        vm.expectRevert(Medialane721.WrongNativeValue.selector);
        venue.fulfillOrder{value: 1e18}(orderHash);
    }

    function test_fulfill_bidErc20() public {
        // Bid: bidder signs a payment-side order; the NFT holder fulfills.
        uint256 bidderPk = 0xB0B;
        address bidder = vm.addr(bidderPk);
        Medialane721.OrderParameters memory params = Medialane721.OrderParameters({
            offerer: bidder,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC20, address(erc20), 0, 10e18),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC721, address(nft), 7, 1, bidder),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: block.timestamp + 3600,
            salt: 43,
            counter: 0
        });
        erc20.mint(bidder, 10e18);
        vm.prank(bidder);
        erc20.approve(address(venue), type(uint256).max);
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bidderPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
        vm.prank(seller);
        venue.fulfillOrder(orderHash);
        assertEq(nft.ownerOf(7), bidder);
        assertEq(erc20.balanceOf(seller), 10e18);
    }

    function test_fulfill_selfFillReverts() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.prank(seller);
        vm.expectRevert(Medialane721.SelfFill.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_fulfill_beforeStartReverts() public {
        Medialane721.OrderParameters memory params = _listing(Medialane721.ItemType.ERC20, address(erc20), 10e18);
        params.startTime = block.timestamp + 100;
        bytes32 orderHash = _register(params);
        vm.prank(buyer);
        vm.expectRevert(Medialane721.OrderNotYetValid.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_fulfill_afterExpiryReverts() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.warp(block.timestamp + 3601);
        vm.prank(buyer);
        vm.expectRevert(Medialane721.OrderExpired.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_fulfill_twiceReverts() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        vm.prank(buyer);
        vm.expectRevert(Medialane721.OrderAlreadyFilled.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_fulfill_unknownHashReverts() public {
        vm.prank(buyer);
        vm.expectRevert(Medialane721.OrderNotFound.selector);
        venue.fulfillOrder(bytes32(uint256(0xDEAD)));
    }

    function test_fulfill_staleCounterReverts() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 10e18));
        vm.prank(seller);
        venue.incrementCounter();
        vm.prank(buyer);
        vm.expectRevert(Medialane721.InvalidCounter.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_fulfill_reentrancyBlocked() public {
        ReentrantERC721 evil = new ReentrantERC721();
        uint256 evilSellerPk = 0xEE;
        address evilSeller = vm.addr(evilSellerPk);
        evil.mint(evilSeller, 1);
        vm.prank(evilSeller);
        evil.setApprovalForAll(address(venue), true);
        Medialane721.OrderParameters memory params = Medialane721.OrderParameters({
            offerer: evilSeller,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, address(evil), 1, 1),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC20, address(erc20), 0, 1e18, evilSeller),
            royaltyMaxBps: 0,
            startTime: block.timestamp,
            endTime: 0,
            salt: 1,
            counter: 0
        });
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(evilSellerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
        evil.arm(venue, orderHash);
        vm.prank(buyer);
        vm.expectRevert(); // re-entered call hits the guard; outer transfer reverts
        venue.fulfillOrder(orderHash);
    }

    function _armedEvilOrder(ReentrantERC721.Action action) internal returns (ReentrantERC721, bytes32) {
        ReentrantERC721 evil = new ReentrantERC721();
        uint256 evilSellerPk = 0xEE;
        address evilSeller = vm.addr(evilSellerPk);
        evil.mint(evilSeller, 1);
        vm.prank(evilSeller);
        evil.setApprovalForAll(address(venue), true);
        Medialane721.OrderParameters memory params = Medialane721.OrderParameters({
            offerer: evilSeller,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, address(evil), 1, 1),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC20, address(erc20), 0, 1e18, evilSeller),
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

    function test_fulfill_registerDuringSettlementBlocked() public {
        (, bytes32 orderHash) = _armedEvilOrder(ReentrantERC721.Action.Register);
        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_fulfill_cancelDuringSettlementBlocked() public {
        (, bytes32 orderHash) = _armedEvilOrder(ReentrantERC721.Action.Cancel);
        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        venue.fulfillOrder(orderHash);
    }

    function _brokenRoyaltyFill(BrokenRoyaltyERC721.Mode mode) internal {
        BrokenRoyaltyERC721 broken = new BrokenRoyaltyERC721();
        broken.setMode(mode);
        uint256 brokenSellerPk = 0xB0B;
        address brokenSeller = vm.addr(brokenSellerPk);
        broken.mint(brokenSeller, 1);
        vm.prank(brokenSeller);
        broken.setApprovalForAll(address(venue), true);
        Medialane721.OrderParameters memory params = Medialane721.OrderParameters({
            offerer: brokenSeller,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, address(broken), 1, 1),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC20, address(erc20), 0, 10e18, brokenSeller),
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
        venue.fulfillOrder(orderHash);
        // Broken royalty never blocks a fill; the seller keeps the full amount.
        assertEq(broken.ownerOf(1), buyer);
        assertEq(erc20.balanceOf(brokenSeller), 10e18);
    }

    function test_fulfill_brokenRoyaltyReverting() public {
        _brokenRoyaltyFill(BrokenRoyaltyERC721.Mode.Revert);
    }

    function test_fulfill_brokenRoyaltyShortReturn() public {
        _brokenRoyaltyFill(BrokenRoyaltyERC721.Mode.ShortReturn);
    }

    function test_fulfill_brokenRoyaltyBadReceiver() public {
        _brokenRoyaltyFill(BrokenRoyaltyERC721.Mode.BadReceiver);
    }

    function test_fulfill_freeOrder() public {
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), 0));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        assertEq(nft.ownerOf(7), buyer);
        assertEq(erc20.balanceOf(seller), 0);
    }

    function testFuzz_fulfill_royaltyNeverExceedsCap(uint96 royaltyBps, uint256 price) public {
        royaltyBps = uint96(bound(royaltyBps, 0, 10_000));
        price = bound(price, 0, 1e30);
        if (royaltyBps > 0) nft.setRoyalty(royaltyReceiver, royaltyBps);
        erc20.mint(buyer, price);
        bytes32 orderHash = _register(_listing(Medialane721.ItemType.ERC20, address(erc20), price));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        assertLe(erc20.balanceOf(royaltyReceiver), price * 1000 / 10_000);
        assertEq(erc20.balanceOf(royaltyReceiver) + erc20.balanceOf(seller), price);
    }
}
