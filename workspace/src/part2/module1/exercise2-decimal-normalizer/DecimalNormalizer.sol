// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// ============================================================================
// EXERCISE: Decimal Normalizer
//
// Build a multi-token accounting contract that accepts deposits from tokens
// with different decimal places (USDC=6, WBTC=8, DAI=18) and maintains
// a single normalized internal ledger in 18 decimals.
//
// Concepts exercised:
//   - Decimal normalization math (scaling up and down)
//   - Multi-token deposit/withdraw patterns
//   - SafeERC20 for safe token interactions
//   - Precision loss awareness
//
// Run: forge test --match-contract DecimalNormalizerTest -vvv
// ============================================================================

// --- Custom Errors ---
error TokenNotRegistered(address token);
error ZeroAmount();
error InsufficientNormalizedBalance(uint256 requested, uint256 available);

/// @notice Accepts deposits from tokens with varying decimals, normalizes to 18.
/// @dev All internal accounting uses 18-decimal normalized amounts.
///      When withdrawing, the contract de-normalizes back to the token's native decimals.
contract DecimalNormalizer {
    /// @notice Registered token decimals (0 means not registered)
    mapping(address => uint8) public tokenDecimals;

    /// @notice Whether a token is registered
    mapping(address => bool) public isRegistered;

    /// @notice Per-user, per-token normalized balance (in 18 decimals)
    mapping(address => mapping(address => uint256)) public normalizedBalanceOf;

    /// @notice Total normalized value across all users and tokens
    uint256 public totalValueNormalized;

    event TokenRegistered(address indexed token, uint8 decimals);
    event Deposit(address indexed user, address indexed token, uint256 rawAmount, uint256 normalizedAmount);
    event Withdraw(address indexed user, address indexed token, uint256 rawAmount, uint256 normalizedAmount);

    // =============================================================
    //  TODO 1: Import and apply SafeERC20
    // =============================================================
    // Same as DefensiveVault — use SafeERC20 for all token interactions.
    // Hint: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    //       using SafeERC20 for IERC20;

    // =============================================================
    //  TODO 2: Implement registerToken
    // =============================================================
    /// @notice Register a token for deposits. Reads decimals from the token contract.
    /// @dev Stores the token's decimals for normalization math.
    ///
    /// Steps:
    ///   1. Read decimals from the token using IERC20Metadata(token).decimals()
    ///   2. Store the decimals and mark the token as registered
    ///   3. Emit TokenRegistered
    function registerToken(address token) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement normalize (internal helper)
    // =============================================================
    /// @notice Convert a raw token amount to 18-decimal normalized form.
    /// @dev If the token has 6 decimals: 1_000_000 (1 USDC) → 1_000_000_000_000_000_000 (1e18)
    ///      Formula: normalizedAmount = rawAmount * 10^(18 - tokenDecimals)
    ///
    /// Example walkthrough:
    ///   USDC (6 decimals): 1_000_000 * 10^(18-6) = 1_000_000 * 10^12 = 1e18 ✅
    ///   WBTC (8 decimals): 100_000_000 * 10^(18-8) = 1e8 * 10^10 = 1e18 ✅
    ///   DAI  (18 decimals): 1e18 * 10^(18-18) = 1e18 * 1 = 1e18 ✅
    function _normalize(uint256 rawAmount, uint8 decimals) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement denormalize (internal helper)
    // =============================================================
    /// @notice Convert a normalized (18-decimal) amount back to raw token decimals.
    /// @dev Formula: rawAmount = normalizedAmount / 10^(18 - tokenDecimals)
    ///
    /// ⚠️ WARNING: This division can lose precision!
    ///   1_500_000_000_000 (1.5e12 normalized from USDC) / 10^12 = 1 (not 1.5!)
    ///   This is expected — you can't represent 0.000001 USDC.
    function _denormalize(uint256 normalizedAmount, uint8 decimals) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement deposit
    // =============================================================
    /// @notice Deposit tokens into the normalizer.
    /// @param token The token address to deposit
    /// @param amount The raw amount in the token's native decimals
    /// @dev Must revert if token is not registered or amount is zero.
    ///
    /// Steps:
    ///   1. Verify token is registered (revert with TokenNotRegistered if not)
    ///   2. Revert with ZeroAmount() if amount is 0
    ///   3. Transfer tokens from sender (use safe version!)
    ///   4. Normalize the amount to 18 decimals
    ///   5. Credit user's normalized balance for this token
    ///   6. Update totalValueNormalized
    ///   7. Emit Deposit with both raw and normalized amounts
    function deposit(address token, uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement withdraw
    // =============================================================
    /// @notice Withdraw tokens, specifying the normalized amount.
    /// @param token The token address to withdraw
    /// @param normalizedAmount The amount in 18-decimal normalized form
    /// @dev De-normalizes to the token's native decimals before transferring.
    ///
    /// Steps:
    ///   1. Verify token is registered
    ///   2. Check user has sufficient normalized balance
    ///   3. Decrease user's normalized balance
    ///   4. Decrease totalValueNormalized
    ///   5. De-normalize to raw token amount
    ///   6. Transfer raw amount to user (use safe version!)
    ///   7. Emit Withdraw with both raw and normalized amounts
    function withdraw(address token, uint256 normalizedAmount) external {
        revert("Not implemented");
    }
}
