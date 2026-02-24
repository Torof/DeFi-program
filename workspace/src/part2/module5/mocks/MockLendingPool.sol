// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock lending pool simulating core Aave V3 lending operations.
/// @dev Pre-built — students do NOT modify this.
///
///      Simulates the subset of Aave V3's Pool needed for the CollateralSwap exercise:
///        - supply:   Pull underlying → mint aTokens to onBehalfOf
///        - withdraw:  Burn caller's aTokens → send underlying to `to`
///        - repay:    Pull tokens from caller → reduce onBehalfOf's debt
///        - borrow:   Check credit delegation → send tokens to caller → increase debt
///        - approveDelegation: Allow another address to borrow on your behalf
///
///      Simplifications vs real Aave V3:
///        - No health factor / LTV checks (any borrow succeeds if delegation exists)
///        - No interest accrual (debt is static until repay/borrow)
///        - Credit delegation lives on the pool (Aave puts it on the debt token)
///        - No separate variable/stable rate tracking (rateMode ignored)
///        - aTokens are 1:1 with underlying (no rebasing or index math)
contract MockLendingPool {
    using SafeERC20 for IERC20;

    /// @notice aToken mapping: underlying asset => aToken address.
    mapping(address => address) public aTokenOf;

    /// @notice Debt tracking: user => asset => debt amount.
    mapping(address => mapping(address => uint256)) public debtOf;

    /// @notice Credit delegation: user => delegatee => asset => allowance.
    mapping(address => mapping(address => mapping(address => uint256))) public creditAllowance;

    error NoAToken();
    error InsufficientDelegation();

    // =========================================================
    //  Admin Setup (used in tests)
    // =========================================================

    /// @notice Register an aToken for an underlying asset.
    function setAToken(address asset, address aToken) external {
        aTokenOf[asset] = aToken;
    }

    /// @notice Set a user's debt directly (for test setup).
    function setDebt(address user, address asset, uint256 amount) external {
        debtOf[user][asset] = amount;
    }

    // =========================================================
    //  Core Lending Operations
    // =========================================================

    /// @notice Deposit tokens and mint aTokens to onBehalfOf.
    /// @dev Pulls underlying from msg.sender, mints aTokens 1:1.
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 /* referralCode */) external {
        address aToken = aTokenOf[asset];
        if (aToken == address(0)) revert NoAToken();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IMintable(aToken).mint(onBehalfOf, amount);
    }

    /// @notice Burn caller's aTokens and send underlying to `to`.
    /// @dev Use type(uint256).max to withdraw entire balance.
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        address aToken = aTokenOf[asset];
        if (aToken == address(0)) revert NoAToken();

        uint256 balance = IERC20(aToken).balanceOf(msg.sender);
        uint256 withdrawAmount = amount == type(uint256).max ? balance : amount;

        IBurnable(aToken).burn(msg.sender, withdrawAmount);
        IERC20(asset).safeTransfer(to, withdrawAmount);

        return withdrawAmount;
    }

    /// @notice Pull tokens from caller and reduce onBehalfOf's debt.
    function repay(address asset, uint256 amount, uint256 /* rateMode */, address onBehalfOf) external returns (uint256) {
        uint256 debt = debtOf[onBehalfOf][asset];
        uint256 repayAmount = amount > debt ? debt : amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), repayAmount);
        debtOf[onBehalfOf][asset] -= repayAmount;

        return repayAmount;
    }

    /// @notice Send tokens to caller and increase onBehalfOf's debt.
    /// @dev If caller != onBehalfOf, requires prior credit delegation.
    ///      In real Aave, this is checked on the variable debt token.
    function borrow(address asset, uint256 amount, uint256 /* rateMode */, uint16 /* referralCode */, address onBehalfOf) external {
        if (msg.sender != onBehalfOf) {
            uint256 allowance = creditAllowance[onBehalfOf][msg.sender][asset];
            if (allowance < amount) revert InsufficientDelegation();
            creditAllowance[onBehalfOf][msg.sender][asset] = allowance - amount;
        }

        debtOf[onBehalfOf][asset] += amount;
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    /// @notice Allow delegatee to borrow `amount` of `asset` on caller's behalf.
    /// @dev Simplified vs Aave V3 (which puts this on the variable debt token).
    function approveDelegation(address asset, address delegatee, uint256 amount) external {
        creditAllowance[msg.sender][delegatee][asset] = amount;
    }
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IBurnable {
    function burn(address from, uint256 amount) external;
}
