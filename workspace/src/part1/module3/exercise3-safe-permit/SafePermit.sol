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
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// --- Custom Errors ---
error InsufficientAllowance();
error TransferFailed();

// =============================================================
//  TODO 1: Implement SafePermitVault
// =============================================================
/// @notice Vault with defensive permit handling.
/// @dev Handles front-running, non-permit tokens, and various edge cases gracefully.
// See: Module 3 > Safe Permit Patterns (#safe-permit-patterns)
// See: Module 3 > Permit Attack Vectors (#permit-attack-vectors)
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
        // 1. Wrap the permit call in try/catch — if it fails (front-run, already used),
        //    check if the spender already has sufficient allowance and proceed
        // 2. If permit failed AND allowance is insufficient, revert InsufficientAllowance()
        // 3. If permit failed but allowance exists, emit FallbackToApprove(msg.sender, token)
        // 4. Transfer tokens using transferFrom (works if permit succeeded OR allowance existed)
        // 5. Update balances and emit Deposit event
        // Hint: Use try IERC20Permit(token).permit(...) { } catch { check allowance }
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
        // 1. If usePermit is true, try permit (same try/catch pattern as safeDepositWithPermit)
        // 2. Whether permit succeeded or not, verify allowance is sufficient
        // 3. Transfer tokens using transferFrom
        // 4. Update balances
        // 5. Emit appropriate events
        // Hint: Reuse the try/catch pattern from safeDepositWithPermit
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
        // Hint: try/catch can capture error strings with `catch Error(string memory reason)`
        //       and handle unknown errors with a bare `catch` block
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
//  PROVIDED — Permit Phishing Demonstration
// =============================================================
/// @notice Demonstrates how a malicious contract can exploit permit signatures.
/// @dev EDUCATIONAL ONLY — study the test to understand the attack vector.
///      In a real phishing attack, the malicious frontend tricks the user into
///      signing a permit where the spender is the attacker, not the vault.
contract PermitPhishingDemo {
    address public attacker;

    constructor(address _attacker) {
        attacker = _attacker;
    }

    /// @notice Looks like a legitimate deposit, but the permit approves the attacker.
    /// @dev The user signs a permit thinking they're depositing, but the spender
    ///      in the signature is the attacker's address, not this contract.
    function fakeDeposit(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // The spender is the attacker, NOT address(this)!
        // In a real attack, the malicious frontend would generate the
        // permit signature with attacker as spender, but display
        // "Approve deposit to Vault" in the UI.
        IERC20Permit(token).permit(msg.sender, attacker, amount, deadline, v, r, s);
        // At this point, attacker can call token.transferFrom(user, attacker, amount)
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
