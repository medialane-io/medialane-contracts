// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Medialane721} from "../src/Medialane721.sol";

contract Medialane721RegisterTest is Test {
    Medialane721 internal venue;
    uint256 internal offererPk = 0xA11CE;
    address internal offerer;
    address internal nft = address(0x721);
    address internal erc20 = address(0x20);

    event OrderCreated(bytes32 indexed orderHash, address indexed offerer);

    function setUp() public {
        venue = new Medialane721();
        offerer = vm.addr(offererPk);
        vm.warp(1_000_000_000);
    }

    function _listing() internal view returns (Medialane721.OrderParameters memory) {
        return Medialane721.OrderParameters({
            offerer: offerer,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, nft, 7, 1),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC20, erc20, 0, 1e18, offerer),
            royaltyMaxBps: 1000,
            startTime: block.timestamp,
            endTime: block.timestamp + 3600,
            salt: 42,
            counter: 0
        });
    }

    function _sign(Medialane721.OrderParameters memory params) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offererPk, venue.getOrderHash(params));
        return abi.encodePacked(r, s, v);
    }

    function test_register_validListing() public {
        Medialane721.OrderParameters memory params = _listing();
        bytes32 orderHash = venue.getOrderHash(params);
        vm.expectEmit(true, true, false, true);
        emit OrderCreated(orderHash, offerer);
        venue.registerOrder(params, _sign(params));
        Medialane721.OrderDetails memory details = venue.getOrderDetails(orderHash);
        assertEq(uint8(details.status), uint8(Medialane721.OrderStatus.Created));
        assertEq(details.offerer, offerer);
        assertEq(details.consideration.amount, 1e18);
    }

    function test_register_validBidErc20() public {
        Medialane721.OrderParameters memory params = _listing();
        params.offer = Medialane721.OfferItem(Medialane721.ItemType.ERC20, erc20, 0, 1e18);
        params.consideration = Medialane721.ConsiderationItem(Medialane721.ItemType.ERC721, nft, 7, 1, offerer);
        venue.registerOrder(params, _sign(params));
        assertEq(uint8(venue.getOrderDetails(venue.getOrderHash(params)).status), uint8(Medialane721.OrderStatus.Created));
    }

    function test_register_validNativeListing() public {
        Medialane721.OrderParameters memory params = _listing();
        params.consideration = Medialane721.ConsiderationItem(Medialane721.ItemType.NATIVE, address(0), 0, 1e18, offerer);
        venue.registerOrder(params, _sign(params));
    }

    function test_register_rejectsNativeBid() public {
        Medialane721.OrderParameters memory params = _listing();
        params.offer = Medialane721.OfferItem(Medialane721.ItemType.NATIVE, address(0), 0, 1e18);
        params.consideration = Medialane721.ConsiderationItem(Medialane721.ItemType.ERC721, nft, 7, 1, offerer);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.NativeBidUnsupported.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsWrongCounter() public {
        Medialane721.OrderParameters memory params = _listing();
        params.counter = 5;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.InvalidCounter.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsRoyaltyOver100Pct() public {
        Medialane721.OrderParameters memory params = _listing();
        params.royaltyMaxBps = 10_001;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.RoyaltyBpsTooHigh.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsNftAmountNotOne() public {
        Medialane721.OrderParameters memory params = _listing();
        params.offer.amount = 2;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.InvalidAmount.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsNativeWithTokenAddress() public {
        Medialane721.OrderParameters memory params = _listing();
        params.consideration = Medialane721.ConsiderationItem(Medialane721.ItemType.NATIVE, erc20, 0, 1e18, offerer);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.NonzeroNativeToken.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsPaymentIdentifier() public {
        Medialane721.OrderParameters memory params = _listing();
        params.consideration.identifier = 9;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.InvalidIdentifier.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsZeroRecipient() public {
        Medialane721.OrderParameters memory params = _listing();
        params.consideration.recipient = address(0);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.InvalidRecipient.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsNftAsPaymentToken() public {
        Medialane721.OrderParameters memory params = _listing();
        params.consideration.token = nft;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.PaymentTokenIsNft.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsErc721BothSides() public {
        Medialane721.OrderParameters memory params = _listing();
        params.consideration = Medialane721.ConsiderationItem(Medialane721.ItemType.ERC721, nft, 7, 1, offerer);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.UnsupportedShape.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsInvertedWindow() public {
        Medialane721.OrderParameters memory params = _listing();
        params.endTime = params.startTime - 1;
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.InvalidTimeWindow.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsExpired() public {
        Medialane721.OrderParameters memory params = _listing();
        vm.warp(params.endTime + 1);
        bytes memory sig = _sign(params);
        vm.expectRevert(Medialane721.OrderExpired.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_allowsNoExpiry() public {
        Medialane721.OrderParameters memory params = _listing();
        params.endTime = 0;
        venue.registerOrder(params, _sign(params));
    }

    function test_register_rejectsDuplicate() public {
        Medialane721.OrderParameters memory params = _listing();
        bytes memory sig = _sign(params);
        venue.registerOrder(params, sig);
        vm.expectRevert(Medialane721.OrderAlreadyExists.selector);
        venue.registerOrder(params, sig);
    }

    function test_register_rejectsBadSignature() public {
        Medialane721.OrderParameters memory params = _listing();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, venue.getOrderHash(params));
        vm.expectRevert(Medialane721.InvalidSignature.selector);
        venue.registerOrder(params, abi.encodePacked(r, s, v));
    }

    function test_register_rejectsTamperedParams() public {
        Medialane721.OrderParameters memory params = _listing();
        bytes memory sig = _sign(params);
        params.consideration.amount = 1;
        vm.expectRevert(Medialane721.InvalidSignature.selector);
        venue.registerOrder(params, sig);
    }
}
