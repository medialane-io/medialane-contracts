// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Medialane1155} from "../src/Medialane1155.sol";

contract Medialane1155RegisterTest is Test {
    Medialane1155 internal venue;
    uint256 internal offererPk = 0xA11CE;
    address internal offerer;
    address internal nft = address(0x1155);
    address internal erc20 = address(0x20);

    event OrderCreated(bytes32 indexed orderHash, address indexed offerer);

    function setUp() public {
        venue = new Medialane1155();
        offerer = vm.addr(offererPk);
        vm.warp(1_000_000_000);
    }

    /// Listing: 50 units of edition 7 at 1e18 per unit.
    function _listing() internal view returns (Medialane1155.OrderParameters memory) {
        return Medialane1155.OrderParameters({
            offerer: offerer,
            offer: Medialane1155.OfferItem(Medialane1155.ItemType.ERC1155, nft, 7, 50),
            consideration: Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC20, erc20, 0, 1e18, offerer),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: block.timestamp + 3600,
            salt: 42,
            counter: 0
        });
    }

    function _sign(Medialane1155.OrderParameters memory params) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offererPk, venue.getOrderHash(params));
        return abi.encodePacked(r, s, v);
    }

    function test_hash_deterministicAndSaltSensitive() public view {
        Medialane1155.OrderParameters memory a = _listing();
        Medialane1155.OrderParameters memory b = _listing();
        assertEq(venue.getOrderHash(a), venue.getOrderHash(b));
        b.salt = 43;
        assertTrue(venue.getOrderHash(a) != venue.getOrderHash(b));
    }

    function test_hash_bindsDeployment() public {
        Medialane1155 other = new Medialane1155();
        assertTrue(venue.getOrderHash(_listing()) != other.getOrderHash(_listing()));
    }

    function test_register_listingSeedsRemaining() public {
        Medialane1155.OrderParameters memory params = _listing();
        bytes32 orderHash = venue.getOrderHash(params);
        vm.expectEmit(true, true, false, true);
        emit OrderCreated(orderHash, offerer);
        venue.registerOrder(params, _sign(params));
        Medialane1155.OrderDetails memory details = venue.getOrderDetails(orderHash);
        assertEq(uint8(details.status), uint8(Medialane1155.OrderStatus.Created));
        assertEq(details.remainingAmount, 50);
        assertEq(details.consideration.amount, 1e18);
    }

    function test_register_bidSeedsRemainingFromConsideration() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.offer = Medialane1155.OfferItem(Medialane1155.ItemType.ERC20, erc20, 0, 1e18);
        params.consideration = Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC1155, nft, 7, 30, offerer);
        venue.registerOrder(params, _sign(params));
        assertEq(venue.getOrderDetails(venue.getOrderHash(params)).remainingAmount, 30);
    }

    function test_register_nativeListingAllowed() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.consideration = Medialane1155.ConsiderationItem(Medialane1155.ItemType.NATIVE, address(0), 0, 1e18, offerer);
        venue.registerOrder(params, _sign(params));
    }

    function test_register_rejectsNativeBid() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.offer = Medialane1155.OfferItem(Medialane1155.ItemType.NATIVE, address(0), 0, 1e18);
        params.consideration = Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC1155, nft, 7, 30, offerer);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.NativeBidUnsupported.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsZeroUnits() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.offer.amount = 0;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.InvalidAmount.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsWrongCounter() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.counter = 5;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.InvalidCounter.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsRoyaltyOver100Pct() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.royaltyMaxBps = 10_001;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.RoyaltyBpsTooHigh.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsPaymentIdentifier() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.consideration.identifier = 9;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.InvalidIdentifier.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsZeroRecipient() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.consideration.recipient = address(0);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.InvalidRecipient.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsNftAsPaymentToken() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.consideration.token = nft;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.PaymentTokenIsNft.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejects1155BothSides() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.consideration = Medialane1155.ConsiderationItem(Medialane1155.ItemType.ERC1155, nft, 7, 1, offerer);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.UnsupportedShape.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsInvertedWindow() public {
        Medialane1155.OrderParameters memory params = _listing();
        params.endTime = params.startTime - 1;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.InvalidTimeWindow.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsExpired() public {
        Medialane1155.OrderParameters memory params = _listing();
        vm.warp(params.endTime + 1);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane1155.OrderExpired.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsDuplicate() public {
        Medialane1155.OrderParameters memory params = _listing();
        bytes memory sig = _sign(params);
        venue.registerOrder(params, sig);
        vm.expectRevert(Medialane1155.OrderAlreadyExists.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsBadSignature() public {
        Medialane1155.OrderParameters memory params = _listing();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, venue.getOrderHash(params));
        vm.expectRevert(Medialane1155.InvalidSignature.selector);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
    }

    function test_register_rejectsTamperedParams() public {
        Medialane1155.OrderParameters memory params = _listing();
        bytes memory sig = _sign(params);
        params.consideration.amount = 1;
        vm.expectRevert(Medialane1155.InvalidSignature.selector);
        venue.registerOrder(params, sig);
    }

    function test_version() public view {
        assertEq(venue.version(), "1.0.0");
    }
}
