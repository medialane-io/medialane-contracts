// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Medialane721} from "../../src/Medialane721.sol";

contract ReentrantERC721 is ERC721 {
    enum Action {
        Fulfill,
        Register,
        Cancel
    }

    Medialane721 public venue;
    bytes32 public target;
    Action public action;
    bool public reentered;

    constructor() ERC721("Evil", "EVIL") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function arm(Medialane721 venue_, bytes32 target_) external {
        venue = venue_;
        target = target_;
        action = Action.Fulfill;
    }

    function armAction(Medialane721 venue_, bytes32 target_, Action action_) external {
        venue = venue_;
        target = target_;
        action = action_;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (address(venue) != address(0) && !reentered) {
            reentered = true;
            if (action == Action.Fulfill) {
                venue.fulfillOrder(target);
            } else if (action == Action.Register) {
                Medialane721.OrderParameters memory params;
                venue.registerOrder(params, "");
            } else {
                venue.cancelOrder(target);
            }
        }
        return super._update(to, tokenId, auth);
    }
}
