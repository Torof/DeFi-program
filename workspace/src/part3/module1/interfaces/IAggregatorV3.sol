// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  Simplified Chainlink AggregatorV3Interface — reused from Part 2 Module 3.
//
//  See Part 2 for detailed documentation on each field and safety check.
//  This copy exists so Part 3 exercises can import locally without
//  cross-part dependencies.
//
//  See: https://docs.chain.link/data-feeds/using-data-feeds
// ============================================================================

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
