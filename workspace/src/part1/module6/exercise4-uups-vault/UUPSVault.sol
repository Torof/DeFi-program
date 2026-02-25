// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: UUPS Upgradeable Vault
//
// Build a vault using the UUPS proxy pattern. Deploy V1 with basic
// deposit/withdraw, then upgrade to V2 that adds a withdrawal fee.
// Verify that storage persists across upgrades.
//
// Day 14-15: Master UUPS proxy pattern and upgrade workflows.
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
        // TODO: Implement
        // 1. Validate inputs (revert ZeroAddress if either is zero)
        // 2. Initialize inherited contracts:
        //    __Ownable_init(_owner);
        //    __UUPSUpgradeable_init();
        // 3. Set token: token = IERC20(_token);
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement deposit
    // =============================================================
    /// @notice Deposits tokens into the vault.
    /// @param amount Amount to deposit
    function deposit(uint256 amount) external {
        // TODO: Implement
        // 1. Validate amount > 0
        // 2. Transfer tokens from user: token.transferFrom(msg.sender, address(this), amount)
        // 3. Update balances: balances[msg.sender] += amount
        // 4. Update totalDeposits: totalDeposits += amount
        // 5. Emit Deposit event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement withdraw
    // =============================================================
    /// @notice Withdraws tokens from the vault.
    /// @param amount Amount to withdraw
    function withdraw(uint256 amount) external virtual {
        // TODO: Implement
        // 1. Validate amount > 0
        // 2. Validate user has sufficient balance: balances[msg.sender] >= amount
        // 3. Update balances: balances[msg.sender] -= amount
        // 4. Update totalDeposits: totalDeposits -= amount
        // 5. Transfer tokens to user: token.transfer(msg.sender, amount)
        // 6. Emit Withdraw event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement _authorizeUpgrade (UUPS requirement)
    // =============================================================
    /// @notice Authorizes an upgrade to a new implementation.
    /// @dev Only owner can upgrade. This is required by UUPSUpgradeable.
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // TODO: Implement authorization logic
        // In this simple version, onlyOwner modifier handles authorization
        // In production, you might add:
        // - Timelock requirement
        // - Multi-sig approval
        // - Validation of newImplementation (e.g., interface check)
        //
        // For now, just allow the function to execute (empty body is fine)
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
        // TODO: Implement
        // 1. Validate fee: _feeBps <= 1000 (revert ExcessiveFee if too high)
        // 2. Set withdrawalFeeBps: withdrawalFeeBps = _feeBps;
        // 3. Emit FeeUpdated event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 8: Override withdraw to add fee logic
    // =============================================================
    /// @notice Withdraws tokens with fee deduction.
    /// @param amount Amount to withdraw (before fee)
    function withdraw(uint256 amount) external override {
        // TODO: Implement
        // 1. Validate amount > 0
        // 2. Validate user has sufficient balance
        // 3. Calculate fee: uint256 fee = (amount * withdrawalFeeBps) / 10000;
        // 4. Calculate net amount: uint256 netAmount = amount - fee;
        // 5. Update balances: balances[msg.sender] -= amount
        // 6. Update totalDeposits: totalDeposits -= amount
        // 7. Update collectedFees: collectedFees += fee
        // 8. Transfer net amount to user: token.transfer(msg.sender, netAmount)
        // 9. Emit Withdraw event
        // 10. Emit FeeCollected event (if fee > 0)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 9: Implement fee management functions
    // =============================================================

    /// @notice Updates the withdrawal fee.
    /// @param newFeeBps New fee in basis points
    function setWithdrawalFee(uint256 newFeeBps) external onlyOwner {
        // TODO: Implement
        // 1. Validate newFeeBps <= 1000
        // 2. Update withdrawalFeeBps
        // 3. Emit FeeUpdated event
        revert("Not implemented");
    }

    /// @notice Withdraws collected fees to owner.
    function collectFees() external onlyOwner {
        // TODO: Implement
        // 1. Get fees: uint256 fees = collectedFees;
        // 2. Validate fees > 0
        // 3. Reset collectedFees: collectedFees = 0;
        // 4. Transfer to owner: token.transfer(owner(), fees);
        revert("Not implemented");
    }

    /// @notice Returns the version of this implementation.
    function version() public pure override returns (uint256) {
        return 2;
    }
}
