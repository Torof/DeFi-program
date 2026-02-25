// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";
import {SimplePool} from "../mocks/SimplePool.sol";

// ============================================================================
// EXERCISE: Spot Price Manipulation Lab
//
// Build TWO lending contracts side by side:
//   1. VulnerableLender — reads price from DEX pool reserves (exploitable)
//   2. SafeLender       — reads price from a Chainlink oracle (immune)
//
// Then watch the test suite demonstrate the attack:
//   - Attacker swaps massively to inflate the spot price
//   - Deposits collateral at the inflated valuation
//   - Borrows more than the collateral is truly worth
//   - Swaps back to restore the price — profit!
//
// Against SafeLender, the same attack fails because the Chainlink oracle
// price doesn't move when someone swaps in a DEX pool.
//
// This is the Harvest Finance ($24M), Cream Finance ($130M), and
// Inverse Finance ($15M) attack pattern. Understanding it viscerally —
// by building both the vulnerable and safe versions — is what separates
// protocol developers from protocol victims.
//
// Concepts exercised:
//   - Why getReserves() is dangerous as a price oracle
//   - Flash loan attack economics (simulated with large capital)
//   - Chainlink as defense against same-transaction manipulation
//   - The difference between manipulable and non-manipulable price sources
//
// Key references:
//   - Harvest Finance: https://rekt.news/harvest-finance-rekt/
//   - Cream Finance: https://rekt.news/cream-rekt-2/
//   - samczsun: https://samczsun.com/so-you-want-to-use-a-price-oracle/
//
// Run: forge test --match-contract SpotPriceManipulationTest -vvv
// ============================================================================

// --- Custom Errors (shared by both lenders) ---
error InsufficientCollateral();
error InvalidToken();
error ZeroAmount();
error InvalidPrice();
error StalePrice();

// ============================================================================
//  VulnerableLender — uses DEX spot price (EXPLOITABLE)
// ============================================================================

/// @notice A lending contract that reads collateral price from a DEX pool.
/// @dev THIS IS INTENTIONALLY VULNERABLE. The spot price (reserve1/reserve0)
///      can be manipulated by anyone with enough capital (or a flash loan).
///
///      In a real attack:
///        1. Attacker flash-loans millions of Token A (zero cost)
///        2. Swaps Token A → Token B in the DEX pool (inflates B's spot price)
///        3. Deposits Token B into this lender at the inflated price
///        4. Borrows Token A far exceeding B's true value
///        5. Swaps Token B → Token A to restore the price
///        6. Repays the flash loan — keeps the profit
///
///      All within a single atomic transaction.
contract VulnerableLender {
    using SafeERC20 for IERC20;

    // --- State ---
    SimplePool public immutable pool;
    mapping(address => uint256) public collateralValue;

    // --- Events ---
    event Deposit(address indexed user, address token, uint256 amount, uint256 valueRecorded);
    event Borrow(address indexed user, address token, uint256 amount);

    constructor(address _pool) {
        pool = SimplePool(_pool);
    }

    // =============================================================
    //  TODO 1: Implement getCollateralValue — the VULNERABLE version
    // =============================================================
    /// @notice Computes the value of collateral using the DEX spot price.
    /// @dev ⚠️ THIS IS INTENTIONALLY VULNERABLE.
    ///
    ///      The spot price is: reserve1 * 1e18 / reserve0
    ///      (for token0 collateral — token0 is priced in terms of token1)
    ///
    ///      A flash loan can move this ratio to ANY value within a single tx.
    ///      For example: a 100 ETH + 300,000 USDC pool has spot price = $3,000.
    ///      After swapping 600,000 USDC in: ~33 ETH + ~900,000 USDC → spot ≈ $27,000.
    ///      That 9x inflation lets the attacker deposit 10 ETH "worth $270,000"
    ///      and borrow up to $270,000 — when the ETH is really worth $30,000.
    ///
    /// Steps:
    ///   1. Read reserves from pool.getReserves()
    ///   2. Determine spot price based on which token is being valued:
    ///      - If token == address(pool.token0()): spotPrice = reserve1 * 1e18 / reserve0
    ///      - If token == address(pool.token1()): spotPrice = reserve0 * 1e18 / reserve1
    ///      - Otherwise: revert InvalidToken
    ///   3. Return: amount * spotPrice / 1e18
    ///
    /// @param token The collateral token address
    /// @param amount The amount of collateral
    /// @return value The collateral value in the other token's terms
    function getCollateralValue(address token, uint256 amount) public view returns (uint256 value) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement deposit (VulnerableLender)
    // =============================================================
    /// @notice Deposits collateral and records its value.
    /// @dev The value is recorded at deposit time based on the current spot price.
    ///      This is where the exploit happens: if the spot price is inflated,
    ///      the recorded value is inflated too.
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Transfer token from msg.sender to this contract
    ///   3. Compute value = getCollateralValue(token, amount)
    ///   4. Add value to collateralValue[msg.sender]
    ///   5. Emit Deposit event
    ///
    /// @param token The collateral token to deposit
    /// @param amount The amount to deposit
    function deposit(address token, uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement borrow (VulnerableLender)
    // =============================================================
    /// @notice Borrows tokens against deposited collateral.
    /// @dev Simple 1:1 collateral ratio for clarity. In production, protocols
    ///      use overcollateralization ratios (e.g., 150% for ETH in Aave).
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Require collateralValue[msg.sender] >= amount (revert InsufficientCollateral)
    ///   3. Reduce collateralValue[msg.sender] by amount
    ///   4. Transfer token to msg.sender
    ///   5. Emit Borrow event
    ///
    /// @param token The token to borrow
    /// @param amount The amount to borrow
    function borrow(address token, uint256 amount) external {
        revert("Not implemented");
    }
}

// ============================================================================
//  SafeLender — uses Chainlink oracle (IMMUNE to spot manipulation)
// ============================================================================

/// @notice A lending contract that reads collateral price from a Chainlink oracle.
/// @dev The oracle price reflects the global market price aggregated from
///      multiple off-chain data sources. It does NOT change when someone
///      swaps in a single DEX pool. This is the fix for the VulnerableLender.
///
///      In production (Aave, Compound, Liquity), the oracle wrapper lives in
///      a separate contract (AaveOracle.sol, PriceFeed.sol). Here we inline it
///      for clarity.
contract SafeLender {
    using SafeERC20 for IERC20;

    // --- State ---
    SimplePool public immutable pool;
    IAggregatorV3 public immutable oracle;
    uint256 public immutable maxStaleness;
    mapping(address => uint256) public collateralValue;

    // --- Events ---
    event Deposit(address indexed user, address token, uint256 amount, uint256 valueRecorded);
    event Borrow(address indexed user, address token, uint256 amount);

    constructor(address _pool, address _oracle, uint256 _maxStaleness) {
        pool = SimplePool(_pool);
        oracle = IAggregatorV3(_oracle);
        maxStaleness = _maxStaleness;
    }

    // =============================================================
    //  TODO 4: Implement getCollateralValue — the SAFE version
    // =============================================================
    /// @notice Computes collateral value using a Chainlink oracle price.
    /// @dev The oracle price is aggregated from multiple off-chain sources.
    ///      It does NOT move when someone swaps in a DEX pool — that's the
    ///      entire point. A flash loan attack that manipulates pool reserves
    ///      has zero effect on the Chainlink price.
    ///
    ///      This function values token0 collateral. The oracle returns the
    ///      price of token0 in token1 terms (e.g., ETH/USD = 3000).
    ///
    /// Steps:
    ///   1. Read latestRoundData() from the oracle
    ///   2. Validate: answer > 0 (revert InvalidPrice)
    ///   3. Validate: block.timestamp - updatedAt < maxStaleness (revert StalePrice)
    ///   4. Normalize to 18 decimals: price * 10^(18 - oracle.decimals())
    ///   5. Return: amount * normalizedPrice / 1e18
    ///
    /// Hint: This is the same validation from OracleConsumer (Exercise 1).
    ///       In production, you'd call through a shared oracle wrapper.
    ///
    /// @param token The collateral token (only token0 is accepted)
    /// @param amount The amount of collateral
    /// @return value The collateral value in token1 terms
    function getCollateralValue(address token, uint256 amount) public view returns (uint256 value) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement deposit and borrow (SafeLender)
    // =============================================================
    /// @notice Deposits collateral using oracle-based valuation.
    /// @dev Same logic as VulnerableLender.deposit, but getCollateralValue
    ///      reads from the oracle instead of the pool. The oracle price
    ///      is immune to DEX manipulation.
    ///
    /// Steps: Same as TODO 2 (transfer, compute value, record, emit)
    ///
    /// @param token The collateral token to deposit
    /// @param amount The amount to deposit
    function deposit(address token, uint256 amount) external {
        revert("Not implemented");
    }

    /// @notice Borrows tokens against oracle-valued collateral.
    /// @dev Same logic as VulnerableLender.borrow.
    ///
    /// Steps: Same as TODO 3 (check collateral, reduce, transfer, emit)
    ///
    /// @param token The token to borrow
    /// @param amount The amount to borrow
    function borrow(address token, uint256 amount) external {
        revert("Not implemented");
    }
}
