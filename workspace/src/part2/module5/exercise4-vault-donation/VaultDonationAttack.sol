// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: VaultDonationAttack
// ============================================================================
//
//  Build a flash loan-powered vault donation attack that exploits the classic
//  ERC-4626 share price inflation vulnerability.
//
//  What you'll learn:
//    - The #1 vault vulnerability: donation-based share price inflation
//    - Why balanceOf is dangerous for asset accounting in vaults
//    - How flash loans amplify donation attacks (unlimited attack capital)
//    - Why the virtual shares/assets offset defense exists (ERC-4626)
//    - The "think like an attacker" security mindset
//
//  The vulnerability:
//    A vault uses balanceOf(address(this)) for totalAssets(). This means
//    anyone can increase totalAssets by simply transferring tokens directly
//    to the vault (a "donation"). This inflates the share price, causing
//    subsequent deposits to round down to 0 shares — stealing their funds.
//
//  The attack flow inside a single transaction:
//
//    +-------------------------------------------------------------------+
//    |                     Single Transaction                            |
//    |                                                                   |
//    |  Target: YieldHarvester with 5,000 USDC pending                  |
//    |                                                                   |
//    |  1. Flash-borrow 10,000 USDC (more than harvester's balance)     |
//    |  2. Deposit 1 wei into vault → get 1 share (first depositor)     |
//    |  3. Donate remaining USDC to vault (direct transfer, no deposit) |
//    |     → share price inflated to ~10,000 USDC per share             |
//    |  4. Call harvester.harvest() → harvester deposits 5,000 USDC     |
//    |     → gets 0 shares (5,000 / 10,000 = 0, rounds down)           |
//    |  5. Withdraw 1 share → receive 15,000 USDC (ours + victim's)    |
//    |  6. Approve flash pool for repayment (10,000 + 5 premium)        |
//    |  7. Transfer profit (~4,995 USDC) to caller                      |
//    |                                                                   |
//    |  Attacker cost: flash loan premium (5 USDC)                      |
//    |  Attacker profit: ~4,995 USDC (harvester's stolen funds)         |
//    +-------------------------------------------------------------------+
//
//  Run:
//    forge test --match-contract VaultDonationAttackTest -vvv
//
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanPool, IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimple.sol";

/// @notice Interface for the vulnerable vault.
interface IVault {
    function deposit(uint256 assets) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 assets);
    function sharesOf(address user) external view returns (uint256);
}

/// @notice Interface for the yield harvester (the victim).
interface IHarvester {
    function harvest() external;
}

/// @notice Thrown when executeOperation is called by an address other than the Pool.
error NotPool();

/// @notice Thrown when the flash loan was initiated by an address other than this contract.
error NotInitiator();

/// @notice Thrown when a restricted function is called by a non-owner.
error NotOwner();

/// @notice Flash loan-powered vault donation attack contract.
/// @dev Exercise for Module 5: Flash Loans — Security Mindset.
///      Demonstrates the #1 vault vulnerability in DeFi: share price inflation
///      via donation, amplified by flash loans for unlimited attack capital.
contract VaultDonationAttack is IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    /// @notice The flash loan pool (Aave V3-style).
    IFlashLoanPool public immutable POOL;

    /// @notice The contract owner (receives the stolen funds).
    address public immutable owner;

    constructor(address pool_) {
        POOL = IFlashLoanPool(pool_);
        owner = msg.sender;
    }

    // =============================================================
    //  TODO 1: Implement executeAttack — initiate the flash loan
    // =============================================================
    /// @notice Execute the vault donation attack.
    /// @dev Only the owner can call this. The flow:
    ///        1. Encode attack params (vault, harvester) into bytes
    ///        2. Request flash loan
    ///        3. After callback completes, sweep profit to caller
    ///
    /// Steps:
    ///   1. Check that only the owner can call this (revert NotOwner)
    ///   2. Encode the vault and harvester addresses into bytes:
    ///      bytes memory params = abi.encode(vault, harvester)
    ///   3. Call POOL.flashLoanSimple(address(this), asset, borrowAmount, params, 0)
    ///   4. After flash loan returns, transfer any remaining asset balance to msg.sender
    ///      (this is the profit — the callback did the attack, pool already pulled repayment)
    ///
    /// Hint: Use IERC20(asset).balanceOf(address(this)) to get the profit amount,
    ///       then safeTransfer to msg.sender.
    /// See: Module 5 — "Flash Loan Security for Protocol Builders"
    ///
    /// @param asset The token to flash-borrow (same token the vault uses).
    /// @param borrowAmount How much to borrow (must exceed harvester's pending balance).
    /// @param vault The vulnerable vault address.
    /// @param harvester The yield harvester address (the victim).
    function executeAttack(
        address asset,
        uint256 borrowAmount,
        address vault,
        address harvester
    ) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement executeOperation — the attack callback
    // =============================================================
    /// @notice Called by the Pool after transferring the flash-loaned tokens.
    /// @dev This is where the attack happens. When called, this contract
    ///      holds `amount` of the flash-borrowed token. Execute the 5-step attack.
    ///
    /// Steps:
    ///   1. Validate msg.sender is the Pool (revert NotPool)
    ///   2. Validate initiator is this contract (revert NotInitiator)
    ///   3. Decode params: (address vault, address harvester) = abi.decode(...)
    ///
    ///   --- Step 1: Become the first (and only) depositor ---
    ///   4. Approve the vault to spend 1 of asset
    ///   5. Call IVault(vault).deposit(1) → receive 1 share
    ///      We are now the sole shareholder.
    ///
    ///   --- Step 2: Inflate the share price via donation ---
    ///   6. Transfer (amount - 1) tokens directly to the vault address
    ///      using IERC20(asset).safeTransfer(vault, amount - 1)
    ///      NOTE: This is a direct transfer, NOT a deposit()!
    ///      The vault's totalAssets() increases but no shares are minted.
    ///      Share price is now ~borrowAmount per share.
    ///
    ///   --- Step 3: Trigger the victim ---
    ///   7. Call IHarvester(harvester).harvest()
    ///      The harvester deposits its pending tokens into the inflated vault.
    ///      It receives 0 shares because: pending / borrowAmount rounds to 0.
    ///      Its tokens are now in the vault, but it has no claim on them.
    ///
    ///   --- Step 4: Withdraw everything ---
    ///   8. Get our share count: IVault(vault).sharesOf(address(this))
    ///   9. Call IVault(vault).withdraw(shares)
    ///      We hold the only shares, so we get ALL vault assets:
    ///      our deposit (1) + donation (amount-1) + victim's funds.
    ///
    ///   --- Step 5: Approve flash pool for repayment ---
    ///   10. Calculate totalOwed = amount + premium
    ///   11. Approve address(POOL) to pull totalOwed of asset
    ///   12. Return true
    ///       (The remaining balance after pool pulls is profit,
    ///        swept to the owner by executeAttack)
    ///
    /// Hint: Step 6 is the key insight — transferring tokens TO a vault contract
    ///       inflates totalAssets() but mints no shares. This is why production
    ///       vaults use internal accounting (virtual shares/assets offset) instead
    ///       of balanceOf.
    /// See: Module 5 — "Contract token balances (donation attacks)"
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        revert("Not implemented");
    }
}
