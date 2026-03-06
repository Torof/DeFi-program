// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title AssemblyRouter — Production Call Patterns
/// @notice Exercise for Module 5: External Calls in Assembly
/// @dev Practice DELEGATECALL proxy forwarding, precompile calls (ecrecover),
///      and the multicall pattern. These are the patterns you'll find in
///      virtually every production DeFi protocol.
///
/// Error Selectors (provided):
///   SwapFailed()            → 0x81ceff30
///   RecoverFailed()         → 0x74e6fd08
///   MultiCallFailed(uint256) → 0x5c7b055c
contract AssemblyRouter {
    // ================================================================
    // TODO 1: proxyForward(address impl, bytes calldata data)
    // ================================================================
    // Implement the proxy forwarding pattern: copy the inner calldata to
    // memory, DELEGATECALL the implementation, forward return data or
    // revert data.
    //
    // In a real proxy, this logic lives in a fallback() and copies ALL
    // calldata. Here, `data` contains the encoded call for the implementation
    // (e.g., abi.encodeWithSelector(impl.someFunction.selector, args...)).
    // The core pattern is identical:
    //   copy to memory → delegatecall → forward return/revert
    //
    // Steps:
    //   1. Copy the inner calldata to memory at offset 0:
    //      - calldatacopy(0x00, data.offset, data.length)
    //   2. DELEGATECALL the implementation:
    //      - let ok := delegatecall(gas(), impl, 0x00, data.length, 0, 0)
    //   3. Copy return data to offset 0:
    //      - let rds := returndatasize()
    //      - returndatacopy(0x00, 0, rds)
    //   4. Branch on success:
    //      - If ok: return(0x00, rds)
    //      - If not: revert(0x00, rds)
    //
    // Why offset 0 is safe: after the return/revert, no Solidity code runs,
    // so overwriting the free memory pointer doesn't matter.
    //
    // Why the assembly `return` is needed: it sends the implementation's raw
    // return bytes back to the caller, bypassing Solidity's ABI encoding.
    // The caller decodes the bytes as if they came from the implementation.
    //
    // Opcodes: calldatacopy, delegatecall, returndatasize,
    //          returndatacopy, return, revert
    // See: Module 5 > DELEGATECALL in Depth (#delegatecall-depth)
    function proxyForward(address impl, bytes calldata data) external payable {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 2: swapExactIn(address pool, address tokenIn, address tokenOut, uint256 amountIn)
    // ================================================================
    // Encode calldata for MockPool.swap(address,address,uint256), make a
    // CALL, decode and return the uint256 amountOut.
    //
    // Steps:
    //   1. Compute the selector: bytes4(keccak256("swap(address,address,uint256)"))
    //      → 0xdf791e50
    //   2. Encode calldata at scratch space + beyond (4 + 3×32 = 100 bytes):
    //      - mstore(0x00, shl(224, 0xdf791e50))
    //      - mstore(0x04, tokenIn)
    //      - mstore(0x24, tokenOut)
    //      - mstore(0x44, amountIn)
    //   3. CALL (not STATICCALL — swap modifies state):
    //      - let ok := call(gas(), pool, 0, 0x00, 0x64, 0x00, 0x20)
    //        (0x64 = 100 bytes, return slot at 0x00 for 32 bytes)
    //   4. Check success — revert with SwapFailed() if it fails:
    //      - mstore(0x00, shl(224, 0x81ceff30))
    //      - revert(0x00, 0x04)
    //   5. Decode: amountOut := mload(0x00)
    //
    // Opcodes: mstore, shl, call, iszero, mload, revert
    // See: Module 5 > The Call Lifecycle (#call-lifecycle)
    function swapExactIn(address pool, address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 3: recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
    // ================================================================
    // Call the ecrecover precompile (address 0x01) via STATICCALL.
    //
    // Steps:
    //   1. Load the free memory pointer: let fmp := mload(0x40)
    //   2. Write the 4 arguments to FMP-allocated memory (128 bytes):
    //      - mstore(fmp, hash)
    //      - mstore(add(fmp, 0x20), v)    ← v is uint8 but stored as uint256
    //      - mstore(add(fmp, 0x40), r)
    //      - mstore(add(fmp, 0x60), s)
    //   3. STATICCALL the ecrecover precompile:
    //      - let ok := staticcall(gas(), 0x01, fmp, 0x80, fmp, 0x20)
    //        (input: 128 bytes, output: 32 bytes written back to fmp)
    //   4. Check success — revert with RecoverFailed() if it fails
    //   5. Load the result: let recovered := mload(fmp)
    //   6. Check for address(0) — ecrecover returns 0 for invalid signatures:
    //      - if iszero(recovered) → revert with RecoverFailed()
    //   7. Assign: signer := recovered
    //
    // Why FMP instead of scratch space?
    //   Writing 128 bytes to 0x00 would overwrite the free memory pointer
    //   at 0x40 and the zero slot at 0x60. Using FMP avoids this.
    //   We don't need to update FMP here because the only Solidity code
    //   after the assembly block is `signer := recovered` (no allocations).
    //
    // Opcodes: mload, mstore, add, staticcall, iszero, shl, revert
    // See: Module 5 > Precompile Calls: ecrecover in Assembly (#precompile-calls)
    function recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        external
        view
        returns (address signer)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 4: multiCall(bytes[] calldata data)
    // ================================================================
    // Loop through an array of encoded function calls and DELEGATECALL
    // each one to address(this). Collect the results into a bytes[] array
    // and return it.
    //
    // This is the Uniswap V3 Multicall pattern: DELEGATECALL to self
    // preserves msg.sender, so inner functions see the real caller.
    //
    // The Solidity boilerplate (array allocation, loop, result assignment)
    // is provided — you write the assembly that performs the DELEGATECALL
    // and handles errors.
    //
    // Memory layout for each result and the outer array:
    //
    //   resultPtr → [ length (32 bytes) ][ data (rds bytes) ][ padding to 32-byte boundary ]
    //   results   → [ length ] [ ptr₀ ] [ ptr₁ ] ... [ ptrₙ₋₁ ]
    //
    // Inside the assembly block for each iteration:
    //   1. Allocate memory for the element's calldata:
    //      - let ptr := mload(0x40)
    //      - calldatacopy(ptr, elemData.offset, elemData.length)
    //   2. DELEGATECALL to self:
    //      - let ok := delegatecall(gas(), address(), ptr, elemData.length, 0, 0)
    //   3. On failure, revert with MultiCallFailed(i):
    //      - mstore(0x00, shl(224, 0x5c7b055c))
    //      - mstore(0x04, i)
    //      - revert(0x00, 0x24)
    //   4. Copy return data to a new memory allocation:
    //      - let rds := returndatasize()
    //      - let resultPtr := mload(0x40)
    //      - mstore(resultPtr, rds)                         // bytes length
    //      - returndatacopy(add(resultPtr, 0x20), 0, rds)   // bytes data
    //      - mstore(0x40, and(add(add(resultPtr, 0x3f), rds), not(0x1f)))  // update FMP (32-byte aligned)
    //      - Store resultPtr into the results array:
    //        mstore(add(add(results, 0x20), mul(i, 0x20)), resultPtr)
    //        (results is the Solidity memory pointer for the bytes[] array)
    //
    // Opcodes: mload, mstore, calldatacopy, delegatecall, address,
    //          returndatasize, returndatacopy, shl, iszero, add, mul, and, not, revert
    // See: Module 5 > The Multicall Pattern (#multicall)
    function multiCall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);

        for (uint256 i = 0; i < data.length; i++) {
            bytes calldata elemData = data[i];

            assembly {
                revert(0, 0) // TODO: replace with implementation
            }
        }
    }

    // ================================================================
    // Helpers (provided for testing — NOT TODOs)
    // ================================================================

    /// @dev Simple function for multicall testing: returns msg.sender.
    function getSender() external view returns (address) {
        return msg.sender;
    }

    /// @dev Simple function for multicall testing: returns a value.
    function echo(uint256 x) external pure returns (uint256) {
        return x;
    }
}
