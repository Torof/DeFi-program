// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Simple Smart Account (ERC-4337)
//
// Build a minimal smart account that implements the IAccount interface from
// ERC-4337. This demonstrates how smart accounts validate and execute
// UserOperations through the EntryPoint.
//
// This exercise uses a mock EntryPoint for learning purposes. In production,
// you'd integrate with the deployed EntryPoint contract.
//
// Run: forge test --match-contract SimpleSmartAccountTest -vvv
// ============================================================================

// --- Custom Errors ---
error NotEntryPoint();
error NotOwner();
error InvalidSignature();
error CallFailed();

// =============================================================
//  ERC-4337 Interfaces
// =============================================================

/// @notice UserOperation struct from ERC-4337
struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

/// @notice Core account interface
interface IAccount {
    /// @notice Validates a UserOperation
    /// @param userOp The operation to validate
    /// @param userOpHash Hash of the operation (for signature verification)
    /// @param missingAccountFunds Funds needed to be deposited to EntryPoint
    /// @return validationData Packed validation data (validAfter | validUntil | authorizer)
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);
}

/// @notice Minimal EntryPoint interface
interface IEntryPoint {
    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external;
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
}

// =============================================================
//  TODO 1: Implement SimpleSmartAccount
// =============================================================
/// @notice Basic smart account with single-owner ECDSA validation.
/// @dev Implements IAccount for ERC-4337 compatibility.
contract SimpleSmartAccount is IAccount {
    address public immutable entryPoint;
    address public owner;
    uint256 public nonce;

    event SimpleAccountInitialized(address indexed owner);
    event Executed(address indexed target, uint256 value, bytes data);

    constructor(address _entryPoint, address _owner) {
        entryPoint = _entryPoint;
        owner = _owner;
        emit SimpleAccountInitialized(_owner);
    }

    // =============================================================
    //  TODO 2: Implement validateUserOp
    // =============================================================
    /// @notice Validates a UserOperation.
    /// @dev Called by EntryPoint during the validation phase.
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override returns (uint256 validationData) {
        // TODO: Implement
        // 1. Check that msg.sender == entryPoint (revert NotEntryPoint() if not)
        // 2. Verify the signature:
        //    a. Recover signer from userOpHash and userOp.signature
        //    b. Check that recovered signer == owner
        //    c. If invalid, return SIG_VALIDATION_FAILED (1)
        // 3. If missingAccountFunds > 0, pay the EntryPoint:
        //    payable(entryPoint).call{value: missingAccountFunds}("")
        // 4. Return 0 for successful validation
        //
        // Hint: Use _validateSignature helper function
        // Hint: validationData = 0 means valid signature
        //       validationData = 1 means invalid signature (SIG_VALIDATION_FAILED)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement _validateSignature helper
    // =============================================================
    /// @notice Validates that the signature is from the owner.
    /// @param userOpHash The hash to verify
    /// @param signature The signature (65 bytes: r, s, v)
    /// @return validationData 0 if valid, 1 if invalid
    function _validateSignature(bytes32 userOpHash, bytes memory signature)
        internal
        view
        returns (uint256 validationData)
    {
        // TODO: Implement
        // 1. Extract r, s, v from signature
        //    bytes32 r = bytes32(signature[0:32]);
        //    bytes32 s = bytes32(signature[32:64]);
        //    uint8 v = uint8(signature[64]);
        // 2. Recover signer using ecrecover:
        //    address signer = ecrecover(userOpHash, v, r, s);
        // 3. If signer == owner, return 0
        // 4. Otherwise, return 1 (SIG_VALIDATION_FAILED)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement execute function
    // =============================================================
    /// @notice Executes a call to an external contract.
    /// @dev Called by EntryPoint during the execution phase.
    /// @param dest Destination address
    /// @param value ETH value to send
    /// @param func Calldata to execute
    function execute(address dest, uint256 value, bytes calldata func) external {
        // TODO: Implement
        // 1. Check that msg.sender == entryPoint (revert NotEntryPoint())
        // 2. Increment nonce
        // 3. Execute the call: (bool success, bytes memory result) = dest.call{value: value}(func)
        // 4. If call failed, revert CallFailed()
        // 5. Emit Executed event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement executeBatch function
    // =============================================================
    /// @notice Executes multiple calls in one transaction.
    /// @param dest Array of destination addresses
    /// @param value Array of ETH values
    /// @param func Array of calldata
    function executeBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) external {
        // TODO: Implement
        // 1. Check that msg.sender == entryPoint
        // 2. Check that all arrays have the same length
        // 3. Increment nonce
        // 4. Loop through and execute each call
        // 5. Emit Executed event for each call
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement helper functions
    // =============================================================

    /// @notice Gets the current nonce for this account.
    function getNonce() external view returns (uint256) {
        // TODO: Return current nonce
        revert("Not implemented");
    }

    /// @notice Gets the hash of a UserOperation for signature verification.
    /// @dev This should match the hash computed by the EntryPoint.
    function getUserOpHash(UserOperation calldata userOp) public pure returns (bytes32) {
        // TODO: Implement
        // Return keccak256(abi.encode(userOp))
        // Note: In real ERC-4337, this includes chainId and entryPoint address
        revert("Not implemented");
    }

    /// @notice Allows account to receive ETH.
    receive() external payable {}
}

// =============================================================
//  PROVIDED — Mock EntryPoint for testing
// =============================================================
/// @notice Simplified EntryPoint for learning purposes.
/// @dev In production, use the deployed EntryPoint contract.
contract MockEntryPoint {
    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success
    );

    /// @notice Handles a batch of UserOperations.
    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external {
        for (uint256 i = 0; i < ops.length; i++) {
            UserOperation calldata op = ops[i];

            // Get the account
            IAccount account = IAccount(op.sender);

            // Compute userOpHash (excludes signature to avoid circular dependency,
            // matching real ERC-4337 behavior)
            bytes32 userOpHash = keccak256(abi.encode(
                op.sender, op.nonce, op.initCode, op.callData,
                op.callGasLimit, op.verificationGasLimit, op.preVerificationGas,
                op.maxFeePerGas, op.maxPriorityFeePerGas, op.paymasterAndData,
                bytes("")
            ));

            // Validation phase: call validateUserOp
            uint256 validationData = account.validateUserOp(op, userOpHash, 0);

            // If validation failed, skip execution
            if (validationData != 0) {
                emit UserOperationEvent(userOpHash, op.sender, address(0), op.nonce, false);
                continue;
            }

            // Execution phase: call the account with callData
            (bool success,) = op.sender.call(op.callData);

            emit UserOperationEvent(userOpHash, op.sender, address(0), op.nonce, success);
        }
    }

    function getNonce(address sender, uint192) external view returns (uint256) {
        return SimpleSmartAccount(payable(sender)).nonce();
    }
}

// =============================================================
//  PROVIDED — Helper for creating UserOperations
// =============================================================
library UserOpHelper {
    function createUserOp(
        address sender,
        uint256 nonce,
        bytes memory callData,
        bytes memory signature
    ) internal pure returns (UserOperation memory) {
        return UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: callData,
            callGasLimit: 200000,
            verificationGasLimit: 150000,
            preVerificationGas: 21000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: "",
            signature: signature
        });
    }
}
