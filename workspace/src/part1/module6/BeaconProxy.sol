// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Beacon Proxy Pattern
//
// Implement the beacon proxy pattern where multiple proxy instances share
// a single upgrade beacon. Upgrading the beacon upgrades ALL proxies
// simultaneously. This is the pattern used by Aave's aTokens.
//
// Day 15: Master the beacon proxy pattern for multi-instance upgrades.
//
// Run: forge test --match-contract BeaconProxyTest -vvv
// ============================================================================

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// --- Custom Errors ---
error ZeroAddress();
error ZeroAmount();
error InsufficientBalance();
error Unauthorized();

// =============================================================
//  TODO 1: Implement UpgradeableBeacon
// =============================================================
/// @notice Beacon that points to an implementation contract.
/// @dev All beacon proxies query this contract for the implementation address.
contract UpgradeableBeacon {
    address private _implementation;
    address public owner;

    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address implementation_) {
        // TODO: Implement
        // 1. Validate implementation != address(0)
        // 2. Set _implementation
        // 3. Set owner to msg.sender
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement implementation getter
    // =============================================================
    /// @notice Returns the current implementation address.
    function implementation() public view returns (address) {
        // TODO: Return _implementation
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement upgradeTo
    // =============================================================
    /// @notice Upgrades the beacon to a new implementation.
    /// @dev Only owner can upgrade. This affects ALL proxies using this beacon.
    /// @param newImplementation Address of new implementation
    function upgradeTo(address newImplementation) public {
        // TODO: Implement
        // 1. Check msg.sender == owner (revert Unauthorized if not)
        // 2. Validate newImplementation != address(0)
        // 3. Set _implementation = newImplementation
        // 4. Emit Upgraded event
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement transferOwnership
    // =============================================================
    /// @notice Transfers ownership of the beacon.
    function transferOwnership(address newOwner) public {
        // TODO: Implement
        // 1. Check msg.sender == owner
        // 2. Validate newOwner != address(0)
        // 3. Emit OwnershipTransferred event
        // 4. Set owner = newOwner
        revert("Not implemented");
    }
}

// =============================================================
//  TODO 5: Implement BeaconProxy
// =============================================================
/// @notice Proxy that delegates to the implementation from a beacon.
/// @dev Queries the beacon for the current implementation on every call.
contract BeaconProxy {
    // Beacon address is immutable
    address private immutable _beacon;

    // =============================================================
    //  TODO 6: Implement constructor
    // =============================================================
    /// @param beacon Address of the UpgradeableBeacon
    /// @param data Initialization data to call on implementation
    constructor(address beacon, bytes memory data) {
        // TODO: Implement the remaining steps
        // 1. Validate beacon != address(0)
        // 2. If data is not empty, delegatecall to implementation with data
        //    (this initializes the proxy storage)
        _beacon = beacon;
    }

    // =============================================================
    //  TODO 7: Implement _getImplementation
    // =============================================================
    /// @notice Gets the current implementation from the beacon.
    function _getImplementation() internal view returns (address) {
        // TODO: Implement
        // Call beacon.implementation() and return the result
        // return UpgradeableBeacon(_beacon).implementation();
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 8: Implement fallback with delegatecall
    // =============================================================
    /// @notice Fallback function that delegates all calls to the implementation.
    fallback() external payable {
        // TODO: Implement
        // 1. Get implementation from beacon: address impl = _getImplementation()
        // 2. Delegatecall to implementation:
        //    assembly {
        //        calldatacopy(0, 0, calldatasize())
        //        let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
        //        returndatacopy(0, 0, returndatasize())
        //        switch result
        //        case 0 { revert(0, returndatasize()) }
        //        default { return(0, returndatasize()) }
        //    }
        revert("Not implemented");
    }

    /// @notice Allows proxy to receive ETH.
    receive() external payable {}

    /// @notice Returns the beacon address.
    function beacon() public view returns (address) {
        return _beacon;
    }
}

// =============================================================
//  Implementation Contracts (like aTokens)
// =============================================================

// =============================================================
//  TODO 9: Implement TokenVaultV1 (Implementation)
// =============================================================
/// @notice V1: Basic token vault implementation.
/// @dev This will be used by multiple beacon proxies.
contract TokenVaultV1 is Initializable, OwnableUpgradeable {
    string public name;
    uint256 public totalDeposits;
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =============================================================
    //  TODO 10: Implement initialize
    // =============================================================
    /// @notice Initializes the vault instance.
    /// @param _name Name of this vault instance (e.g., "aUSDC", "aWETH")
    /// @param _owner Owner of this vault instance
    function initialize(string memory _name, address _owner) public initializer {
        // TODO: Implement
        // 1. Call __Ownable_init(_owner)
        // 2. Set name = _name
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 11: Implement deposit
    // =============================================================
    /// @notice Deposits into the vault.
    function deposit(uint256 amount) external {
        // TODO: Implement
        // 1. Validate amount > 0
        // 2. Update balances[msg.sender] += amount
        // 3. Update totalDeposits += amount
        // 4. Emit Deposit event
        //
        // Note: Simplified - no actual token transfer
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 12: Implement withdraw
    // =============================================================
    /// @notice Withdraws from the vault.
    function withdraw(uint256 amount) external virtual {
        // TODO: Implement
        // 1. Validate amount > 0
        // 2. Validate balances[msg.sender] >= amount
        // 3. Update balances[msg.sender] -= amount
        // 4. Update totalDeposits -= amount
        // 5. Emit Withdraw event
        revert("Not implemented");
    }

    function version() public pure virtual returns (uint256) {
        return 1;
    }
}

// =============================================================
//  TODO 13: Implement TokenVaultV2 (Upgraded Implementation)
// =============================================================
/// @notice V2: Adds fee collection feature.
contract TokenVaultV2 is TokenVaultV1 {
    uint256 public feePercentage; // Fee in basis points
    uint256 public collectedFees;

    event FeeCollected(address indexed user, uint256 amount);

    // =============================================================
    //  TODO 14: Override withdraw to add fees
    // =============================================================
    /// @notice Withdraws with fee deduction.
    function withdraw(uint256 amount) external override {
        // TODO: Implement
        // 1. Validate amount > 0
        // 2. Validate balances[msg.sender] >= amount
        // 3. Calculate fee: uint256 fee = (amount * feePercentage) / 10000
        // 4. Calculate net: uint256 netAmount = amount - fee
        // 5. Update balances[msg.sender] -= amount
        // 6. Update totalDeposits -= amount
        // 7. Update collectedFees += fee
        // 8. Emit Withdraw event
        // 9. Emit FeeCollected event (if fee > 0)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 15: Implement setFeePercentage
    // =============================================================
    /// @notice Sets the withdrawal fee percentage.
    /// @param newFee Fee in basis points (e.g., 100 = 1%)
    function setFeePercentage(uint256 newFee) external onlyOwner {
        // TODO: Implement
        // 1. Set feePercentage = newFee
        revert("Not implemented");
    }

    function version() public pure override returns (uint256) {
        return 2;
    }
}
