// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";
import {TWAPOracle} from "../exercise2-twap-oracle/TWAPOracle.sol";

// ============================================================================
// EXERCISE: Dual Oracle with Fallback
//
// Build a production-grade dual-oracle system inspired by Liquity's PriceFeed.sol.
// The contract reads from two independent price sources (Chainlink + TWAP),
// cross-checks them for consistency, and gracefully degrades when either fails.
//
// This is the architecture pattern used by serious lending protocols:
//   - Liquity: Chainlink primary + Tellor secondary (5-state machine)
//   - Aave V3: Chainlink primary + governance fallback
//   - Compound V3: Primary + backup price feeds
//
// The simplified 3-state machine here teaches the core pattern:
//   USING_PRIMARY → USING_SECONDARY → BOTH_UNTRUSTED
//   with recovery paths back to USING_PRIMARY when the primary oracle recovers.
//
// Concepts exercised:
//   - Dual-oracle architecture (defense in depth)
//   - Deviation detection between independent sources
//   - State machine for oracle health tracking
//   - Graceful degradation (fallback to last known good price)
//   - Event-driven monitoring (off-chain systems watch status changes)
//
// Key references:
//   - Liquity PriceFeed.sol: https://github.com/liquity/dev/blob/main/packages/contracts/contracts/PriceFeed.sol
//   - Aave AaveOracle: https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol
//
// Run: forge test --match-contract DualOracleTest -vvv
// ============================================================================

// --- Custom Errors ---
error NoGoodPrice();
error InvalidConfiguration();

/// @notice A dual-oracle system with automatic fallback and recovery.
/// @dev Reads from a Chainlink feed (primary) and a TWAP oracle (secondary).
///
///      State machine:
///
///        ┌─────────────────┐
///        │  USING_PRIMARY  │ ← Normal operation
///        │  (Chainlink)    │   Both sources agree, primary is fresh
///        └────┬───────┬────┘
///             │       │
///      Primary│       │ Deviation
///      fails  │       │ detected
///             ▼       ▼
///        ┌─────────────────┐
///        │ USING_SECONDARY │   Primary unavailable or disagrees with secondary
///        │    (TWAP)       │   Secondary is the best available source
///        └────┬────────────┘
///             │
///      Secondary│
///      also fails│
///             ▼
///        ┌─────────────────┐
///        │ BOTH_UNTRUSTED  │   Neither source is reliable
///        │ (lastGoodPrice) │   Fall back to last known good price
///        └─────────────────┘
///
///      Recovery: When a source recovers (comes back online, deviation resolves),
///      the system transitions back up the chain. The transition always requires
///      a deviation check — you can't switch back to primary if it disagrees with secondary.
contract DualOracle {
    // --- Types ---

    enum OracleStatus {
        USING_PRIMARY,     // Chainlink is healthy and agrees with TWAP
        USING_SECONDARY,   // Chainlink failed or disagrees; using TWAP
        BOTH_UNTRUSTED     // Neither source is reliable; using lastGoodPrice
    }

    // --- State ---

    /// @dev Current oracle health state
    OracleStatus public status;

    /// @dev The Chainlink price feed (primary source)
    IAggregatorV3 public immutable primaryFeed;

    /// @dev The TWAP oracle (secondary source)
    TWAPOracle public immutable secondaryOracle;

    /// @dev Maximum staleness for the Chainlink feed (in seconds)
    uint256 public immutable maxStaleness;

    /// @dev TWAP window to use when consulting the secondary oracle (in seconds)
    uint256 public immutable twapWindow;

    /// @dev The last price that both sources agreed on
    ///      Used as ultimate fallback when both oracles fail
    uint256 public lastGoodPrice;

    // --- Constants ---

    /// @dev Maximum allowed deviation between primary and secondary (in bps)
    ///      500 bps = 5%. If sources disagree by more than this, something is wrong.
    uint256 public constant MAX_DEVIATION = 500;

    // --- Events ---

    /// @dev Emitted when the oracle state machine transitions between states
    event OracleStatusChanged(OracleStatus indexed oldStatus, OracleStatus indexed newStatus);

    /// @dev Emitted when primary and secondary prices disagree beyond threshold
    event DeviationDetected(uint256 primaryPrice, uint256 secondaryPrice, uint256 deviationBps);

    /// @dev Emitted when both oracles fail and we fall back to cached price
    event FallbackToLastGoodPrice(uint256 price);

    constructor(
        address _primaryFeed,
        address _secondaryOracle,
        uint256 _maxStaleness,
        uint256 _twapWindow
    ) {
        if (_primaryFeed == address(0) || _secondaryOracle == address(0)) {
            revert InvalidConfiguration();
        }
        primaryFeed = IAggregatorV3(_primaryFeed);
        secondaryOracle = TWAPOracle(_secondaryOracle);
        maxStaleness = _maxStaleness;
        twapWindow = _twapWindow;
        status = OracleStatus.USING_PRIMARY;
    }

    // =============================================================
    //  TODO 1: Implement _getPrimaryPrice — read Chainlink safely
    // =============================================================
    /// @notice Attempts to read and validate the Chainlink price.
    /// @dev Same 4 checks as OracleConsumer, but instead of reverting on
    ///      failure, returns (0, false). The caller (getPrice) handles
    ///      the failure by falling back to the secondary source.
    ///
    ///      Why not revert? Because in a dual-oracle system, one source
    ///      failing is EXPECTED and handled gracefully. Reverting would
    ///      freeze the entire protocol. Returning success=false lets the
    ///      state machine decide what to do.
    ///
    /// Steps:
    ///   1. Try calling primaryFeed.latestRoundData()
    ///      - If the external call itself reverts, return (0, false)
    ///   2. Check: answer > 0, else return (0, false)
    ///   3. Check: updatedAt > 0, else return (0, false)
    ///   4. Check: block.timestamp - updatedAt < maxStaleness, else return (0, false)
    ///   5. Check: answeredInRound >= roundId, else return (0, false)
    ///   6. Normalize to 18 decimals: price * 10^(18 - decimals)
    ///   7. Return (normalizedPrice, true)
    ///
    /// Hint: You can use a try/catch block to handle the external call,
    ///       or just call it normally and wrap the validations in if-statements.
    ///       The key is: NEVER revert from this function.
    ///
    /// @return price The normalized price (18 decimals), or 0 if failed
    /// @return success Whether the price is valid and usable
    function _getPrimaryPrice() internal view returns (uint256 price, bool success) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement _getSecondaryPrice — read TWAP safely
    // =============================================================
    /// @notice Attempts to read the TWAP oracle price.
    /// @dev The TWAP oracle may fail if:
    ///      - Not enough observations recorded yet (InsufficientHistory)
    ///      - Observations are too old for the requested window (ObservationTooOld)
    ///      - Window is too short (WindowTooShort)
    ///
    ///      Same pattern as _getPrimaryPrice: return (0, false) on failure
    ///      instead of reverting.
    ///
    /// Steps:
    ///   1. Try calling secondaryOracle.consult(twapWindow)
    ///      - If it reverts (any reason), return (0, false)
    ///   2. If it succeeds, return (twapPrice, true)
    ///
    /// Hint: Use try/catch around the consult call. The TWAP oracle returns
    ///       prices in the same units as the spot prices fed to it — make sure
    ///       your test setup feeds it prices in 18-decimal format to match
    ///       the Chainlink normalization.
    ///
    /// @return price The TWAP price, or 0 if unavailable
    /// @return success Whether the TWAP is valid and usable
    function _getSecondaryPrice() internal view returns (uint256 price, bool success) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement _checkDeviation — compare two prices
    // =============================================================
    /// @notice Checks if two prices are within the acceptable deviation threshold.
    /// @dev Deviation formula:
    ///        deviation_bps = |priceA - priceB| × 10000 / max(priceA, priceB)
    ///
    ///      Using max() as the denominator gives a conservative (smaller)
    ///      deviation percentage. This means the check is slightly lenient,
    ///      which is appropriate — you want to avoid false positives that
    ///      would unnecessarily trigger fallback.
    ///
    ///      Example:
    ///        priceA = 3000e18, priceB = 3100e18
    ///        diff = 100e18
    ///        deviation = 100e18 * 10000 / 3100e18 = 322 bps (3.22%)
    ///        MAX_DEVIATION = 500 bps → within bounds ✓
    ///
    /// Steps:
    ///   1. If either price is 0, return false (can't compare with zero)
    ///   2. Compute diff = |priceA - priceB|
    ///   3. Compute maxPrice = max(priceA, priceB)
    ///   4. Compute deviationBps = diff * 10000 / maxPrice
    ///   5. Return deviationBps <= MAX_DEVIATION
    ///
    /// @param priceA First price (18 decimals)
    /// @param priceB Second price (18 decimals)
    /// @return withinBounds True if deviation is within MAX_DEVIATION
    function _checkDeviation(uint256 priceA, uint256 priceB) internal pure returns (bool withinBounds) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement getPrice — the main entry point
    // =============================================================
    /// @notice Returns the best available price, managing oracle health state.
    /// @dev This is the function your lending/vault/CDP protocol calls.
    ///      It implements the state machine logic:
    ///
    ///      Decision tree:
    ///
    ///        primarySuccess?
    ///        ├── YES: secondarySuccess?
    ///        │   ├── YES: deviation OK?
    ///        │   │   ├── YES → use primary, status=PRIMARY, update lastGoodPrice
    ///        │   │   └── NO  → emit DeviationDetected, use secondary, status=SECONDARY
    ///        │   └── NO  → use primary alone (can't cross-check), update lastGoodPrice
    ///        └── NO:  secondarySuccess?
    ///            ├── YES → use secondary, status=SECONDARY, update lastGoodPrice
    ///            └── NO  → lastGoodPrice > 0?
    ///                ├── YES → emit Fallback, status=BOTH_UNTRUSTED, return lastGoodPrice
    ///                └── NO  → revert NoGoodPrice (no data at all)
    ///
    /// Steps:
    ///   1. Get primary and secondary prices via _getPrimaryPrice() and _getSecondaryPrice()
    ///   2. If primary succeeds:
    ///      a. If secondary also succeeds:
    ///         - Check deviation. If within bounds → use primary, _updateStatus(USING_PRIMARY), set lastGoodPrice
    ///         - If deviation too high → emit DeviationDetected, use secondary, _updateStatus(USING_SECONDARY), set lastGoodPrice
    ///      b. If secondary fails → use primary (no cross-check), _updateStatus(USING_PRIMARY), set lastGoodPrice
    ///   3. If primary fails:
    ///      a. If secondary succeeds → use secondary, _updateStatus(USING_SECONDARY), set lastGoodPrice
    ///      b. If both fail:
    ///         - If lastGoodPrice > 0 → emit FallbackToLastGoodPrice, _updateStatus(BOTH_UNTRUSTED), return lastGoodPrice
    ///         - If lastGoodPrice == 0 → revert NoGoodPrice
    ///
    /// Hint: This is a simplified version of Liquity's 5-state machine.
    ///       Study Liquity's PriceFeed.sol for the production pattern:
    ///       https://github.com/liquity/dev/blob/main/packages/contracts/contracts/PriceFeed.sol
    ///
    /// @return The best available price (18 decimals)
    function getPrice() external returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement _updateStatus — state transition with events
    // =============================================================
    /// @notice Updates the oracle status and emits an event on state change.
    /// @dev Off-chain monitoring systems (Tenderly, OpenZeppelin Defender,
    ///      custom alert bots) watch for OracleStatusChanged events.
    ///      A transition to USING_SECONDARY or BOTH_UNTRUSTED is a critical
    ///      alert that requires human investigation.
    ///
    /// Steps:
    ///   1. If newStatus != current status:
    ///      - Emit OracleStatusChanged(old, new)
    ///      - Update status = newStatus
    ///
    /// Hint: Simple but important. In production, these events trigger PagerDuty
    ///       alerts, Discord notifications, and automatic protocol pausing.
    ///
    /// @param newStatus The new oracle health status
    function _updateStatus(OracleStatus newStatus) internal {
        revert("Not implemented");
    }
}
