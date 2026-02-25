// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockStrategy} from "./MockStrategy.sol";

// ============================================================================
//  EXERCISE: SimpleAllocator — Multi-Strategy Yield Aggregator
// ============================================================================
//
//  Build a simplified Yearn V3-style allocator vault. The vault accepts
//  deposits of an underlying token and allocates those funds across multiple
//  strategies. Each strategy is an external contract that holds and grows
//  assets independently.
//
//  Key concepts:
//    - Multi-source totalAssets: idle balance + strategy values
//    - Debt tracking: how much was allocated vs how much is there now
//    - Capital deployment: approve + deposit pattern to external contracts
//    - Withdrawal queue: pull from idle first, then strategies in order
//
//  Architecture:
//    User → deposit → SimpleAllocator (idle balance)
//                          ├── allocate → Strategy A (earns yield)
//                          ├── allocate → Strategy B (earns yield)
//                          └── idle funds (no yield, instant withdrawal)
//
//  The vault owner calls allocate/deallocate to move funds between idle and
//  strategies. When a user redeems, the vault serves from idle first, then
//  pulls from strategies in queue order to cover any deficit.
//
//  Run:
//    forge test --match-contract SimpleAllocatorTest -vvv
//
// ============================================================================

/// @notice ERC-4626-style allocator vault that delegates to multiple strategies.
/// @dev Exercise for Module 7: Vaults & Yield (Yield Aggregation).
///      Students implement: totalAssets, allocate, deallocate, redeem.
///      Pre-built: deposit, _convertToShares, _convertToAssets, constructor.
contract SimpleAllocator is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    /// @notice Ordered list of strategies (set in constructor).
    MockStrategy[] public strategies;

    /// @notice Whether an address is a registered strategy.
    mapping(address => bool) public isStrategy;

    /// @notice How much was allocated (net) to each strategy.
    /// @dev debt[strategy] tracks capital sent minus capital returned.
    ///      After yield, strategy.totalValue() > debt[strategy].
    ///      The difference is profit.
    mapping(address => uint256) public debt;

    modifier onlyValidStrategy(address strategy) {
        require(isStrategy[strategy], "SimpleAllocator: not a strategy");
        _;
    }

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        MockStrategy[] memory strategies_
    ) ERC20(name_, symbol_) {
        asset = asset_;
        for (uint256 i = 0; i < strategies_.length; i++) {
            strategies.push(strategies_[i]);
            isStrategy[address(strategies_[i])] = true;
        }
    }

    /// @notice Idle assets sitting in the vault (not deployed to strategies).
    function idle() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // =============================================================
    //  TODO 1: Implement totalAssets — multi-source accounting
    // =============================================================
    /// @notice Total assets = idle balance + value held in ALL strategies.
    /// @dev Unlike SimpleVault (which just returns balanceOf), an allocator
    ///      vault must query every strategy to know its true total value.
    ///
    ///   Steps:
    ///     1. Start with idle() (assets sitting in the vault itself).
    ///     2. Loop through the strategies array.
    ///     3. For each strategy, add strategies[i].totalValue() to the total.
    ///     4. Return the sum.
    ///
    ///   Why this matters:
    ///     totalAssets() drives the share price. If it only counts idle funds,
    ///     shares would be underpriced after allocation (the vault "forgot"
    ///     about deployed capital). The vault must account for ALL assets,
    ///     including those earning yield in strategies.
    ///
    ///   After yield accrues in strategies, totalAssets() increases
    ///   automatically (strategies report higher totalValue), so shares
    ///   become worth more — no explicit "report" needed in this simplified
    ///   design.
    ///
    /// See: Module 7 — "Allocator Vault Mechanics"
    ///
    /// @return total The total value of all assets (idle + deployed).
    function totalAssets() public view returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement allocate — deploy idle funds to a strategy
    // =============================================================
    /// @notice Move idle funds into a strategy to earn yield.
    /// @dev This is how the vault owner deploys capital.
    ///
    ///   Steps:
    ///     1. Require amount <= idle() (can't allocate more than available).
    ///     2. Approve the strategy to pull tokens:
    ///        asset.approve(address(strategy), amount)
    ///     3. Call strategy.deposit(amount) — strategy pulls tokens via
    ///        safeTransferFrom.
    ///     4. Update debt tracking:
    ///        debt[strategy] += amount
    ///
    ///   After allocation:
    ///     - idle() decreases by amount
    ///     - strategy.totalValue() increases by amount
    ///     - totalAssets() stays the SAME (funds moved, not created)
    ///     - debt[strategy] tracks how much was sent
    ///
    /// See: Module 7 — "Debt allocation"
    ///
    /// @param strategy The strategy to allocate funds to.
    /// @param amount The amount of assets to deploy.
    function allocate(address strategy, uint256 amount) external onlyValidStrategy(strategy) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement deallocate — return funds from a strategy
    // =============================================================
    /// @notice Pull funds from a strategy back to idle.
    /// @dev The inverse of allocate. Can pull up to the strategy's full value
    ///      (including yield earned beyond the original debt).
    ///
    ///   Steps:
    ///     1. Require amount <= MockStrategy(strategy).totalValue()
    ///        (can't pull more than the strategy holds).
    ///     2. Call MockStrategy(strategy).withdraw(amount) — strategy sends
    ///        tokens back to this vault.
    ///     3. Update debt tracking:
    ///        debt[strategy] -= min(amount, debt[strategy])
    ///
    ///   Why min(amount, debt)? If the strategy earned yield, its totalValue
    ///   exceeds the original debt. Pulling all funds (including yield) would
    ///   try to subtract more than debt, causing underflow. The min() prevents
    ///   this — debt bottoms out at 0.
    ///
    ///   Example:
    ///     debt[A] = 5,000  |  A.totalValue() = 5,500 (earned 500 yield)
    ///     deallocate(A, 5,500):
    ///       debt[A] -= min(5,500, 5,000) = 5,000  →  debt[A] = 0  ✓
    ///
    /// See: Module 7 — "Debt allocation"
    ///
    /// @param strategy The strategy to pull funds from.
    /// @param amount The amount of assets to return to idle.
    function deallocate(address strategy, uint256 amount) external onlyValidStrategy(strategy) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement redeem — withdrawal queue
    // =============================================================
    /// @notice Redeem shares for assets, pulling from strategies if needed.
    /// @dev This is the core allocator pattern: idle-first withdrawal queue.
    ///
    ///   Steps:
    ///     1. Require msg.sender == owner (simplified access control).
    ///     2. Compute assets owed:
    ///        assets = _convertToAssets(shares, Math.Rounding.Floor)
    ///     3. Serve from idle first:
    ///        If idle() >= assets → no strategy withdrawal needed.
    ///        If idle() < assets → must pull the deficit from strategies.
    ///     4. Pull deficit from strategies IN ORDER:
    ///        uint256 deficit = assets - idle();
    ///        for each strategy in strategies[]:
    ///          uint256 pull = min(deficit, strategies[i].totalValue())
    ///          if pull > 0:
    ///            strategies[i].withdraw(pull)
    ///            debt[strategy] -= min(pull, debt[strategy])
    ///            deficit -= pull
    ///          if deficit == 0: break
    ///     5. Burn shares from owner: _burn(owner, shares)
    ///     6. Transfer assets to receiver: asset.safeTransfer(receiver, assets)
    ///
    ///   Important: compute assets BEFORE burning shares, because
    ///   _convertToAssets uses totalSupply() which changes after burn.
    ///
    ///   The withdrawal queue order matters — in production vaults, strategies
    ///   are ordered by withdrawal priority (most liquid first).
    ///
    /// See: Module 7 — "The withdrawal queue"
    ///
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address to receive the withdrawn assets.
    /// @param owner The address whose shares will be burned.
    /// @return assets The amount of assets sent to the receiver.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        revert("Not implemented");
    }

    // ── Pre-built: deposit, conversions ───────────────────────────────────
    // These use your totalAssets(). Once TODO 1 is done, they work.

    /// @notice Deposit assets, receive shares. First deposit is 1:1.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Floor);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// @notice Convert assets to shares.
    /// @dev Empty vault = 1:1. Otherwise mulDiv(assets, supply, totalAssets).
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets(), rounding);
    }

    /// @notice Convert shares to assets.
    /// @dev Empty vault = 1:1. Otherwise mulDiv(shares, totalAssets, supply).
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : Math.mulDiv(shares, totalAssets(), supply, rounding);
    }
}
