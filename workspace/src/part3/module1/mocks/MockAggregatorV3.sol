// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

/// @notice Configurable mock for testing Chainlink oracle consumers.
/// @dev Replicates the Part 2 Module 3 mock pattern. Allows tests to simulate:
///      - Fresh valid prices (happy path)
///      - Stale prices (updatedAt in the past)
///      - Negative/zero prices (invalid data)
///      - Incomplete rounds (updatedAt == 0)
contract MockAggregatorV3 is IAggregatorV3 {
    uint8 private _decimals;
    string private _description;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(int256 initialAnswer, uint8 decimals_) {
        _answer = initialAnswer;
        _decimals = decimals_;
        _roundId = 1;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
        _description = "Mock / USD";
    }

    // --- IAggregatorV3 implementation ---

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }

    // --- Test helpers ---

    /// @notice Update the price and refresh timestamps (simulates a normal feed update).
    function updateAnswer(int256 newAnswer) external {
        _roundId++;
        _answer = newAnswer;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = _roundId;
    }

    /// @notice Force the updatedAt timestamp (to simulate stale data).
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    /// @notice Force the startedAt timestamp.
    function setStartedAt(uint256 timestamp) external {
        _startedAt = timestamp;
    }

    /// @notice Force answeredInRound to a specific value (to simulate stale rounds).
    function setAnsweredInRound(uint80 answeredInRound) external {
        _answeredInRound = answeredInRound;
    }

    /// @notice Full control over all round data fields.
    function setRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }
}
