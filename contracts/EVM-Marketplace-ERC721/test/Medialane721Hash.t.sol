// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Medialane721} from "../src/Medialane721.sol";

contract Medialane721HashTest is Test {
    Medialane721 internal venue;

    function setUp() public {
        venue = new Medialane721();
    }

    function _sampleOrder() internal view returns (Medialane721.OrderParameters memory) {
        return Medialane721.OrderParameters({
            offerer: address(0x111),
            offer: Medialane721.OfferItem({
                itemType: Medialane721.ItemType.ERC721,
                token: address(0x721),
                identifier: 7,
                amount: 1
            }),
            consideration: Medialane721.ConsiderationItem({
                itemType: Medialane721.ItemType.ERC20,
                token: address(0x20),
                identifier: 0,
                amount: 1_000_000,
                recipient: address(0x111)
            }),
            royaltyMaxBps: 1000,
            startTime: 1_000_000_000,
            endTime: 1_000_003_600,
            salt: 42,
            counter: 0
        });
    }

    function test_orderHash_isDeterministic() public view {
        assertEq(venue.getOrderHash(_sampleOrder()), venue.getOrderHash(_sampleOrder()));
    }

    function test_orderHash_bindsDeployment() public {
        Medialane721 other = new Medialane721();
        assertTrue(venue.getOrderHash(_sampleOrder()) != other.getOrderHash(_sampleOrder()));
    }

    function test_orderHash_bindsChainId() public {
        bytes32 initial = venue.getOrderHash(_sampleOrder());
        vm.chainId(8453);
        assertTrue(venue.getOrderHash(_sampleOrder()) != initial);
    }

    function test_orderHash_changesWithSalt() public view {
        Medialane721.OrderParameters memory a = _sampleOrder();
        Medialane721.OrderParameters memory b = _sampleOrder();
        b.salt = 43;
        assertTrue(venue.getOrderHash(a) != venue.getOrderHash(b));
    }

    function test_version() public view {
        assertEq(venue.version(), "1.0.0");
    }
}
