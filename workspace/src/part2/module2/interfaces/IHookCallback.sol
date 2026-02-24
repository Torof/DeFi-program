// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IHookCallback — Simplified V4-style hook interface
/// @notice In real Uniswap V4, hooks extend BaseHook and the hook ADDRESS itself
///         encodes which callbacks are enabled (specific bits in the address must be set).
///         This simplified version uses a struct instead, so you can focus on the hook
///         logic without needing the full V4 infrastructure.
///
/// @dev Real V4 references:
///   - BaseHook: https://github.com/Uniswap/v4-periphery/blob/main/src/utils/BaseHook.sol
///   - Hooks library: https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol
///   - Hook development guide: https://docs.uniswap.org/contracts/v4/guides/hooks/your-first-hook
interface IHookCallback {
    /// @notice Swap parameters passed to the hook by the pool manager.
    /// @dev In real V4, this is IPoolManager.SwapParams plus pool context.
    struct SwapParams {
        address pool;
        bool zeroForOne;        // true = token0 → token1, false = token1 → token0
        int256 amountSpecified; // positive = exact input, negative = exact output
        uint160 sqrtPriceX96;   // current pool price BEFORE the swap
    }

    /// @notice Declares which lifecycle callbacks this hook implements.
    /// @dev In real V4, these are encoded in the hook's address bits.
    ///      The PoolManager checks the address to know which callbacks to invoke.
    struct HookPermissions {
        bool beforeSwap;
        bool afterSwap;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
    }

    /// @notice Called by the pool manager BEFORE executing a swap.
    /// @param params The swap context (pool, direction, amount, current price).
    /// @return fee The fee to charge for this swap, in hundredths of a bip (1 = 0.0001%).
    ///         Example: 3000 = 0.3%, 10000 = 1%.
    function beforeSwap(SwapParams calldata params) external returns (uint24 fee);

    /// @notice Returns which lifecycle callbacks this hook wants to receive.
    function getHookPermissions() external pure returns (HookPermissions memory);
}
