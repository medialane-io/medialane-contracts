// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Minimal contract simulating a Gnosis Safe treasury for tests.
contract MockSafe {
    function transfer(address token, address to, uint256 amount) external {
        (bool ok,) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(ok, "transfer failed");
    }
}
