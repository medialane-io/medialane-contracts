// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MDLNVesting
 * @notice On-chain time-lock vesting for the Medialane DAO treasury.
 *
 * Holds 90% of MDLN supply (18,900,000 tokens) and releases one tranche
 * of 2,100,000 MDLN to the Gnosis Safe every 365 days, for 9 years.
 *
 * Design decisions:
 *  - Beneficiary and token are immutable — set at deploy, never changeable.
 *  - `release()` is permissionless — anyone can trigger a release once a
 *    tranche is due. Tokens always go to the beneficiary, never anywhere else.
 *  - Multiple elapsed tranches are released in a single call (catch-up safe).
 *  - No owner, no admin, no pause, no upgrade. Fully trustless.
 *
 * Deploy flow:
 *  1. Deploy MedialaneToken with treasury = Gnosis Safe.
 *  2. Deploy MDLNVesting with token = MDLN address, beneficiary = Gnosis Safe.
 *  3. From Gnosis Safe, transfer 18,900,000 MDLN to this contract.
 *  4. Gnosis Safe retains 2,100,000 MDLN as operational runway.
 */
contract MDLNVesting {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 public constant TOTAL_TRANCHES   = 9;
    uint256 public constant TRANCHE_AMOUNT   = 2_100_000 * 10 ** 18; // 2.1M MDLN
    uint256 public constant TRANCHE_DURATION = 365 days;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The MDLN token contract.
    IERC20  public immutable token;

    /// @notice Gnosis Safe that receives each released tranche.
    address public immutable beneficiary;

    /// @notice Timestamp when vesting starts (set at deployment).
    uint256 public immutable startTime;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Number of tranches already released (0–9).
    uint256 public releasedTranches;

    // ─── Events ───────────────────────────────────────────────────────────────

    event Released(uint256 tranche, uint256 amount, uint256 timestamp);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error MDLN_NothingToRelease();
    error MDLN_ZeroAddress();

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _token       Address of the deployed MedialaneToken (MDLN).
     * @param _beneficiary Gnosis Safe address — receives every released tranche.
     */
    constructor(address _token, address _beneficiary) {
        if (_token       == address(0)) revert MDLN_ZeroAddress();
        if (_beneficiary == address(0)) revert MDLN_ZeroAddress();

        token       = IERC20(_token);
        beneficiary = _beneficiary;
        startTime   = block.timestamp;
    }

    // ─── External ─────────────────────────────────────────────────────────────

    /**
     * @notice Release all tranches that have become due since the last release.
     * @dev    Permissionless — anyone can call. Tokens always go to beneficiary.
     *         Safe to call multiple times; no-ops if nothing is due.
     */
    function release() external {
        uint256 due = _tranchesDue();
        if (due == 0) revert MDLN_NothingToRelease();

        releasedTranches += due;
        uint256 amount = due * TRANCHE_AMOUNT;

        token.safeTransfer(beneficiary, amount);

        emit Released(releasedTranches, amount, block.timestamp);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    /// @notice Tranches that can be released right now.
    function tranchesDue() external view returns (uint256) {
        return _tranchesDue();
    }

    /// @notice Timestamp when the next tranche becomes releasable.
    function nextReleaseAt() external view returns (uint256) {
        if (releasedTranches >= TOTAL_TRANCHES) return 0;
        return startTime + (releasedTranches + 1) * TRANCHE_DURATION;
    }

    /// @notice MDLN tokens still locked in this contract.
    function lockedBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _tranchesDue() internal view returns (uint256) {
        uint256 elapsed  = (block.timestamp - startTime) / TRANCHE_DURATION;
        uint256 unlocked = elapsed < TOTAL_TRANCHES ? elapsed : TOTAL_TRANCHES;
        return unlocked - releasedTranches;
    }
}
