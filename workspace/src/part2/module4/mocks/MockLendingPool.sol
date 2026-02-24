// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3} from "../../module3/interfaces/IAggregatorV3.sol";

/// @notice Mock lending pool for the FlashLiquidator exercise.
/// @dev Pre-built — students do NOT modify this. It simulates a lending pool
///      with configurable positions and a liquidate() function.
///
///      Features:
///        - Admin-configurable user positions (collateral + debt)
///        - Health factor calculation using Chainlink oracles
///        - Close factor: 50% if HF >= 0.95, 100% if HF < 0.95
///        - 5% liquidation bonus on seized collateral
///        - Transfers debt from liquidator, sends collateral to liquidator
contract MockLendingPool {
    using SafeERC20 for IERC20;

    struct Position {
        address collateralToken;
        uint256 collateralAmount;
        address debtToken;
        uint256 debtAmount;
    }

    uint256 public constant LIQUIDATION_BONUS_BPS = 10500; // 105% = 5% bonus
    uint256 public constant CLOSE_FACTOR_HF_THRESHOLD = 0.95e18;

    mapping(address => Position) public positions;
    mapping(address => IAggregatorV3) public oracles;

    error HealthyPosition();
    error ExceedsCloseFactor();

    /// @notice Admin: set up a user's position for testing.
    function setPosition(
        address user,
        address collateral,
        uint256 collateralAmt,
        address debt,
        uint256 debtAmt
    ) external {
        positions[user] = Position({
            collateralToken: collateral,
            collateralAmount: collateralAmt,
            debtToken: debt,
            debtAmount: debtAmt
        });
    }

    /// @notice Admin: configure oracle for a token.
    function setOracle(address token, address oracle) external {
        oracles[token] = IAggregatorV3(oracle);
    }

    /// @notice Returns health factor for a user (18 decimals).
    function getHealthFactor(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.debtAmount == 0) return type(uint256).max;

        uint256 collateralValue = _getValueE18(pos.collateralToken, pos.collateralAmount);
        uint256 debtValue = _getValueE18(pos.debtToken, pos.debtAmount);

        return collateralValue * 1e18 / debtValue;
    }

    /// @notice Liquidate a borrower's position.
    /// @dev Caller must have approved this contract for debtToCover of debtAsset.
    /// @return collateralSeized The amount of collateral sent to the liquidator.
    function liquidate(
        address borrower,
        address debtAsset,
        uint256 debtToCover,
        address collateralAsset
    ) external returns (uint256 collateralSeized) {
        Position storage pos = positions[borrower];

        uint256 hf = getHealthFactor(borrower);
        if (hf >= 1e18) revert HealthyPosition();

        // Close factor: 50% if HF >= 0.95, 100% if HF < 0.95
        uint256 maxClose = hf >= CLOSE_FACTOR_HF_THRESHOLD
            ? pos.debtAmount / 2
            : pos.debtAmount;
        if (debtToCover > maxClose) revert ExceedsCloseFactor();

        // Calculate collateral to seize: debtToCover × debtPrice × bonus / collateralPrice
        uint256 debtValue = _getValueE18(debtAsset, debtToCover);
        uint256 collateralPrice = _getPriceE18(collateralAsset);
        collateralSeized = debtValue * LIQUIDATION_BONUS_BPS / 10000 * 1e18 / collateralPrice;

        // Update position (no collateral cap — mock has pre-minted reserves)
        pos.debtAmount -= debtToCover;
        if (collateralSeized <= pos.collateralAmount) {
            pos.collateralAmount -= collateralSeized;
        } else {
            pos.collateralAmount = 0;
        }

        // Transfer debt from liquidator to this pool
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);

        // Transfer collateral to liquidator
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralSeized);
    }

    // --- Internal helpers ---

    function _getValueE18(address token, uint256 amount) internal view returns (uint256) {
        uint256 price = _getPriceE18(token);
        uint8 decimals = IERC20Metadata(token).decimals();
        return amount * price / (10 ** decimals);
    }

    function _getPriceE18(address token) internal view returns (uint256) {
        IAggregatorV3 oracle = oracles[token];
        (, int256 answer,,,) = oracle.latestRoundData();
        uint8 oracleDecimals = oracle.decimals();
        return uint256(answer) * 1e18 / (10 ** oracleDecimals);
    }
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
