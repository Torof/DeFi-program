// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the L2GasEstimator
//  exercise. Implement L2GasEstimator.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {L2GasEstimator} from "../../../../src/part3/module7/exercise2-l2-gas-estimator/L2GasEstimator.sol";

contract L2GasEstimatorTest is Test {
    L2GasEstimator public estimator;

    function setUp() public {
        estimator = new L2GasEstimator();
    }

    // =========================================================
    //  estimateL1DataGas (TODO 1)
    // =========================================================

    function test_estimateL1DataGas_allNonZero() public view {
        // 3 non-zero bytes: 3 * 16 = 48
        bytes memory data = hex"FFAABB";
        uint256 gas = estimator.estimateL1DataGas(data);
        assertEq(gas, 48, "3 non-zero bytes = 48 gas");
    }

    function test_estimateL1DataGas_allZero() public view {
        // 4 zero bytes: 4 * 4 = 16
        bytes memory data = hex"00000000";
        uint256 gas = estimator.estimateL1DataGas(data);
        assertEq(gas, 16, "4 zero bytes = 16 gas");
    }

    function test_estimateL1DataGas_mixed() public view {
        // FF 00 FF = 2 non-zero (32) + 1 zero (4) = 36
        bytes memory data = hex"FF00FF";
        uint256 gas = estimator.estimateL1DataGas(data);
        assertEq(gas, 36, "2 non-zero + 1 zero = 36 gas");
    }

    function test_estimateL1DataGas_emptyData() public view {
        bytes memory data = "";
        uint256 gas = estimator.estimateL1DataGas(data);
        assertEq(gas, 0, "Empty data = 0 gas");
    }

    function test_estimateL1DataGas_realisticCalldata() public view {
        // Simulate a swap function selector (4 bytes, all non-zero typically)
        // + 2 addresses (20 bytes each, mostly non-zero)
        // + 2 uint256 amounts (32 bytes each, mix of zero and non-zero)
        // Total: 108 bytes
        bytes memory data = abi.encodeWithSelector(
            bytes4(0x12345678),
            address(0xdead),
            address(0xbeef),
            uint256(1e18),
            uint256(900e18)
        );
        uint256 gas = estimator.estimateL1DataGas(data);
        assertGt(gas, 0, "Realistic calldata should have non-zero gas cost");
        // Most bytes in padded encoding are zero → relatively cheaper
    }

    // =========================================================
    //  compareEncodings (TODO 2)
    // =========================================================

    function test_compareEncodings_packedSmallerThanStandard() public view {
        (uint256 stdGas, uint256 packedGas, uint256 stdBytes, uint256 packedBytes) =
            estimator.compareEncodings(
                address(0xdead),
                address(0xbeef),
                uint128(1e18),
                uint128(900e15)
            );

        assertGt(stdBytes, packedBytes, "Standard encoding should be larger");
        assertGt(stdGas, packedGas, "Standard encoding should cost more gas");
    }

    function test_compareEncodings_correctByteSizes() public view {
        (, , uint256 stdBytes, uint256 packedBytes) =
            estimator.compareEncodings(
                address(0x1111111111111111111111111111111111111111),
                address(0x2222222222222222222222222222222222222222),
                uint128(1e18),
                uint128(1e18)
            );

        // Standard: 4 * 32 = 128 bytes
        assertEq(stdBytes, 128, "Standard ABI = 4 x 32 bytes = 128");

        // Packed: 20 + 20 + 16 + 16 = 72 bytes
        assertEq(packedBytes, 72, "Packed = 20 + 20 + 16 + 16 = 72");
    }

    function test_compareEncodings_gasSavingsSignificant() public view {
        (uint256 stdGas, uint256 packedGas,,) =
            estimator.compareEncodings(
                address(0x1111111111111111111111111111111111111111),
                address(0x2222222222222222222222222222222222222222),
                uint128(1e18),
                uint128(1e18)
            );

        // Packed should save significant gas (byte ratio: 72/128 = 56%, so ~19-44% gas savings)
        uint256 savings = stdGas - packedGas;
        uint256 savingsPercent = savings * 100 / stdGas;
        assertGt(savingsPercent, 15, "Packed encoding should save >15% L1 gas");
    }

    // =========================================================
    //  shouldSplitRoute (TODO 3)
    // =========================================================

    function test_shouldSplitRoute_worthIt_largeSavings() public view {
        // Split gains 5 USDC, extra calldata is cheap
        bool split = estimator.shouldSplitRoute(
            1000e18,        // single output: 1000 USDC
            1005e18,        // split output: 1005 USDC (0.5% better)
            64,             // extra calldata: 64 bytes
            30 gwei         // L1 gas price: 30 gwei
        );
        assertTrue(split, "5 USDC gain should be worth 64 bytes of calldata at 30 gwei");
    }

    function test_shouldSplitRoute_notWorthIt_highL1Price() public view {
        // Same gain but very high L1 gas price
        bool split = estimator.shouldSplitRoute(
            1000e18,        // single output: 1000 USDC
            1000.001e18,    // split output: barely better (0.001 USDC)
            256,            // extra calldata: 256 bytes
            500 gwei        // L1 gas price: 500 gwei (very expensive)
        );
        assertFalse(split, "Tiny gain shouldn't justify 256 bytes at 500 gwei L1");
    }

    function test_shouldSplitRoute_notWorthIt_splitWorse() public view {
        // Split is actually worse (shouldn't happen in practice, but test edge case)
        bool split = estimator.shouldSplitRoute(
            1000e18,        // single output
            999e18,         // split output is WORSE
            64,
            30 gwei
        );
        assertFalse(split, "Should not split when split output is worse");
    }

    function test_shouldSplitRoute_zeroExtraCalldata() public view {
        // If no extra calldata, any gain makes it worthwhile
        bool split = estimator.shouldSplitRoute(
            1000e18,
            1000e18 + 1,    // even 1 wei better
            0,              // no extra calldata
            100 gwei
        );
        assertTrue(split, "Any gain with zero extra calldata should split");
    }

    function test_shouldSplitRoute_zeroGasPrice() public view {
        // Zero L1 gas price (post-4844 blob scenario extreme)
        bool split = estimator.shouldSplitRoute(
            1000e18,
            1000e18 + 1,    // 1 wei better
            1000,           // lots of extra calldata
            0               // free L1 gas
        );
        assertTrue(split, "Any gain with free L1 gas should split");
    }

    // =========================================================
    //  Integration: L2 Cost Model Demonstration
    // =========================================================

    function test_integration_calldataDominatesCost() public view {
        // Demonstrate that on L2, calldata size is the primary optimization target
        //
        // A typical swap tx:
        //   - Function selector: 4 bytes
        //   - Standard params: 128 bytes (4 x 32)
        //   - Total: 132 bytes
        //
        // L1 data cost at 30 gwei:
        //   ~132 * 16 * 30 gwei = 63,360 gwei = 0.00006336 ETH
        //
        // L2 execution cost:
        //   ~100,000 gas * 0.01 gwei = 1,000 gwei = 0.000001 ETH
        //
        // Ratio: L1 data cost is ~63x the L2 execution cost

        bytes memory swapCalldata = abi.encodeWithSelector(
            bytes4(0x12345678),
            address(0xdead),
            address(0xbeef),
            uint256(1e18),
            uint256(900e18)
        );

        uint256 l1DataGas = estimator.estimateL1DataGas(swapCalldata);
        uint256 l1GasPrice = 30 gwei;
        uint256 l1DataCostWei = l1DataGas * l1GasPrice;

        uint256 l2ExecutionGas = 100_000;
        uint256 l2GasPrice = 0.01 gwei;
        uint256 l2ExecutionCostWei = l2ExecutionGas * l2GasPrice;

        // L1 data cost should dominate
        assertGt(
            l1DataCostWei,
            l2ExecutionCostWei * 10,
            "L1 data cost should be >10x L2 execution cost"
        );
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_estimateL1DataGas_neverZeroForNonEmpty(bytes calldata data) public view {
        vm.assume(data.length > 0);
        uint256 gas = estimator.estimateL1DataGas(data);
        assertGt(gas, 0, "INVARIANT: non-empty data always has non-zero gas cost");
    }

    function testFuzz_shouldSplitRoute_splitWorseNeverRecommended(
        uint256 singleOutput,
        uint256 extraBytes,
        uint256 l1GasPrice
    ) public view {
        singleOutput = bound(singleOutput, 1, 1e30);
        extraBytes = bound(extraBytes, 0, 1000);
        l1GasPrice = bound(l1GasPrice, 0, 1000 gwei);

        // Split output = singleOutput (equal, not better)
        bool split = estimator.shouldSplitRoute(singleOutput, singleOutput, extraBytes, l1GasPrice);

        // If there's any extra cost, should not split for equal output
        if (extraBytes > 0 && l1GasPrice > 0) {
            assertFalse(split, "INVARIANT: equal output with extra cost should not split");
        }
    }
}
