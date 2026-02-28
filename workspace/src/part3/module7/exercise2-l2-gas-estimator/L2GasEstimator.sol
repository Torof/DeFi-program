// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE 2: L2 Gas Estimator
//
// Build a utility that estimates L1 data costs for different calldata encodings,
// proving quantitatively that calldata size is the dominant cost on L2 and
// understanding when routing optimizations are worth the extra calldata.
//
// Concepts exercised:
//   - L1 data cost calculation (16 gas per non-zero byte, 4 per zero byte)
//   - Calldata optimization (packed vs standard ABI encoding)
//   - Break-even analysis: better routing vs more calldata
//   - The L2 cost model that flips L1 optimization priorities
//
// Key references:
//   - Module 7 lesson: "The L2 Gas Model" section
//   - Module 7 lesson: CalldataCostDemo Quick Try
//   - EIP-4844 impact on blob vs calldata pricing
//
// Run: forge test --match-contract L2GasEstimatorTest -vvv
// ============================================================================

/// @notice Utility for estimating and comparing L1 data costs on L2.
/// @dev Pre-built: constants.
///      Student implements: estimateL1DataGas, compareEncodings, shouldSplitRoute.
contract L2GasEstimator {
    // --- Constants ---
    /// @dev Gas cost per non-zero byte of calldata (EIP-2028)
    uint256 public constant GAS_PER_NON_ZERO_BYTE = 16;

    /// @dev Gas cost per zero byte of calldata
    uint256 public constant GAS_PER_ZERO_BYTE = 4;

    // =============================================================
    //  TODO 1: Implement estimateL1DataGas
    // =============================================================
    /// @notice Estimate the L1 data gas cost for arbitrary calldata.
    /// @dev On L2, every transaction posts its calldata to L1. The cost is:
    ///        total_gas = (non_zero_bytes * 16) + (zero_bytes * 4)
    ///
    ///      This is the DOMINANT cost on L2 — often 90%+ of total tx cost.
    ///
    ///      Steps:
    ///        1. Iterate through each byte of `data`
    ///        2. For each byte: if zero, add 4 gas; if non-zero, add 16 gas
    ///        3. Return the total gas estimate
    ///
    ///      Numeric example:
    ///        data = 0xFF00FF (3 bytes: 2 non-zero, 1 zero)
    ///        gas = 2*16 + 1*4 = 36
    ///
    ///      Hint: Access individual bytes with data[i] and compare to 0.
    ///
    /// @param data The bytes to estimate L1 data gas for
    /// @return gasEstimate The estimated L1 data gas cost
    function estimateL1DataGas(bytes memory data)
        public
        pure
        returns (uint256 gasEstimate)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement compareEncodings
    // =============================================================
    /// @notice Compare packed vs standard ABI encoding for swap parameters.
    /// @dev Standard ABI encoding pads every parameter to 32 bytes.
    ///      Packed encoding uses the minimum bytes needed.
    ///
    ///      For a swap with (address tokenIn, address tokenOut, uint128 amountIn, uint128 minOut):
    ///
    ///      Standard ABI encoding (abi.encode):
    ///        4 × 32 bytes = 128 bytes  (addresses padded to 32B, uint128s padded to 32B)
    ///
    ///      Packed encoding (abi.encodePacked):
    ///        20 + 20 + 16 + 16 = 72 bytes  (actual sizes, no padding)
    ///
    ///      Steps:
    ///        1. Create standard encoding: abi.encode(tokenIn, tokenOut, amountIn, minOut)
    ///        2. Create packed encoding: abi.encodePacked(tokenIn, tokenOut, amountIn, minOut)
    ///        3. Estimate L1 gas for each using estimateL1DataGas()
    ///        4. Return both gas estimates and the byte sizes
    ///
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Amount of input token (uint128 for packed efficiency)
    /// @param minOut Minimum output (uint128 for packed efficiency)
    /// @return standardGas L1 gas for standard ABI encoding
    /// @return packedGas L1 gas for packed encoding
    /// @return standardBytes Size of standard encoding
    /// @return packedBytes Size of packed encoding
    function compareEncodings(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 minOut
    )
        public
        pure
        returns (
            uint256 standardGas,
            uint256 packedGas,
            uint256 standardBytes,
            uint256 packedBytes
        )
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement shouldSplitRoute
    // =============================================================
    /// @notice Determine if splitting a route is worth the extra calldata cost.
    /// @dev On L1: more routing hops = more gas, so keep it simple.
    ///      On L2: execution is cheap but calldata is expensive.
    ///
    ///      The tradeoff:
    ///        Split gives better output (less price impact)
    ///        BUT split requires more calldata (two pool addresses instead of one)
    ///
    ///      Break-even formula:
    ///        outputGain = splitOutput - singleOutput  (in token units)
    ///        extraL1Cost = extraCalldataBytes * avgGasPerByte * l1GasPrice
    ///        Split is worth it when: outputGain > extraL1Cost
    ///
    ///      For simplicity, use avgGasPerByte = GAS_PER_NON_ZERO_BYTE (16)
    ///      as a conservative estimate (most calldata bytes are non-zero).
    ///
    ///      IMPORTANT SIMPLIFICATION: This comparison works for demonstration
    ///      purposes but is dimensionally simplified — it compares token amounts
    ///      (output gain) against wei (L1 cost). A production implementation
    ///      would need a price oracle to convert both to a common unit (e.g., USD).
    ///
    ///      Steps:
    ///        1. If splitOutput <= singleOutput, return false (no gain to offset cost)
    ///        2. Calculate outputGain = splitOutput - singleOutput
    ///        3. Calculate extraL1Cost = extraCalldataBytes * 16 * l1GasPrice
    ///        4. Return outputGain > extraL1Cost
    ///
    ///      Numeric example:
    ///        singleOutput = 1000 USDC
    ///        splitOutput  = 1005 USDC (0.5% better)
    ///        extraCalldata = 64 bytes (one extra pool address + amounts)
    ///        l1GasPrice = 30 gwei
    ///        extraCost = 64 * 16 * 30 gwei = 30,720 gwei = 0.00003072 ETH
    ///        At $2000/ETH: $0.06 cost for $5 gain → SPLIT (worth it)
    ///
    /// @param singleOutput Output from single-pool route (in token units)
    /// @param splitOutput Output from split route (in token units)
    /// @param extraCalldataBytes Additional calldata bytes for split route
    /// @param l1GasPrice Current L1 gas price (in wei)
    /// @return True if splitting produces a net benefit
    function shouldSplitRoute(
        uint256 singleOutput,
        uint256 splitOutput,
        uint256 extraCalldataBytes,
        uint256 l1GasPrice
    ) public pure returns (bool) {
        // YOUR CODE HERE
    }
}
