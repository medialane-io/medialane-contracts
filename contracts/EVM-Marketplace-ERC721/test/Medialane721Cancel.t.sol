// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Medialane721} from "../src/Medialane721.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {ERC1271Wallet} from "./mocks/ERC1271Wallet.sol";

contract Medialane721CancelTest is Test {
    Medialane721 internal venue;
    MockERC20 internal erc20;
    MockERC721 internal nft;
    uint256 internal sellerPk = 0xA11CE;
    address internal seller;
    address internal buyer = makeAddr("buyer");

    event OrderCancelled(bytes32 indexed orderHash, address indexed offerer);
    event CounterIncremented(address indexed offerer, uint256 newCounter);

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

    function _listing(uint256 salt) internal view returns (Medialane721.OrderParameters memory) {
        return Medialane721.OrderParameters({
            offerer: seller,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, address(nft), 7, 1),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC20, address(erc20), 0, 10e18, seller),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: 0,
            salt: salt,
            counter: 0
        });
    }

    function _register(Medialane721.OrderParameters memory params) internal returns (bytes32 orderHash) {
        orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
    }

    function test_cancel_byOfferer() public {
        bytes32 orderHash = _register(_listing(1));
        vm.expectEmit(true, true, false, true);
        emit OrderCancelled(orderHash, seller);
        vm.prank(seller);
        venue.cancelOrder(orderHash);
        assertEq(uint8(venue.getOrderDetails(orderHash).status), uint8(Medialane721.OrderStatus.Cancelled));
        vm.prank(buyer);
        vm.expectRevert(Medialane721.OrderCancelledError.selector);
        venue.fulfillOrder(orderHash);
    }

    function test_cancel_byOtherReverts() public {
        bytes32 orderHash = _register(_listing(1));
        vm.prank(buyer);
        vm.expectRevert(Medialane721.CallerNotOfferer.selector);
        venue.cancelOrder(orderHash);
    }

    function test_cancel_unknownReverts() public {
        vm.prank(seller);
        vm.expectRevert(Medialane721.OrderNotFound.selector);
        venue.cancelOrder(bytes32(uint256(1)));
    }

    function test_cancel_filledReverts() public {
        bytes32 orderHash = _register(_listing(1));
        vm.prank(buyer);
        venue.fulfillOrder(orderHash);
        vm.prank(seller);
        vm.expectRevert(Medialane721.OrderAlreadyFilled.selector);
        venue.cancelOrder(orderHash);
    }

    function test_incrementCounter_emitsAndInvalidatesRegistration() public {
        vm.expectEmit(true, false, false, true);
        emit CounterIncremented(seller, 1);
        vm.prank(seller);
        venue.incrementCounter();
        assertEq(venue.getCounter(seller), 1);
        // An order signed under counter 0 can no longer register.
        Medialane721.OrderParameters memory params = _listing(2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, venue.getOrderHash(params));
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.expectRevert(Medialane721.InvalidCounter.selector);
        venue.registerOrder(params, sig);
    }

    function test_erc1271_registerAndCancel() public {
        uint256 walletOwnerPk = 0xC0FFEE;
        ERC1271Wallet wallet = new ERC1271Wallet(vm.addr(walletOwnerPk));
        nft.mint(address(wallet), 8);
        Medialane721.OrderParameters memory params = _listing(3);
        params.offerer = address(wallet);
        params.offer.identifier = 8;
        params.consideration.recipient = address(wallet);
        bytes32 orderHash = venue.getOrderHash(params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletOwnerPk, orderHash);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
        assertEq(uint8(venue.getOrderDetails(orderHash).status), uint8(Medialane721.OrderStatus.Created));
        vm.prank(address(wallet));
        venue.cancelOrder(orderHash);
        assertEq(uint8(venue.getOrderDetails(orderHash).status), uint8(Medialane721.OrderStatus.Cancelled));
    }
}
