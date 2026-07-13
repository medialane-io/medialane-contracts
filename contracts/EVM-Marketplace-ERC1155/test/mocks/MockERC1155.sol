// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract MockERC1155 is ERC1155, ERC2981 {
    bool private _royaltyEnabled;

    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 value) external {
        _mint(to, id, value, "");
    }

    function setRoyalty(address receiver, uint96 bps) external {
        _royaltyEnabled = true;
        _setDefaultRoyalty(receiver, bps);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, ERC2981) returns (bool) {
        if (interfaceId == type(IERC2981).interfaceId && !_royaltyEnabled) return false;
        return super.supportsInterface(interfaceId);
    }
}
