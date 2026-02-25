// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built mock DEX for the AutoCompounder exercise.
//  A minimal 1:1 swap router. Must be pre-funded with output tokens in tests.
// ============================================================================

/// @notice Minimal mock swap — exchanges tokenIn for tokenOut at 1:1 rate.
/// @dev Used by AutoCompounder tests. Must hold sufficient tokenOut balance.
contract MockSwap {
    using SafeERC20 for IERC20;

    /// @notice Swap tokenIn for tokenOut at 1:1 rate.
    /// @dev Pulls tokenIn from caller, sends equal tokenOut back.
    ///      Reverts if this contract doesn't hold enough tokenOut.
    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        amountOut = amountIn;
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOut.safeTransfer(msg.sender, amountOut);
    }
}
