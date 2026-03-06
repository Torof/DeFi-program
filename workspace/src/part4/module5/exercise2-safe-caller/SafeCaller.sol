// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SafeCaller — Error Handling & Safety Patterns
/// @notice Exercise for Module 5: External Calls in Assembly
/// @dev Practice the SafeERC20 pattern, error bubbling, and returnbomb defense.
///      Each function handles a different failure mode that production DeFi code
///      must account for.
///
/// Error Selectors (provided):
///   TransferFailed()       → 0x90b8ec18
///   TransferFromFailed()   → 0x7939f424
contract SafeCaller {
    // ================================================================
    // TODO 1: bubbleRevert(address target, bytes calldata data)
    // ================================================================
    // Call `target` with arbitrary calldata. If the call succeeds, return.
    // If it fails, bubble the callee's revert data exactly.
    //
    // Steps:
    //   1. Copy calldata to memory:
    //      - let size := data.length
    //      - calldatacopy(0x00, data.offset, size)
    //   2. Make the call:
    //      - let ok := call(gas(), target, 0, 0x00, size, 0, 0)
    //   3. If failed, bubble the revert data:
    //      - let rds := returndatasize()
    //      - returndatacopy(0x00, 0, rds)
    //      - revert(0x00, rds)
    //
    // This is the standard error propagation pattern. Every aggregator router
    // (1inch, Paraswap) uses this to try a DEX, catch the error, and try the next.
    //
    // Opcodes: calldatacopy, call, iszero, returndatasize, returndatacopy, revert
    // See: Module 5 > Error Propagation: Bubbling Revert Data (#error-propagation)
    function bubbleRevert(address target, bytes calldata data) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 2: safeTransfer(address token, address to, uint256 amount)
    // ================================================================
    // The SafeERC20 transfer pattern — must work with BOTH:
    //   - Standard tokens (return true on success)
    //   - Non-returning tokens like USDT (return nothing on success)
    //
    // Steps:
    //   1. Encode calldata for transfer(address,uint256):
    //      - Selector: 0xa9059cbb
    //      - mstore(0x00, shl(224, 0xa9059cbb))
    //      - mstore(0x04, to)
    //      - mstore(0x24, amount)
    //   2. Make the call:
    //      - let ok := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
    //        (write up to 32 bytes of return data to 0x00)
    //   3. Check the compound condition:
    //      - and(ok, or(iszero(returndatasize()), eq(mload(0x00), 1)))
    //      - This is the key insight: accept EITHER no return data (USDT)
    //        OR return data that decodes to true (standard ERC-20)
    //   4. If the check fails, revert with TransferFailed():
    //      - mstore(0x00, shl(224, 0x90b8ec18))
    //      - revert(0x00, 0x04)
    //
    // Truth table (from the lesson):
    //   Call reverts  → ok=0 → and(0, ...) = 0 → revert ✓
    //   Returns false → ok=1, rds=32, mload=0 → and(1, or(0,0)) = 0 → revert ✓
    //   Returns true  → ok=1, rds=32, mload=1 → and(1, or(0,1)) = 1 → success ✓
    //   Returns empty → ok=1, rds=0           → and(1, or(1,_)) = 1 → success ✓
    //
    // Opcodes: mstore, shl, call, iszero, returndatasize, eq, mload, or, and, revert
    // See: Module 5 > The SafeERC20 Pattern (#safe-erc20)
    function safeTransfer(address token, address to, uint256 amount) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 3: safeTransferFrom(address token, address from, address to, uint256 amount)
    // ================================================================
    // Same SafeERC20 pattern but for transferFrom(address,address,uint256).
    // Three args instead of two — the calldata is 100 bytes (4 + 32 + 32 + 32).
    //
    // Steps:
    //   1. Encode calldata for transferFrom(address,address,uint256):
    //      - Selector: 0x23b872dd
    //      - mstore(0x00, shl(224, 0x23b872dd))
    //      - mstore(0x04, from)
    //      - mstore(0x24, to)
    //      - mstore(0x44, amount)
    //   2. Make the call:
    //      - let ok := call(gas(), token, 0, 0x00, 0x64, 0x00, 0x20)
    //        (0x64 = 100 bytes: 4 selector + 3 × 32 args)
    //   3. Same compound check as safeTransfer:
    //      - and(ok, or(iszero(returndatasize()), eq(mload(0x00), 1)))
    //   4. Revert with TransferFromFailed() on failure:
    //      - Selector: 0x7939f424
    //
    // Opcodes: same as TODO 2
    // See: Module 5 > The SafeERC20 Pattern (#safe-erc20)
    function safeTransferFrom(address token, address from, address to, uint256 amount) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 4: boundedCall(address target, bytes calldata data)
    // ================================================================
    // Call `target` with arbitrary calldata. If the call fails, bubble
    // the revert data BUT cap the copy at 256 bytes (returnbomb defense).
    //
    // This is identical to bubbleRevert (TODO 1) except for one critical
    // difference: you must NOT copy all of returndatasize() blindly.
    // A malicious target could return megabytes of data, causing quadratic
    // memory expansion costs that exhaust the caller's gas.
    //
    // Steps:
    //   1. Copy calldata and make the call (same as TODO 1)
    //   2. If failed:
    //      - let rds := returndatasize()
    //      - Cap it: if gt(rds, 0x100) { rds := 0x100 }
    //        (0x100 = 256 bytes — enough for any standard error)
    //      - returndatacopy(0x00, 0, rds)
    //      - revert(0x00, rds)
    //   3. On success: also cap and store the return data for the caller.
    //      - let rds := returndatasize()
    //      - if gt(rds, 0x100) { rds := 0x100 }
    //      - returndatacopy(0x00, 0, rds)
    //      - return(0x00, rds)
    //
    // Why 256 bytes? Standard errors: Error(string) uses ~100 bytes for short
    // messages, Panic(uint256) uses 36 bytes, custom errors rarely exceed 256.
    // Any legitimate error fits; a returnbomb doesn't get copied.
    //
    // Opcodes: calldatacopy, call, iszero, returndatasize, gt, returndatacopy, revert, return
    // See: Module 5 > The Returnbomb Attack (#returnbomb)
    function boundedCall(address target, bytes calldata data) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}
