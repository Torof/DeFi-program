// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Yield Tokenizer — Split Yield-Bearing Tokens into PT + YT
//
// Build the core mechanism behind Pendle-style yield tokenization.
// Users deposit vault shares (ERC-4626-like) and receive:
//   - PT (Principal Token) balance — redeemable for the principal at maturity
//   - YT (Yield Token) balance — entitles holder to yield until maturity
//
// The yield accumulator pattern is the SAME as:
//   - Module 2's FundingRateEngine (cumulativeFundingPerUnit)
//   - Compound's borrowIndex
//   - Aave's liquidityIndex
//   - Pendle's pyIndex
//
// But here, the vault's exchange rate IS the accumulator — it's already
// maintained by the underlying protocol. We just snapshot it per-user.
//
// Key math:
//   - principalValue = shares × entryRate / WAD (fixed at tokenization)
//   - accruedYield = currentValue - principalValue (value above principal)
//   - At maturity: PT redeems for principalValue worth of shares
//   - Yield claim: pays out excess shares above principal value
//
// Concepts exercised:
//   - Exchange rate as yield accumulator
//   - Per-user snapshot pattern
//   - Principal/yield separation
//   - Maturity-gated redemption
//   - Share accounting (shares decrease as yield is claimed)
//
// Run: forge test --match-contract YieldTokenizerTest -vvv
// ============================================================================

// --- Interfaces ---

/// @dev Minimal vault interface (ERC-4626-like). Only what we need.
interface IVault {
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function exchangeRate() external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

// --- Custom Errors ---
error ZeroAmount();
error NoPosition();
error PositionAlreadyExists();
error NotMatured();
error AlreadyMatured();
error InsufficientYTBalance();
error InsufficientPTBalance();

/// @notice Simplified yield tokenizer demonstrating the PT/YT split pattern.
/// @dev Pre-built: constructor, state, position struct, view helpers.
///      Student implements: tokenize, getAccruedYield, claimYield,
///                          redeemAtMaturity, redeemBeforeMaturity.
contract YieldTokenizer {
    // --- Types ---

    struct Position {
        uint256 sharesLocked;    // vault shares held by the contract for this user
        uint256 principalValue;  // underlying value at tokenization (18 dec) — fixed
        uint256 ptBalance;       // principal token balance (same as principalValue)
        uint256 ytBalance;       // yield token balance (same as principalValue)
        uint256 lastClaimedRate; // exchange rate at last yield claim (18 dec)
    }

    // --- State ---

    /// @dev The yield-bearing vault (ERC-4626-like).
    IVault public immutable vault;

    /// @dev Maturity timestamp. PT redeemable only after this.
    uint256 public immutable maturity;

    /// @dev Per-user position. One position per address (simplified).
    mapping(address => Position) public positions;

    // --- Constants ---

    uint256 private constant WAD = 1e18;

    // --- Constructor ---

    constructor(address vault_, uint256 maturity_) {
        vault = IVault(vault_);
        maturity = maturity_;
    }

    // =============================================================
    //  TODO 1: Implement tokenize
    // =============================================================
    /// @notice Deposit vault shares and receive PT + YT balances.
    /// @dev This is the "splitting" step. The user locks vault shares, and
    ///      the contract tracks their PT (principal) and YT (yield) claims.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if shares == 0
    ///        2. Revert with PositionAlreadyExists if user already has a position
    ///           (positions[msg.sender].sharesLocked > 0)
    ///        3. Revert with AlreadyMatured if block.timestamp >= maturity
    ///        4. Transfer `shares` vault tokens from msg.sender to this contract
    ///           (use vault.transferFrom)
    ///        5. Get current exchange rate: vault.exchangeRate()
    ///        6. Compute principalValue = shares * exchangeRate / WAD
    ///           (this is the underlying value at deposit — fixed forever)
    ///        7. Store the position:
    ///           - sharesLocked = shares
    ///           - principalValue = computed above
    ///           - ptBalance = principalValue (1:1 with underlying value)
    ///           - ytBalance = principalValue (1:1 with underlying value)
    ///           - lastClaimedRate = current exchange rate
    ///
    ///      Note: PT + YT balances equal the underlying value at deposit.
    ///            PT represents the principal claim, YT represents the yield claim.
    ///
    /// @param shares Number of vault shares to tokenize
    function tokenize(uint256 shares) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement getAccruedYield
    // =============================================================
    /// @notice Calculate accrued yield for a user's YT position (view only).
    /// @dev The yield comes from the vault shares becoming more valuable
    ///      over time (exchange rate increases). The math:
    ///
    ///      currentValue = sharesLocked * currentRate / WAD
    ///      accruedYield = currentValue - principalValue
    ///
    ///      This works because:
    ///        - principalValue is fixed at deposit
    ///        - sharesLocked decreases when yield is claimed
    ///        - After claiming, currentValue - principalValue = only NEW yield
    ///
    ///      Steps:
    ///        1. Revert with NoPosition if user has no position (sharesLocked == 0)
    ///        2. Get current exchange rate from vault
    ///        3. Compute currentValue = sharesLocked * currentRate / WAD
    ///        4. If currentValue <= principalValue, return 0 (no yield yet)
    ///        5. Return currentValue - principalValue (yield in underlying units)
    ///
    ///      Note: Return value is in underlying units (18 decimals).
    ///            To convert to shares: yield * WAD / currentRate
    ///
    /// @param user The address to check
    /// @return yield_ Accrued yield in underlying units (18 decimals)
    function getAccruedYield(address user) public view returns (uint256 yield_) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement claimYield
    // =============================================================
    /// @notice Claim accrued yield — transfers vault shares to the YT holder.
    /// @dev The yield is paid out in vault shares. The contract reduces
    ///      sharesLocked by the number of shares paid out. The remaining
    ///      shares still back the principalValue (PT claim).
    ///
    ///      The math for share conversion:
    ///        yieldInUnderlying = getAccruedYield(msg.sender)
    ///        yieldInShares = yieldInUnderlying * WAD / currentRate
    ///
    ///      After claiming:
    ///        sharesLocked decreases (fewer shares, but they're worth more)
    ///        principalValue stays the same (PT claim unchanged)
    ///        Remaining shares * currentRate / WAD ≈ principalValue ✓
    ///
    ///      Steps:
    ///        1. Revert with NoPosition if user has no position
    ///        2. Revert with InsufficientYTBalance if ytBalance == 0
    ///        3. Compute yield in underlying via getAccruedYield
    ///        4. If yield == 0, return early (nothing to claim)
    ///        5. Get current exchange rate
    ///        6. Convert yield to shares: yieldShares = yield * WAD / currentRate
    ///        7. Reduce sharesLocked by yieldShares
    ///        8. Update lastClaimedRate to current rate
    ///        9. Transfer yieldShares vault tokens to msg.sender
    ///
    /// @return claimed Amount of yield claimed in underlying units (18 dec)
    function claimYield() external returns (uint256 claimed) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement redeemAtMaturity
    // =============================================================
    /// @notice Redeem PT balance at maturity — returns principal worth of shares.
    /// @dev After maturity, PT holders can redeem their principal.
    ///      The contract converts principalValue back to shares at the current
    ///      exchange rate and transfers them.
    ///
    ///      If there's also unclaimed YT yield, it gets included in the payout
    ///      (since the user is withdrawing everything).
    ///
    ///      Steps:
    ///        1. Revert with NoPosition if user has no position
    ///        2. Revert with NotMatured if block.timestamp < maturity
    ///        3. Revert with InsufficientPTBalance if ptBalance == 0
    ///        4. Transfer ALL remaining sharesLocked to msg.sender
    ///           (this includes principal + any unclaimed yield)
    ///        5. Delete the position entirely
    ///
    ///      Note: We transfer all remaining shares because at maturity,
    ///            the user owns everything left in their position.
    ///            The shares cover principal + any yield not yet claimed.
    ///
    /// @return shares Number of vault shares returned
    function redeemAtMaturity() external returns (uint256 shares) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement redeemBeforeMaturity
    // =============================================================
    /// @notice "Unsplit" — burn both PT and YT to get vault shares back.
    /// @dev Before maturity, a user who holds BOTH PT and YT can reverse
    ///      the tokenization. This requires both balances to be non-zero.
    ///
    ///      Steps:
    ///        1. Revert with NoPosition if user has no position
    ///        2. Revert with AlreadyMatured if block.timestamp >= maturity
    ///        3. Revert with InsufficientPTBalance if ptBalance == 0
    ///        4. Revert with InsufficientYTBalance if ytBalance == 0
    ///        5. Transfer ALL sharesLocked to msg.sender
    ///        6. Delete the position entirely
    ///
    ///      Note: This returns ALL shares (principal + accrued yield).
    ///            The user gets back exactly what the contract holds for them.
    ///            This is the "unsplit" operation — reversing the PT/YT split.
    ///
    /// @return shares Number of vault shares returned
    function redeemBeforeMaturity() external returns (uint256 shares) {
        // YOUR CODE HERE
    }
}
