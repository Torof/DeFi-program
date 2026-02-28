// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Mock Chainlink price feed for testing.
contract MockPriceFeed {
    int256 public price;
    uint256 public updatedAt;
    uint8 public decimals_ = 8;

    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (1, price, updatedAt, updatedAt, 1);
    }
}
