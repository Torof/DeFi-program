// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal mock price feed for perp exercises.
/// @dev Returns a configurable price. Owner can update at any time.
///      Prices use 8 decimals (Chainlink convention).
///
///      NOTE: This mock is not used by the current Module 2 exercises
///      (SimplePerpExchange uses a built-in setEthPrice() instead).
///      It is kept here as a utility for students who want to extend
///      the exercises with Chainlink-style oracle integration.
contract MockPriceFeed {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
    }

    function latestAnswer() external view returns (int256) {
        return _price;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // --- Test helpers ---

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }
}
