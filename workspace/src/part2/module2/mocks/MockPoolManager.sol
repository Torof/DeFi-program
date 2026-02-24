// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHookCallback} from "../interfaces/IHookCallback.sol";

/// @title MockPoolManager — Simulates V4 PoolManager calling hooks
/// @notice In real Uniswap V4, the PoolManager is a singleton that manages all pools.
///         During a swap, it checks the pool's hook address and calls the appropriate
///         lifecycle callbacks. This mock replicates that flow for testing.
///
/// @dev Real V4 reference:
///   - PoolManager: https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol
contract MockPoolManager {
    IHookCallback public hook;

    /// @notice The fee returned by the hook on the last swap.
    uint24 public lastFee;

    error HookNotSet();
    error BeforeSwapNotEnabled();

    constructor(address _hook) {
        hook = IHookCallback(_hook);
    }

    /// @notice Simulates a swap that triggers the hook's beforeSwap callback.
    /// @dev In real V4, this happens inside PoolManager.swap() after unlock().
    ///      The manager checks hook permissions, calls beforeSwap, executes the swap
    ///      math, then calls afterSwap. We only simulate the beforeSwap part.
    function executeSwap(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceX96
    ) external returns (uint24 fee) {
        if (address(hook) == address(0)) revert HookNotSet();

        // Check permissions (in real V4, this is done by inspecting address bits)
        IHookCallback.HookPermissions memory perms = hook.getHookPermissions();
        if (!perms.beforeSwap) revert BeforeSwapNotEnabled();

        // Call the hook
        fee = hook.beforeSwap(
            IHookCallback.SwapParams({
                pool: pool,
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceX96: sqrtPriceX96
            })
        );

        lastFee = fee;
    }
}
