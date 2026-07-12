// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Medialane721} from "../src/Medialane721.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

/// Drives random register/fulfill/cancel/incrementCounter sequences and checks
/// the venue's conservation properties.
contract VenueHandler is Test {
    Medialane721 public venue;
    MockERC20 public erc20;
    MockERC721 public nft;
    uint256 internal sellerPk = 0xA11CE;
    address public seller;
    address public buyer = address(0xB0B1);
    bytes32[] public hashes;
    uint256 public fills;
    uint256 public nextTokenId = 1;

    constructor(Medialane721 venue_, MockERC20 erc20_, MockERC721 nft_) {
        venue = venue_;
        erc20 = erc20_;
        nft = nft_;
        seller = vm.addr(sellerPk);
        vm.prank(seller);
        nft.setApprovalForAll(address(venue), true);
        vm.prank(buyer);
        erc20.approve(address(venue), type(uint256).max);
    }

    function register(uint96 price) external {
        uint256 tokenId = nextTokenId++;
        nft.mint(seller, tokenId);
        Medialane721.OrderParameters memory params = Medialane721.OrderParameters({
            offerer: seller,
            offer: Medialane721.OfferItem(Medialane721.ItemType.ERC721, address(nft), tokenId, 1),
            consideration: Medialane721.ConsiderationItem(Medialane721.ItemType.ERC20, address(erc20), 0, price, seller),
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
        } catch {}
    }

    function fulfill(uint256 index) external {
        if (hashes.length == 0) return;
        bytes32 orderHash = hashes[index % hashes.length];
        uint256 price = venue.getOrderDetails(orderHash).consideration.amount;
        erc20.mint(buyer, price);
        vm.prank(buyer);
        try venue.fulfillOrder(orderHash) {
            fills++;
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

contract Medialane721InvariantTest is Test {
    Medialane721 internal venue;
    MockERC20 internal erc20;
    MockERC721 internal nft;
    VenueHandler internal handler;

    function setUp() public {
        vm.warp(1_000_000_000);
        venue = new Medialane721();
        erc20 = new MockERC20();
        nft = new MockERC721();
        handler = new VenueHandler(venue, erc20, nft);
        targetContract(address(handler));
    }

    /// Every fill moved exactly one NFT to the buyer: fills == buyer's NFT
    /// balance, and no order is ever double-filled.
    function invariant_fillsMatchBuyerNftBalance() public view {
        assertEq(nft.balanceOf(handler.buyer()), handler.fills());
    }

    /// Registered orders are only ever in a defined status.
    function invariant_statusesAreTerminalOrCreated() public view {
        for (uint256 i = 0; i < handler.hashCount(); i++) {
            uint8 status = uint8(venue.getOrderDetails(handler.hashes(i)).status);
            assertTrue(status >= 1 && status <= 3);
        }
    }
}
