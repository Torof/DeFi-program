// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Uninitialized Proxy Attack
//
// Demonstrate the uninitialized proxy vulnerability and how to fix it.
// If initialize() can be called by anyone, an attacker can take ownership.
//
// See: Module 6 > Initializers vs Constructors (#initializers-vs-constructors)
//
// Run: forge test --match-contract UninitializedProxyTest -vvv
// ============================================================================

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// --- Custom Errors ---
error Unauthorized();

// =============================================================
//  TODO 1: Implement VulnerableVault (No initializer protection)
// =============================================================
/// @notice VULNERABLE: initialize() can be called by anyone.
/// @dev This demonstrates the uninitialized proxy attack.
contract VulnerableVault is Initializable, OwnableUpgradeable {
    uint256 public totalDeposits;

    event Initialized(address indexed owner);

    // =============================================================
    //  TODO 2: Implement vulnerable initialize (no protection)
    // =============================================================
    /// @notice VULNERABLE: Anyone can call this and become owner!
    /// @param _owner Address to set as owner
    function initialize(address _owner) public {
        // TODO: Implement WITHOUT the 'initializer' modifier
        // 1. Call _transferOwnership(_owner)
        //    (Cannot use __Ownable_init — it has 'onlyInitializing' in OZ v5,
        //     so it reverts outside an 'initializer' context)
        // 2. Emit Initialized event
        //
        // BUG: Missing 'initializer' modifier means anyone can call this
        // multiple times and take ownership!
        revert("Not implemented");
    }

    /// @notice Owner-only function.
    function ownerOnlyFunction() external view onlyOwner returns (bool) {
        return true;
    }
}

// =============================================================
//  TODO 3: Implement SecureVault (With initializer protection)
// =============================================================
/// @notice SECURE: initialize() has proper protection.
/// @dev Uses 'initializer' modifier to prevent re-initialization.
contract SecureVault is Initializable, OwnableUpgradeable {
    uint256 public totalDeposits;

    event Initialized(address indexed owner);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // TODO: Implement
        // Disable initializers in the implementation contract
        // _disableInitializers();
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement secure initialize (with protection)
    // =============================================================
    /// @notice SECURE: Can only be called once due to 'initializer' modifier.
    /// @param _owner Address to set as owner
    function initialize(address _owner) public initializer {
        // TODO: Implement WITH the 'initializer' modifier
        // 1. Call __Ownable_init(_owner);
        // 2. Emit Initialized event
        //
        // FIX: The 'initializer' modifier prevents re-initialization
        revert("Not implemented");
    }

    /// @notice Owner-only function.
    function ownerOnlyFunction() external view onlyOwner returns (bool) {
        return true;
    }
}

// =============================================================
//  TODO 5: Implement VaultWithReinitializer
// =============================================================
/// @notice Demonstrates reinitializer for version-bumped upgrades.
/// @dev Uses reinitializer(n) to allow controlled re-initialization.
contract VaultWithReinitializer is Initializable, OwnableUpgradeable {
    uint256 public totalDeposits;
    uint256 public newFeature; // Added in V2

    event Initialized(address indexed owner);
    event Reinitialized(uint256 newFeature);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice V1 initialization.
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        emit Initialized(_owner);
    }

    // =============================================================
    //  TODO 6: Implement reinitialize for V2 upgrade
    // =============================================================
    /// @notice V2 initialization - can be called once after upgrade.
    /// @param _newFeature Value for the new feature
    function reinitializeV2(uint256 _newFeature) public reinitializer(2) {
        // TODO: Implement
        // 1. Set newFeature: newFeature = _newFeature;
        // 2. Emit Reinitialized event
        //
        // The 'reinitializer(2)' modifier allows this to run once during
        // the upgrade to V2, even though initialize() was already called
        revert("Not implemented");
    }

    /// @notice Owner-only function.
    function ownerOnlyFunction() external view onlyOwner returns (bool) {
        return true;
    }
}
