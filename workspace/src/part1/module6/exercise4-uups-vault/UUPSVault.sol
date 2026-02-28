// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: UUPS Upgradeable Vault
//
// Build a vault using the UUPS proxy pattern. Deploy V1 with basic
// deposit/withdraw, then upgrade to V2 that adds a withdrawal fee.
// Verify that storage persists across upgrades.
//
// See: Module 6 > UUPS Proxy Pattern (#uups-pattern)
//
// Run: forge test --match-contract UUPSVaultTest -vvv
// ============================================================================

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// --- Custom Errors ---
error ZeroAmount();
error ZeroAddress();
error InsufficientBalance();
error TransferFailed();
error ExcessiveFee();

// =============================================================
//  TODO 1: Implement VaultV1 (UUPS Upgradeable)
// =============================================================
/// @notice V1: Basic vault with deposit/withdraw functionality.
/// @dev Uses UUPS pattern - upgrade logic is in the implementation.
contract VaultV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IERC20 public token;
    mapping(address => uint256) public balances;
    uint256 public totalDeposits;

    // Storage gap for future upgrades
    uint256[47] private __gap;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable initializers in the implementation contract
        _disableInitializers();
    }

    // =============================================================
    //  TODO 2: Implement initialize (replaces constructor)
    // =============================================================
    /// @notice Initializes the vault (called once on deployment).
    /// @param _token Address of the ERC20 token to accept
    /// @param _owner Address of the vault owner
    function initialize(address _token, address _owner) public initializer {
        // TODO: Implement initialization
        // 1. Validate inputs are not zero addresses (revert ZeroAddress)
        // 2. Initialize inherited upgradeable contracts (Ownable, UUPS)
        // 3. Set the token state variable
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement deposit
    // =============================================================
    /// @notice Deposits tokens into the vault.
    /// @param amount Amount to deposit
    function deposit(uint256 amount) external {
        // TODO: Implement deposit
        // 1. Validate amount > 0 (revert ZeroAmount)
        // 2. Transfer tokens from the caller into this contract
        // 3. Update the caller's balance and total deposits
        // 4. Emit the Deposit event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement withdraw
    // =============================================================
    /// @notice Withdraws tokens from the vault.
    /// @param amount Amount to withdraw
    function withdraw(uint256 amount) external virtual {
        // TODO: Implement withdrawal
        // 1. Validate amount > 0 (revert ZeroAmount)
        // 2. Validate caller has sufficient balance (revert InsufficientBalance)
        // 3. Update the caller's balance and total deposits
        // 4. Transfer tokens back to the caller
        // 5. Emit the Withdraw event
        revert("Not implemented");
    }

    // =============================================================
    //  _authorizeUpgrade (UUPS requirement)
    // =============================================================
    /// @notice Authorizes an upgrade to a new implementation.
    /// @dev Only owner can upgrade. This is required by UUPSUpgradeable.
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Authorization: only owner can upgrade (enforced by onlyOwner modifier)
        // In production, you might also add:
        // - Timelock requirement
        // - Multi-sig approval
        // - Validation of newImplementation (e.g., interface check)
    }

    /// @notice Returns the version of this implementation.
    function version() public pure virtual returns (uint256) {
        return 1;
    }
}

// =============================================================
//  TODO 6: Implement VaultV2 (Upgraded Version)
// =============================================================
/// @notice V2: Adds a withdrawal fee feature.
/// @dev Storage layout MUST be compatible with V1.
contract VaultV2 is VaultV1 {
    // =============================================================
    //  New state variables (appended after V1 storage)
    // =============================================================
    uint256 public withdrawalFeeBps; // Fee in basis points (1 bps = 0.01%)
    uint256 public collectedFees;

    // Reduce gap by 2 (we added 2 new uint256 variables)
    uint256[45] private __gapV2;

    event FeeUpdated(uint256 newFeeBps);
    event FeeCollected(address indexed user, uint256 amount);

    // =============================================================
    //  TODO 7: Implement V2 initializer
    // =============================================================
    /// @notice Initializes V2-specific features.
    /// @param _feeBps Withdrawal fee in basis points (max 10% = 1000 bps)
    function initializeV2(uint256 _feeBps) public reinitializer(2) {
        // TODO: Initialize V2-specific state
        // 1. Validate fee is not excessive (max 1000 bps = 10%)
        // 2. Set the withdrawal fee
        // 3. Emit the FeeUpdated event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 8: Override withdraw to add fee logic
    // =============================================================
    /// @notice Withdraws tokens with fee deduction.
    /// @param amount Amount to withdraw (before fee)
    function withdraw(uint256 amount) external override {
        // TODO: Implement withdrawal with fee deduction
        // 1. Validate amount > 0 and caller has sufficient balance
        // 2. Calculate the fee (using withdrawalFeeBps, 10000 = 100%)
        // 3. Calculate net amount after fee
        // 4. Update caller's balance, total deposits, and collected fees
        // 5. Transfer the net amount to the caller
        // 6. Emit Withdraw event, and FeeCollected if fee > 0
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 9: Implement fee management functions
    // =============================================================

    /// @notice Updates the withdrawal fee.
    /// @param newFeeBps New fee in basis points
    function setWithdrawalFee(uint256 newFeeBps) external onlyOwner {
        // TODO: Update the withdrawal fee
        // 1. Validate fee is not excessive (max 1000 bps)
        // 2. Update the fee and emit FeeUpdated
        revert("Not implemented");
    }

    /// @notice Withdraws collected fees to owner.
    function collectFees() external onlyOwner {
        // TODO: Transfer all collected fees to the owner
        // 1. Read and validate there are fees to collect
        // 2. Reset the collected fees counter
        // 3. Transfer the fee tokens to the owner
        revert("Not implemented");
    }

    /// @notice Returns the version of this implementation.
    function version() public pure override returns (uint256) {
        return 2;
    }
}
