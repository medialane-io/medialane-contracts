// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Medialane1155} from "../../src/Medialane1155.sol";

/// An ERC1155 that re-enters the venue from inside its transfer, per the
/// configured action. Lifecycle mutations must be blocked during settlement.
contract ReentrantERC1155 is ERC1155 {
    enum Action {
        Fulfill,
        Register,
        Cancel
    }

    Medialane1155 public venue;
    bytes32 public target;
    Action public action;
    bool public reentered;

    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 value) external {
        _mint(to, id, value, "");
    }

    function armAction(Medialane1155 venue_, bytes32 target_, Action action_) external {
        venue = venue_;
        target = target_;
        action = action_;
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override
    {
        if (address(venue) != address(0) && !reentered) {
            reentered = true;
            if (action == Action.Fulfill) {
                venue.fulfillOrder(target, 1);
            } else if (action == Action.Register) {
                Medialane1155.OrderParameters memory params;
                venue.registerOrder(params, "");
            } else {
                venue.cancelOrder(target);
            }
        }
        super._update(from, to, ids, values);
    }
}
