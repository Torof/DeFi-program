// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Safe Permit Wrapper
//
// Build defensive patterns for handling permit signatures:
// - Front-running protection via try/catch
// - Fallback to standard approve for non-EIP-2612 tokens
// - Proper error handling for various failure modes
//
// This demonstrates real-world security considerations when integrating permits.
//
// Run: forge test --match-contract SafePermitTest -vvv
// ============================================================================

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "../exercise1-permit-vault/PermitVault.sol";

// --- Custom Errors ---
error InsufficientAllowance();
error TransferFailed();

// =============================================================
//  TODO 1: Implement SafePermitVault
// =============================================================
/// @notice Vault with defensive permit handling.
/// @dev Handles front-running, non-permit tokens, and various edge cases gracefully.
contract SafePermitVault {
    mapping(address user => mapping(address token => uint256 balance)) public balances;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event PermitFailed(address indexed token, string reason);
    event FallbackToApprove(address indexed user, address indexed token);

    // =============================================================
    //  TODO 2: Implement safeDepositWithPermit
    // =============================================================
    /// @notice Deposits tokens with safe permit handling.
    /// @dev Uses try/catch to handle permit failures gracefully:
    ///      - If permit succeeds, proceed with transfer
    ///      - If permit fails (front-run or not supported), check allowance
    ///      - If allowance is sufficient, proceed anyway
    ///      - Otherwise, revert
    /// @param token The token address
    /// @param amount The amount to deposit
    /// @param deadline The permit deadline
    /// @param v Signature component
    /// @param r Signature component
    /// @param s Signature component
    function safeDepositWithPermit(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // TODO: Implement
        // 1. Try to execute permit in a try/catch block:
        //    try IERC20Permit(token).permit(msg.sender, address(this), amount, deadline, v, r, s) {
        //        // Permit succeeded
        //    } catch {
        //        // Permit failed - check if we have allowance anyway
        //        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        //        if (allowance < amount) {
        //            revert InsufficientAllowance();
        //        }
        //        emit FallbackToApprove(msg.sender, token);
        //    }
        //
        // 2. Transfer tokens using transferFrom (will work if permit succeeded OR allowance exists)
        // 3. Update balances
        // 4. Emit Deposit event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement depositWithFallback
    // =============================================================
    /// @notice Deposits with automatic fallback to standard approve.
    /// @dev Tries permit first, falls back to checking allowance if permit not supported.
    /// @param token The token address
    /// @param amount The amount to deposit
    /// @param deadline The permit deadline (ignored if token doesn't support permit)
    /// @param v Signature component (ignored if token doesn't support permit)
    /// @param r Signature component (ignored if token doesn't support permit)
    /// @param s Signature component (ignored if token doesn't support permit)
    /// @param usePermit Whether to attempt permit (false = skip directly to allowance check)
    function depositWithFallback(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bool usePermit
    ) external {
        // TODO: Implement
        // 1. If usePermit is true, try permit (same as safeDepositWithPermit)
        // 2. Whether permit succeeded or not, verify allowance is sufficient
        // 3. Transfer tokens
        // 4. Update balances
        // 5. Emit appropriate events
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement tryPermit helper
    // =============================================================
    /// @notice Attempts permit, returns true if successful.
    /// @dev This is a helper function that can be called before deposit operations.
    /// @return success Whether the permit succeeded
    function tryPermit(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bool success) {
        // TODO: Implement
        // 1. Try calling permit in a try/catch
        // 2. Return true if succeeded, false if failed
        // 3. Emit PermitFailed event with reason if it failed
        //
        // Hint: You can catch the error message like this:
        //       try IERC20Permit(token).permit(...) {
        //           return true;
        //       } catch Error(string memory reason) {
        //           emit PermitFailed(token, reason);
        //           return false;
        //       } catch {
        //           emit PermitFailed(token, "Unknown error");
        //           return false;
        //       }
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement supportsPermit checker
    // =============================================================
    /// @notice Checks if a token supports EIP-2612 permit.
    /// @dev Uses staticcall to check for permit function existence.
    /// @param token The token address
    /// @return supported Whether the token implements permit
    function supportsPermit(address token) public view returns (bool supported) {
        // TODO: Implement
        // 1. Try to call IERC20Permit(token).DOMAIN_SEPARATOR() using staticcall
        // 2. If the call succeeds and returns data, the token likely supports permit
        // 3. Return true if supported, false otherwise
        //
        // Hint: Use low-level staticcall:
        //       (bool success, bytes memory data) = token.staticcall(
        //           abi.encodeWithSelector(IERC20Permit.DOMAIN_SEPARATOR.selector)
        //       );
        //       return success && data.length == 32;
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement withdraw
    // =============================================================
    function withdraw(address token, uint256 amount) external {
        // TODO: Implement standard withdrawal
        // 1. Check balance
        // 2. Update balance
        // 3. Transfer tokens
        revert("Not implemented");
    }

    function getBalance(address user, address token) external view returns (uint256) {
        return balances[user][token];
    }
}

// =============================================================
//  PROVIDED — Mock Non-Permit Token
// =============================================================
/// @notice Simple ERC-20 without EIP-2612 support (for testing fallback).
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NonPermitToken is ERC20 {
    constructor() ERC20("Non-Permit Token", "NPTKN") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
