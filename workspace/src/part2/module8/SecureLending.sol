// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockPair} from "./MockPair.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";

// ============================================================================
//  EXERCISE: SecureLending — Fix the Oracle Manipulation Vulnerability
// ============================================================================
//
//  SpotPriceLending is vulnerable because it reads pair.getSpotPrice()
//  to value collateral. Spot price = reserve ratio — trivially inflated
//  by a flash-loan-funded swap.
//
//  Your task: replace the spot price read with a Chainlink oracle read
//  in borrow(). Chainlink prices come from off-chain aggregation of
//  multiple exchanges — a swap on one AMM pool doesn't affect them.
//
//  Run:
//    forge test --match-contract OracleManipulationTest -vvv
//
// ============================================================================

/// @notice Lending protocol defended against oracle manipulation.
/// @dev Exercise for Module 8: DeFi Security.
///      Student implements: Chainlink price read in borrow().
///      Pre-built: everything else (same as SpotPriceLending).
contract SecureLending {
    using SafeERC20 for IERC20;

    MockPair public immutable pair;
    MockChainlinkFeed public immutable priceFeed;
    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;

    uint256 public constant COLLATERAL_RATIO = 2e18;

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public borrowed;

    constructor(MockPair pair_, MockChainlinkFeed priceFeed_, IERC20 collateralToken_, IERC20 borrowToken_) {
        pair = pair_;
        priceFeed = priceFeed_;
        collateralToken = collateralToken_;
        borrowToken = borrowToken_;
    }

    /// @notice Deposit tokenA as collateral (same as SpotPriceLending).
    function depositCollateral(uint256 amount) external {
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    // =============================================================
    //  TODO: Fix borrow — use Chainlink price instead of spot price
    // =============================================================
    /// @notice Borrow tokenB against deposited tokenA collateral.
    /// @dev Replace the spot price read with a Chainlink feed read.
    ///
    ///   The fix (replace the price line below):
    ///     (, int256 answer,,,) = priceFeed.latestRoundData();
    ///     uint256 price = uint256(answer) * 1e10;
    ///
    ///   Why 1e10?
    ///     Chainlink returns 8-decimal prices (e.g., 1e8 = $1.00).
    ///     Our lending math uses 18 decimals. 1e8 * 1e10 = 1e18.
    ///
    ///   Why this is safe:
    ///     Chainlink prices are aggregated from off-chain exchanges.
    ///     Swapping on one AMM pool doesn't change the Chainlink price.
    ///     The attacker's flash-loan manipulation is invisible to Chainlink.
    ///
    /// See: Module 8 — "Oracle Manipulation" + Module 3 — "Chainlink"
    function borrow(uint256 amount) external {
        // TODO: Replace this line with Chainlink feed read
        uint256 price = pair.getSpotPrice();

        uint256 collateralValue = collateral[msg.sender] * price / 1e18;
        uint256 maxBorrow = collateralValue * 1e18 / COLLATERAL_RATIO;

        require(
            borrowed[msg.sender] + amount <= maxBorrow,
            "SecureLending: insufficient collateral"
        );

        borrowed[msg.sender] += amount;
        borrowToken.safeTransfer(msg.sender, amount);
    }
}
