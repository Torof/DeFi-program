// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Permit2 Integration Vault
//
// Integrate with Uniswap's Permit2 contract to support both SignatureTransfer
// and AllowanceTransfer permit modes. This demonstrates how modern DeFi
// protocols leverage Permit2 for universal, gasless approvals.
//
// The vault will fork mainnet to interact with the deployed Permit2 contract.
//
// Run: forge test --match-contract Permit2VaultTest --fork-url $MAINNET_RPC_URL -vvv
// ============================================================================

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// --- Custom Errors ---
error InsufficientBalance();
error TransferFailed();
error InvalidWitnessData();

// =============================================================
//  Permit2 Interfaces
// =============================================================

/// @notice SignatureTransfer mode — one-time, stateless permits
interface ISignatureTransfer {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    /// @notice Extended version with witness data
    function permitWitnessTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;
}

/// @notice AllowanceTransfer mode — persistent, time-bounded allowances
interface IAllowanceTransfer {
    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    struct PermitSingle {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    function permit(
        address owner,
        PermitSingle memory permitSingle,
        bytes calldata signature
    ) external;

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external;
}

/// @notice Combined Permit2 interface
interface IPermit2 is ISignatureTransfer, IAllowanceTransfer {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// =============================================================
//  TODO 1: Implement Permit2Vault
// =============================================================
/// @notice Vault that integrates with Permit2 for deposits.
contract Permit2Vault {
    IPermit2 public immutable permit2;

    // TODO: Add state variables for tracking balances
    // Hint: mapping(address user => mapping(address token => uint256 balance)) public balances;

    constructor(address _permit2) {
        permit2 = IPermit2(_permit2);
    }

    // =============================================================
    //  TODO 2: Implement depositWithSignatureTransfer
    // =============================================================
    /// @notice Deposits tokens using Permit2 SignatureTransfer.
    /// @dev User signs a one-time permit, vault calls permitTransferFrom.
    /// @param token The token address
    /// @param amount The amount to deposit
    /// @param nonce The permit nonce (from user's signature)
    /// @param deadline The permit deadline
    /// @param signature The user's EIP-712 signature
    function depositWithSignatureTransfer(
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        // TODO: Implement
        // 1. Build the PermitTransferFrom struct
        // 2. Build the SignatureTransferDetails struct (to: address(this), requestedAmount: amount)
        // 3. Call permit2.permitTransferFrom(permit, transferDetails, msg.sender, signature)
        //    This will:
        //    - Verify the signature
        //    - Transfer tokens from msg.sender to this vault
        // 4. Update balances[msg.sender][token] += amount
        // 5. Emit a Deposit event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement depositWithSignatureTransferWitness
    // =============================================================
    /// @notice Deposits tokens using Permit2 SignatureTransfer with witness data.
    /// @dev The user signs both the transfer AND a depositId (witness data).
    ///      This ensures the signature is only valid for this specific deposit.
    /// @param token The token address
    /// @param amount The amount to deposit
    /// @param nonce The permit nonce
    /// @param deadline The permit deadline
    /// @param depositId The specific deposit identifier (witness data)
    /// @param signature The user's EIP-712 signature (includes witness)
    function depositWithSignatureTransferWitness(
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 depositId,
        bytes calldata signature
    ) external {
        // TODO: Implement
        // 1. Build PermitTransferFrom and SignatureTransferDetails structs
        // 2. Compute witness hash (EIP-712 hashStruct):
        //    keccak256(abi.encode(keccak256("Deposit(uint256 depositId)"), depositId))
        // 3. Define witnessTypeString (completes Permit2's type stub):
        //    "Deposit witness)Deposit(uint256 depositId)TokenPermissions(address token,uint256 amount)"
        //    Format: "<WitnessType> <fieldName>)<WitnessTypeDef><TokenPermissionsTypeDef>"
        // 4. Call permit2.permitWitnessTransferFrom(
        //      permit, transferDetails, msg.sender, witness, witnessTypeString, signature
        //    )
        // 5. Verify depositId matches expected value (optional additional check)
        // 6. Update balances[msg.sender][token] += amount
        // 7. Emit a DepositWithWitness event (define it)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement depositWithAllowanceTransfer
    // =============================================================
    /// @notice Deposits tokens using Permit2 AllowanceTransfer.
    /// @dev The user must have previously called permit2.permit() to set an allowance.
    ///      This function then transfers from that allowance.
    /// @param token The token address
    /// @param amount The amount to deposit (must be within allowance)
    function depositWithAllowanceTransfer(address token, uint160 amount) external {
        // TODO: Implement
        // 1. Call permit2.transferFrom(msg.sender, address(this), amount, token)
        //    This assumes the user has already set an allowance via permit2.permit()
        // 2. Update balances[msg.sender][token] += amount
        // 3. Emit a Deposit event
        //
        // Note: This is the simpler mode — the user signs a permit() call once,
        //       then can make multiple deposits without new signatures until the
        //       allowance expires or is exhausted.
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement permitAndDepositWithAllowanceTransfer
    // =============================================================
    /// @notice Sets an allowance via permit, then deposits in one transaction.
    /// @dev Combines permit() and transferFrom() for a one-shot deposit.
    /// @param token The token address
    /// @param amount The amount for the allowance
    /// @param expiration When the allowance expires
    /// @param nonce The permit nonce
    /// @param sigDeadline The signature deadline
    /// @param signature The user's signature
    /// @param depositAmount The amount to deposit (≤ amount)
    function permitAndDepositWithAllowanceTransfer(
        address token,
        uint160 amount,
        uint48 expiration,
        uint48 nonce,
        uint256 sigDeadline,
        bytes calldata signature,
        uint160 depositAmount
    ) external {
        // TODO: Implement
        // 1. Build PermitSingle struct with PermitDetails
        // 2. Call permit2.permit(msg.sender, permitSingle, signature)
        // 3. Call permit2.transferFrom(msg.sender, address(this), depositAmount, token)
        // 4. Update balances[msg.sender][token] += depositAmount
        // 5. Emit a Deposit event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement withdraw
    // =============================================================
    /// @notice Withdraws deposited tokens.
    function withdraw(address token, uint256 amount) external {
        // TODO: Implement (same as PermitVault)
        // 1. Check balance
        // 2. Update balance
        // 3. Transfer tokens
        // 4. Emit Withdrawal event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 7: Implement view functions
    // =============================================================

    function getBalance(address user, address token) external view returns (uint256) {
        // TODO: Return balances[user][token]
        revert("Not implemented");
    }

    // TODO: Define events
    // event Deposit(address indexed user, address indexed token, uint256 amount);
    // event DepositWithWitness(address indexed user, address indexed token, uint256 amount, uint256 indexed depositId);
    // event Withdrawal(address indexed user, address indexed token, uint256 amount);
}
