// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: ERC-4337 Paymasters
//
// Build two types of paymasters:
// 1. VerifyingPaymaster - Sponsors gas with trusted signer approval
// 2. ERC20Paymaster - Accepts ERC-20 tokens as gas payment
//
// Day 10: Gas abstraction patterns for DeFi protocols.
//
// Run: forge test --match-contract PaymastersTest -vvv
// ============================================================================

import {UserOperation} from "../exercise1-simple-smart-account/SimpleSmartAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// --- Custom Errors ---
error InvalidSignature();
error InsufficientTokenBalance();
error TransferFailed();

// =============================================================
//  Paymaster Interfaces
// =============================================================

interface IPaymaster {
    enum PostOpMode {
        opSucceeded,
        opReverted,
        postOpReverted
    }

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData);

    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external;
}

// =============================================================
//  TODO 1: Implement VerifyingPaymaster
// =============================================================
/// @notice Paymaster that sponsors gas if UserOp has valid signature from trusted signer.
contract VerifyingPaymaster is IPaymaster {
    address public immutable verifyingSigner;
    address public immutable entryPoint;

    constructor(address _entryPoint, address _signer) {
        entryPoint = _entryPoint;
        verifyingSigner = _signer;
    }

    // TODO 2: Implement validatePaymasterUserOp
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        // TODO: Implement
        // 1. Extract signature from userOp.paymasterAndData
        //    Format: [paymaster address (20 bytes)][signature (65 bytes)]
        //    bytes memory signature = userOp.paymasterAndData[20:];
        // 2. Verify signature:
        //    - Hash to sign: keccak256(abi.encode(userOpHash, maxCost))
        //    - Recover signer from signature
        //    - Check signer == verifyingSigner
        // 3. If invalid, revert InvalidSignature()
        // 4. Return empty context and 0 for validationData
        revert("Not implemented");
    }

    // TODO 3: Implement postOp (can be empty for verifying paymaster)
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external override {
        // No post-operation logic needed for simple sponsorship
    }

    receive() external payable {}
}

// =============================================================
//  TODO 4: Implement ERC20Paymaster
// =============================================================
/// @notice Paymaster that accepts ERC-20 tokens as gas payment.
contract ERC20Paymaster is IPaymaster {
    address public immutable entryPoint;
    IERC20 public immutable token;
    uint256 public immutable tokenToEthRate; // How many tokens per 1 ETH (18 decimals)

    constructor(address _entryPoint, address _token, uint256 _rate) {
        entryPoint = _entryPoint;
        token = IERC20(_token);
        tokenToEthRate = _rate;
    }

    // TODO 5: Implement validatePaymasterUserOp
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        // TODO: Implement
        // 1. Calculate required token amount:
        //    uint256 requiredTokens = (maxCost * tokenToEthRate) / 1e18;
        // 2. Check user has enough tokens:
        //    if (token.balanceOf(userOp.sender) < requiredTokens) revert InsufficientTokenBalance();
        // 3. Return context with sender address and required tokens:
        //    context = abi.encode(userOp.sender, requiredTokens);
        // 4. Return 0 for validationData
        revert("Not implemented");
    }

    // TODO 6: Implement postOp
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external override {
        // TODO: Implement
        // 1. Decode context to get sender and max token amount:
        //    (address sender, uint256 maxTokens) = abi.decode(context, (address, uint256));
        // 2. Calculate actual token cost:
        //    uint256 actualTokenCost = (actualGasCost * tokenToEthRate) / 1e18;
        // 3. Transfer tokens from sender to this paymaster:
        //    bool success = token.transferFrom(sender, address(this), actualTokenCost);
        //    if (!success) revert TransferFailed();
        // 4. Note: In production, handle mode.opReverted case carefully
        revert("Not implemented");
    }

    receive() external payable {}
}

// PROVIDED - Mock ERC20 for testing
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
