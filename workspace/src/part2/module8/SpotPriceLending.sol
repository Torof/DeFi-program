// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockPair} from "./MockPair.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built lending protocol that is VULNERABLE to oracle
//  manipulation. It reads pair.getSpotPrice() to value collateral.
//
//  The vulnerability: spot price = reserveB / reserveA on the AMM pair.
//  A flash loan swap can shift reserves dramatically, inflating the spot
//  price within a single transaction. The lending protocol sees the
//  inflated price and allows an oversized borrow.
// ============================================================================

/// @notice Minimal lending protocol — accepts tokenA as collateral, lends tokenB.
/// @dev VULNERABLE: reads AMM spot price (reserve ratio) for collateral valuation.
contract SpotPriceLending {
    using SafeERC20 for IERC20;

    MockPair public immutable pair;
    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;

    /// @notice Collateralization ratio: 200% (2e18). Must deposit $200 of
    ///         collateral to borrow $100.
    uint256 public constant COLLATERAL_RATIO = 2e18;

    /// @notice TokenA deposited as collateral, per user.
    mapping(address => uint256) public collateral;

    /// @notice TokenB borrowed, per user.
    mapping(address => uint256) public borrowed;

    constructor(MockPair pair_, IERC20 collateralToken_, IERC20 borrowToken_) {
        pair = pair_;
        collateralToken = collateralToken_;
        borrowToken = borrowToken_;
    }

    /// @notice Deposit tokenA as collateral.
    function depositCollateral(uint256 amount) external {
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    /// @notice Borrow tokenB against deposited tokenA collateral.
    /// @dev VULNERABLE: reads pair.getSpotPrice() which can be inflated
    ///      by a flash-loan-funded swap on the same AMM pair.
    function borrow(uint256 amount) external {
        uint256 price = pair.getSpotPrice(); // VULNERABLE — AMM spot price!
        uint256 collateralValue = collateral[msg.sender] * price / 1e18;
        uint256 maxBorrow = collateralValue * 1e18 / COLLATERAL_RATIO;

        require(
            borrowed[msg.sender] + amount <= maxBorrow,
            "SpotPriceLending: insufficient collateral"
        );

        borrowed[msg.sender] += amount;
        borrowToken.safeTransfer(msg.sender, amount);
    }
}
