// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  Simplified Chainlink AggregatorV3Interface
//
//  In production, you import from @chainlink/contracts:
//    import {AggregatorV3Interface} from
//      "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
//
//  This simplified version avoids adding Chainlink as a dependency while
//  teaching the exact same interface your protocol will consume.
//
//  How this maps to real Chainlink on-chain:
//    - Your protocol calls latestRoundData() on a PROXY address
//      (e.g., 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 for ETH/USD)
//    - The Proxy delegates to an Aggregator (AccessControlledOffchainAggregator)
//    - The Aggregator stores the median of all node observations (OCR)
//    - Chainlink can upgrade the Aggregator behind the Proxy without breaking consumers
//
//  See: https://docs.chain.link/data-feeds/using-data-feeds
//  See: https://github.com/smartcontractkit/chainlink/blob/contracts-v1.3.0/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol
// ============================================================================

interface IAggregatorV3 {
    /// @notice Returns the number of decimal places in the answer.
    /// @dev Most USD-denominated feeds use 8 decimals (e.g., ETH/USD: 300000000000 = $3,000.00).
    ///      ETH-denominated feeds use 18 decimals (e.g., BTC/ETH).
    ///      NEVER hardcode this — always call decimals() dynamically.
    function decimals() external view returns (uint8);

    /// @notice Returns a human-readable description (e.g., "ETH / USD").
    function description() external view returns (string memory);

    /// @notice Returns the latest round data from the oracle.
    /// @dev Critical fields for your protocol:
    ///
    ///      roundId          — Identifier for this round of data
    ///      answer           — The price (int256, can be negative for some feeds!)
    ///      startedAt        — Timestamp when the round started (for sequencer feeds:
    ///                         when the sequencer last came back online)
    ///      updatedAt        — Timestamp of the last update. YOUR STALENESS CHECK USES THIS.
    ///      answeredInRound  — The round in which the answer was computed.
    ///                         If answeredInRound < roundId, the data is from a previous round (stale).
    ///
    ///      Mandatory safety checks before using the answer:
    ///        1. answer > 0           (invalid/negative price)
    ///        2. updatedAt > 0        (round not complete)
    ///        3. block.timestamp - updatedAt < maxStaleness  (data is fresh)
    ///        4. answeredInRound >= roundId                  (round is finalized)
    ///
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
