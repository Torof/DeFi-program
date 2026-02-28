// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Mock Chainlink L2 Sequencer Uptime Feed for testing.
/// @dev answer = 0 means sequencer UP, answer = 1 means DOWN.
///      startedAt = timestamp when the current status began.
contract MockSequencerFeed {
    int256 public answer;       // 0 = up, 1 = down
    uint256 public startedAt;   // when current status started

    constructor() {
        answer = 0;             // start as UP
        startedAt = block.timestamp;
    }

    function setStatus(bool isDown, uint256 _startedAt) external {
        answer = isDown ? int256(1) : int256(0);
        startedAt = _startedAt;
    }

    /// @dev Matches Chainlink AggregatorV3Interface.latestRoundData()
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 _startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, startedAt, block.timestamp, 1);
    }
}
