// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for JumpDispatcher.
/// Your task is to implement the contract in JumpDispatcher.sol so all tests pass.

import "forge-std/Test.sol";
import {JumpDispatcher} from "../../../../src/part4/module6/exercise3-jump-dispatcher/JumpDispatcher.sol";
import {LinearDispatcher} from "../../../../src/part4/module6/exercise3-jump-dispatcher/LinearDispatcher.sol";

/// @dev Interface matching the 8 functions in LinearDispatcher.
/// Used to call JumpDispatcher via its fallback with the correct selectors.
interface IDispatcher {
    function getA() external pure returns (uint256);
    function getB() external pure returns (uint256);
    function getC() external pure returns (uint256);
    function getD() external pure returns (uint256);
    function getE() external pure returns (uint256);
    function getF() external pure returns (uint256);
    function getG() external pure returns (uint256);
    function getH() external pure returns (uint256);
}

contract JumpDispatcherTest is Test {
    JumpDispatcher internal jump;
    LinearDispatcher internal linear;

    // Cast JumpDispatcher to the IDispatcher interface so we can call
    // getA()..getH() on it — these go through the fallback.
    IDispatcher internal jumpAsInterface;

    function setUp() public {
        jump = new JumpDispatcher();
        linear = new LinearDispatcher();
        jumpAsInterface = IDispatcher(address(jump));
    }

    // =========================================================================
    // Selector verification — ensures the scaffold's selectors are correct
    // =========================================================================

    function test_SelectorVerification() public pure {
        assertEq(IDispatcher.getA.selector, bytes4(0xd46300fd), "getA selector");
        assertEq(IDispatcher.getB.selector, bytes4(0xa1c51915), "getB selector");
        assertEq(IDispatcher.getC.selector, bytes4(0xa2375d1e), "getC selector");
        assertEq(IDispatcher.getD.selector, bytes4(0x1a14ff7a), "getD selector");
        assertEq(IDispatcher.getE.selector, bytes4(0xb1cb267b), "getE selector");
        assertEq(IDispatcher.getF.selector, bytes4(0x0c204dbc), "getF selector");
        assertEq(IDispatcher.getG.selector, bytes4(0x04c09ce9), "getG selector");
        assertEq(IDispatcher.getH.selector, bytes4(0x82529fdb), "getH selector");
    }

    // =========================================================================
    // Correctness — each function returns the right value
    // =========================================================================

    function test_GetA_returns1() public {
        assertEq(jumpAsInterface.getA(), 1, "getA should return 1");
    }

    function test_GetB_returns2() public {
        assertEq(jumpAsInterface.getB(), 2, "getB should return 2");
    }

    function test_GetC_returns3() public {
        assertEq(jumpAsInterface.getC(), 3, "getC should return 3");
    }

    function test_GetD_returns4() public {
        assertEq(jumpAsInterface.getD(), 4, "getD should return 4");
    }

    function test_GetE_returns5() public {
        assertEq(jumpAsInterface.getE(), 5, "getE should return 5");
    }

    function test_GetF_returns6() public {
        assertEq(jumpAsInterface.getF(), 6, "getF should return 6");
    }

    function test_GetG_returns7() public {
        assertEq(jumpAsInterface.getG(), 7, "getG should return 7");
    }

    function test_GetH_returns8() public {
        assertEq(jumpAsInterface.getH(), 8, "getH should return 8");
    }

    // =========================================================================
    // Match LinearDispatcher — values must be identical
    // =========================================================================

    function test_AllValues_matchLinearDispatcher() public {
        assertEq(jumpAsInterface.getA(), linear.getA(), "getA mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getB(), linear.getB(), "getB mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getC(), linear.getC(), "getC mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getD(), linear.getD(), "getD mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getE(), linear.getE(), "getE mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getF(), linear.getF(), "getF mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getG(), linear.getG(), "getG mismatch vs LinearDispatcher");
        assertEq(jumpAsInterface.getH(), linear.getH(), "getH mismatch vs LinearDispatcher");
    }

    // =========================================================================
    // Unknown selector — fallback should revert
    // =========================================================================

    function test_UnknownSelector_reverts() public {
        // Call with a selector that doesn't match any of the 8 functions.
        (bool ok,) = address(jump).call(abi.encodeWithSelector(bytes4(0xdeadbeef)));
        assertFalse(ok, "Unknown selector should revert");
    }

    function test_EmptyCalldata_reverts() public {
        // Call with no calldata — selector extraction produces 0x00000000.
        (bool ok,) = address(jump).call("");
        assertFalse(ok, "Empty calldata should revert");
    }

    // =========================================================================
    // Gas comparison — informational (not a pass/fail criterion)
    // =========================================================================

    function test_GasComparison_logDispatchCosts() public {
        // Measure dispatch gas for the first and last function in each contract.
        // This is informational — the test always passes.

        uint256 gasBeforeJumpA = gasleft();
        jumpAsInterface.getA();
        uint256 gasJumpA = gasBeforeJumpA - gasleft();

        uint256 gasBeforeJumpH = gasleft();
        jumpAsInterface.getH();
        uint256 gasJumpH = gasBeforeJumpH - gasleft();

        uint256 gasBeforeLinearA = gasleft();
        linear.getA();
        uint256 gasLinearA = gasBeforeLinearA - gasleft();

        uint256 gasBeforeLinearH = gasleft();
        linear.getH();
        uint256 gasLinearH = gasBeforeLinearH - gasleft();

        emit log_named_uint("JumpDispatcher.getA() gas", gasJumpA);
        emit log_named_uint("JumpDispatcher.getH() gas", gasJumpH);
        emit log_named_uint("LinearDispatcher.getA() gas", gasLinearA);
        emit log_named_uint("LinearDispatcher.getH() gas", gasLinearH);
        emit log_named_uint("Jump: H-A gas delta", gasJumpH > gasJumpA ? gasJumpH - gasJumpA : gasJumpA - gasJumpH);
        emit log_named_uint("Linear: H-A gas delta", gasLinearH > gasLinearA ? gasLinearH - gasLinearA : gasLinearA - gasLinearH);
    }
}
