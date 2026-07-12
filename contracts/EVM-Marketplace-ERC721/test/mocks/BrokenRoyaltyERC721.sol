// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/// An ERC721 that advertises ERC-2981 but misbehaves when royaltyInfo is
/// called, per the configured mode. A broken royalty implementation must
/// never block a fill.
contract BrokenRoyaltyERC721 is ERC721 {
    enum Mode {
        Revert,
        ShortReturn,
        BadReceiver
    }

    Mode public mode;

    constructor() ERC721("Broken", "BRK") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        if (bytes4(data) == IERC2981.royaltyInfo.selector) {
            if (mode == Mode.Revert) revert("royalty broken");
            if (mode == Mode.ShortReturn) return abi.encodePacked(uint128(1));
            // BadReceiver: first word is not a clean address (high bits set).
            return abi.encode(type(uint256).max, uint256(100));
        }
        revert("unknown call");
    }
}
