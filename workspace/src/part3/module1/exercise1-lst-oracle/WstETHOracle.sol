// SPDX-License-Identifier: MIT
// NOTE: src files use ^0.8.28 (flexible — compatible with future patch releases),
//       while test files use 0.8.28 (pinned — deterministic test artifacts).
//       This is intentional and mirrors common production practice.
pragma solidity ^0.8.28;

import {IWstETH} from "../interfaces/IWstETH.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

// ============================================================================
// EXERCISE: wstETH Oracle — Two-Step LST Pricing Pipeline
//
// Build an oracle that correctly prices wstETH in USD using the two-step
// pipeline that every production lending protocol implements:
//
//   Step 1: wstETH → ETH equivalent (via Lido exchange rate)
//   Step 2: ETH → USD (via Chainlink ETH/USD feed)
//
// Then extend it with the DUAL ORACLE pattern that protects against de-peg
// scenarios. During the June 2022 stETH de-peg (0.93 ETH), lending protocols
// using exchange-rate-only pricing overvalued wstETH collateral by ~7% —
// enough to leave positions undercollateralized without triggering liquidation.
//
// The dual oracle pattern (used by Aave, Morpho, and others):
//   stETH→ETH rate = min(protocolRate, marketRate)
//   - Normal times: both ≈ 1.0, min doesn't matter
//   - De-peg: market < protocol, min uses the lower (safer) value
//
// Concepts exercised:
//   - Two-step LST pricing pipeline (exchange rate × Chainlink)
//   - Dual oracle pattern for de-peg safety
//   - Chainlink staleness validation on multiple feeds
//   - Decimal handling across the pipeline
//
// Key references:
//   - Lido wstETH: https://docs.lido.fi/contracts/wsteth
//   - Chainlink stETH/ETH feed: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812
//   - Aave wstETH oracle: https://github.com/aave/aave-v3-core
//   - Module 1 lesson: part3/1-liquid-staking.md#oracle-pricing
//
// Run: forge test --match-contract WstETHOracleTest -vvv
// ============================================================================

// --- Custom Errors ---
error InvalidPrice();
error StalePrice();
error ZeroAmount();

/// @notice Oracle that prices wstETH in USD via a two-step pipeline.
/// @dev Pre-built: constructor, state variables, constants.
///      Student implements: getWstETHValueUSD (basic) and getWstETHValueUSDSafe (dual oracle).
contract WstETHOracle {
    // --- State ---

    /// @dev Lido wstETH contract — provides the exchange rate.
    IWstETH public immutable wstETH;

    /// @dev Chainlink ETH/USD price feed (8 decimals on mainnet).
    IAggregatorV3 public immutable ethUsdFeed;

    /// @dev Chainlink stETH/ETH market price feed (18 decimals on mainnet).
    ///      This is the MARKET price of stETH in ETH — it can diverge from
    ///      the protocol exchange rate during de-peg events.
    IAggregatorV3 public immutable stethEthFeed;

    // --- Constants ---

    /// @dev Maximum allowed age for the ETH/USD feed (seconds).
    ///      ETH/USD heartbeat is 3600s; we add buffer.
    uint256 public constant ETH_USD_STALENESS = 3900; // 1h 5m

    /// @dev Maximum allowed age for the stETH/ETH feed (seconds).
    ///      stETH/ETH heartbeat is 86400s (24h); we add buffer.
    uint256 public constant STETH_ETH_STALENESS = 90_000; // 25h

    /// @dev 1e18 — used for fixed-point math clarity.
    uint256 private constant WAD = 1e18;

    constructor(address _wstETH, address _ethUsdFeed, address _stethEthFeed) {
        wstETH = IWstETH(_wstETH);
        ethUsdFeed = IAggregatorV3(_ethUsdFeed);
        stethEthFeed = IAggregatorV3(_stethEthFeed);
    }

    // =============================================================
    //  TODO 1: Implement getWstETHValueUSD — basic two-step pricing
    // =============================================================
    /// @notice Prices a wstETH amount in USD using the protocol exchange rate.
    /// @dev This is the BASIC pipeline — no de-peg protection.
    ///
    ///      The two-step pipeline:
    ///      ┌──────────┐  getStETHByWstETH  ┌────────────┐  Chainlink   ┌───────────┐
    ///      │ wstETH   │ ────────────────→   │ ETH equiv  │ ──────────→  │ USD value │
    ///      │ (18 dec) │   exchange rate     │ (18 dec)   │  ETH/USD    │ (8 dec)   │
    ///      └──────────┘                     └────────────┘  (8 dec)    └───────────┘
    ///
    ///      Numeric example:
    ///        wstETHAmount  = 10e18 (10 wstETH)
    ///        stEthPerToken = 1.19e18
    ///        ETH/USD       = 3200e8 ($3,200)
    ///
    ///        Step 1: ethEquiv = 10e18 × 1.19e18 / 1e18 = 11.9e18
    ///        Step 2: valueUSD = 11.9e18 × 3200e8 / 1e18 = 38_080e8
    ///
    ///        Result: 38_080e8 (in Chainlink 8-decimal format = $38,080.00)
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if wstETHAmount is 0
    ///        2. Convert wstETH → stETH (ETH equivalent) via wstETH.getStETHByWstETH()
    ///        3. Read ETH/USD price from Chainlink — validate:
    ///           - answer > 0 (revert InvalidPrice)
    ///           - block.timestamp - updatedAt <= ETH_USD_STALENESS (revert StalePrice)
    ///        4. Compute: ethEquivalent × ethUsdPrice / WAD
    ///
    ///      Hint: getStETHByWstETH() already handles the exchange rate multiplication
    ///            internally. You're just chaining its output into Chainlink.
    ///
    /// @param wstETHAmount The amount of wstETH to price (18 decimals)
    /// @return valueUSD The USD value (in ethUsdFeed decimals, typically 8)
    function getWstETHValueUSD(uint256 wstETHAmount) external view returns (uint256 valueUSD) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement getWstETHValueUSDSafe — dual oracle pattern
    // =============================================================
    /// @notice Prices a wstETH amount in USD using the dual oracle pattern.
    /// @dev This is the SAFE pipeline — uses min(protocolRate, marketRate)
    ///      for the stETH→ETH conversion step.
    ///
    ///      Why dual oracle?
    ///        Protocol rate (stEthPerToken): always ~1.19 — reflects backing.
    ///        Market rate (Chainlink stETH/ETH): usually ~1.0, but during
    ///        a de-peg can drop (e.g., 0.93 in June 2022).
    ///
    ///        Protocol says 1 stETH = 1.0 ETH equivalent for pricing.
    ///        Market says 1 stETH = 0.93 ETH (actual liquidation value).
    ///        Using min(1.0, 0.93) = 0.93 correctly reflects what a liquidator
    ///        would actually receive when selling the collateral.
    ///
    ///      The safe pipeline:
    ///        1. Get protocol rate: wstETH.stEthPerToken() → e.g., 1.19e18
    ///        2. Get market rate: stETH/ETH Chainlink feed → e.g., 0.99e18
    ///        3. Effective rate = stEthPerToken × min(1e18, marketRate) / 1e18
    ///           - If marketRate ≈ 1e18 (normal): effective ≈ stEthPerToken
    ///           - If marketRate < 1e18 (de-peg): effective < stEthPerToken
    ///        4. ethEquivalent = wstETHAmount × effectiveRate / 1e18
    ///        5. valueUSD = ethEquivalent × ethUsdPrice / 1e18
    ///
    ///      Numeric example (de-peg scenario):
    ///        wstETHAmount  = 10e18
    ///        stEthPerToken = 1.19e18
    ///        stETH/ETH     = 0.93e18 (de-peg!)
    ///        ETH/USD       = 3200e8
    ///
    ///        effectiveRate = 1.19e18 × min(1e18, 0.93e18) / 1e18
    ///                      = 1.19e18 × 0.93e18 / 1e18
    ///                      = 1.1067e18
    ///        ethEquiv      = 10e18 × 1.1067e18 / 1e18 = 11.067e18
    ///        valueUSD      = 11.067e18 × 3200e8 / 1e18 = 35_414.4e8
    ///
    ///        Compare to basic: 38_080e8 — dual oracle gives $35,414 vs $38,080
    ///        The $2,665 difference per wstETH is the de-peg discount.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if wstETHAmount is 0
    ///        2. Read stETH/ETH market price from Chainlink — validate:
    ///           - answer > 0 (revert InvalidPrice)
    ///           - block.timestamp - updatedAt <= STETH_ETH_STALENESS (revert StalePrice)
    ///        3. Cap market rate at WAD: safeMarketRate = min(marketRate, WAD)
    ///           (market rate should never exceed 1.0 for stETH/ETH, but cap defensively)
    ///        4. Get protocol exchange rate: stEthPerToken = wstETH.stEthPerToken()
    ///        5. Compute effective rate: stEthPerToken × safeMarketRate / WAD
    ///        6. Compute ETH equivalent: wstETHAmount × effectiveRate / WAD
    ///        7. Read ETH/USD from Chainlink — validate (same checks as TODO 1)
    ///        8. Compute USD value: ethEquivalent × ethUsdPrice / WAD
    ///
    ///      Hint: The key insight is that stEthPerToken converts wstETH→stETH
    ///            (always valid), but the stETH→ETH step needs the market rate
    ///            discount. Multiplying stEthPerToken by min(1, marketRate)
    ///            creates one combined wstETH→ETH rate.
    ///
    /// @param wstETHAmount The amount of wstETH to price (18 decimals)
    /// @return valueUSD The USD value (in ethUsdFeed decimals, typically 8)
    function getWstETHValueUSDSafe(uint256 wstETHAmount) external view returns (uint256 valueUSD) {
        // YOUR CODE HERE
    }
}
