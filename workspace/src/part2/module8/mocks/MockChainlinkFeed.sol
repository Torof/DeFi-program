// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY — Pre-built mock Chainlink price feed.
//  Returns a fixed price set at construction. Used by SecureLending.
//
//  Real Chainlink feeds return 8-decimal prices via latestRoundData().
//  This mock mirrors that interface with a configurable price.
// ============================================================================

/// @notice Minimal mock of Chainlink's AggregatorV3Interface.
/// @dev Returns a fixed price. No rounds, no staleness — just the price.
contract MockChainlinkFeed {
    int256 public immutable price;
    uint8 public immutable feedDecimals;

    /// @param price_ The fixed price to return (e.g., 1e8 for $1.00 at 8 decimals).
    /// @param feedDecimals_ Number of decimals in the price (Chainlink typically uses 8).
    constructor(int256 price_, uint8 feedDecimals_) {
        price = price_;
        feedDecimals = feedDecimals_;
    }

    /// @notice Returns the feed's decimal precision.
    function decimals() external view returns (uint8) {
        return feedDecimals;
    }

    /// @notice Returns the latest price data (simplified — only answer matters).
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}
