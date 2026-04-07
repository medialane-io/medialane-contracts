// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// OpenZeppelin Contracts v5
// https://github.com/OpenZeppelin/openzeppelin-contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title MedialaneToken
 * @notice Governance and utility token for the Medialane DAO.
 *
 * Symbol  : MDLN
 * Supply  : 21,000,000 (fixed — no further minting)
 * Chain   : Ethereum mainnet (L1)
 * Bridge  : StarkGate → Starknet (wrapped MDLN for on-chain liquidity)
 * Governance: Snapshot (off-chain, EIP-712 signatures over MDLN balances)
 *
 * Design decisions:
 *  - Fixed supply minted once to a Gnosis Safe DAO treasury.
 *    The treasury multisig distributes tokens per the DAO tokenomics
 *    (community, team vesting, ecosystem grants, liquidity).
 *  - No owner, no admin, no pause, no upgrade. Immutable after deploy.
 *    This maximises credibility for DAO governance compliance (Utah DAO LLC).
 *  - ERC20Permit (EIP-2612): gasless approvals — required by StarkGate and
 *    most modern DeFi protocols.
 *  - ERC20Votes: on-chain voting weight snapshots + delegation. Enables
 *    future migration to an on-chain Governor (e.g. OpenZeppelin Governor)
 *    without a token migration.
 *  - ERC20Burnable: token holders can permanently reduce supply.
 *    Intended for fee-burn mechanics governed by Snapshot vote.
 *  - Vote checkpoints use block numbers (Ethereum L1 default). Timestamp-based
 *    clocks are not needed here — block times on L1 are stable (~12s).
 *
 * Deployment:
 *  1. Deploy a Gnosis Safe with your team as signers (recommend 3-of-5).
 *  2. Pass the Safe address as `treasury` to this constructor.
 *  3. Verify on Etherscan — the Safe becomes sole initial holder.
 *  4. Register the deployed address on StarkGate for L2 bridging.
 *  5. Create a Snapshot space pointing at this contract address.
 */
contract MedialaneToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes {

    /// @notice The total and maximum supply — minted once, never increased.
    uint256 public constant TOTAL_SUPPLY = 21_000_000 * 10 ** 18; // 21M MDLN

    /// @notice Treasury address is zero.
    error MDLN_ZeroAddress();
    /// @notice Treasury must be a contract (Gnosis Safe), not an EOA.
    error MDLN_TreasuryNotContract();

    /**
     * @param treasury Gnosis Safe address that receives the full initial supply.
     *                 Must be a deployed contract — an EOA is rejected.
     */
    constructor(address treasury)
        ERC20("Medialane", "MDLN")
        ERC20Permit("Medialane")
    {
        if (treasury == address(0)) revert MDLN_ZeroAddress();
        if (treasury.code.length == 0) revert MDLN_TreasuryNotContract();
        _mint(treasury, TOTAL_SUPPLY);
    }

    // ─── Required overrides (ERC20Votes + ERC20) ─────────────────────────────

    /**
     * @dev Hook called on every transfer, mint and burn.
     *      ERC20Votes uses this to maintain voting weight checkpoints.
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    /**
     * @dev ERC20Permit and Nonces both expose `nonces()` — resolve the
     *      ambiguity so the compiler knows which implementation to use.
     */
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
