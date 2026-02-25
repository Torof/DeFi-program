// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Storage Collision Demonstration
//
// Demonstrate what happens when storage layout is not maintained correctly
// during proxy upgrades. This shows both the WRONG way (causing collisions)
// and the CORRECT way (append-only upgrades).
//
// Day 15: Understand storage layout compatibility.
//
// Run: forge test --match-contract StorageCollisionTest -vvv
// Run: forge inspect src/part1/module6/StorageCollision.sol:VaultV1 storage-layout
// ============================================================================

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// =============================================================
//  TODO 1: Implement VaultV1 (Original Version)
// =============================================================
/// @notice V1: Original vault with totalDeposits.
/// @dev Storage: slot 0 = totalDeposits
contract VaultV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Slot 0
    uint256 public totalDeposits;

    // Storage gap
    uint256[49] private __gap;

    event Deposit(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =============================================================
    //  TODO 2: Implement initialize
    // =============================================================
    function initialize(address _owner) public initializer {
        // TODO: Implement
        // __Ownable_init(_owner);
        // __UUPSUpgradeable_init();
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement deposit
    // =============================================================
    function deposit(uint256 amount) external {
        // TODO: Implement
        // totalDeposits += amount;
        // emit Deposit(msg.sender, amount);
        revert("Not implemented");
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function version() public pure virtual returns (uint256) {
        return 1;
    }
}

// =============================================================
//  TODO 4: Observe VaultV2Wrong (WRONG - Storage Collision)
// =============================================================
/// @notice V2 WRONG: Redefines storage layout instead of inheriting V1.
/// @dev This simulates a common production mistake: deploying a new implementation
///      that doesn't preserve the original storage layout.
///      V1 had: slot 0 = totalDeposits.
///      V2Wrong has: slot 0 = newOwner → COLLISION! The old totalDeposits value
///      (e.g., 5000) gets interpreted as an address.
///
/// NOTE: This contract does NOT inherit VaultV1 — that's the bug.
///       In a real upgrade, the new implementation MUST preserve the storage
///       layout of the previous version (use inheritance or be very careful).
contract VaultV2Wrong is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // BUG: Storage layout doesn't match V1!
    // V1 had:      slot 0 = totalDeposits (uint256)
    // V2Wrong has: slot 0 = newOwner (address) ← COLLISION!

    // =============================================================
    //  TODO 5: Observe the wrong storage layout
    // =============================================================
    // This contract redefines storage from scratch instead of inheriting V1.
    // newOwner now occupies slot 0, where totalDeposits used to be!
    address public newOwner;      // Slot 0 — COLLISION with V1's totalDeposits!
    uint256 public totalDeposits; // Slot 1 — reads old __gap[0], which is 0

    uint256[48] private __gap;

    // =============================================================
    //  TODO 6: Implement getStorageSlotValues helper
    // =============================================================
    /// @notice Helper to read raw storage slots.
    /// @param slot Storage slot to read
    /// @return value Value at that slot
    function getStorageSlot(uint256 slot) external view returns (bytes32 value) {
        // TODO: Implement using assembly
        // assembly {
        //     value := sload(slot)
        // }
        revert("Not implemented");
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function version() public pure returns (uint256) {
        return 2;
    }
}

// =============================================================
//  TODO 7: Implement VaultV2Correct (CORRECT - Append Only)
// =============================================================
/// @notice V2 CORRECT: Inherits V1 and appends new variables after existing ones.
/// @dev Storage: slot 0 = totalDeposits (same), slot 50 = newOwner (after 49-slot __gap)
contract VaultV2Correct is VaultV1 {
    // CORRECT: New variables appended after all inherited storage

    // =============================================================
    //  TODO 8: Add owner variable AFTER totalDeposits (correct!)
    // =============================================================
    // TODO: Implement
    address public newOwner;  // This occupies a new slot after VaultV1's storage

    // Reduce gap by 1 (we added 1 variable)
    // uint256[48] private __gapV2;

    event NewOwnerSet(address indexed owner);

    // =============================================================
    //  TODO 9: Implement setNewOwner
    // =============================================================
    function setNewOwner(address _newOwner) external onlyOwner {
        // TODO: Implement
        // newOwner = _newOwner;
        // emit NewOwnerSet(_newOwner);
        revert("Not implemented");
    }

    /// @notice Helper to read raw storage slots.
    function getStorageSlot(uint256 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function version() public pure override returns (uint256) {
        return 2;
    }
}

// =============================================================
//  TODO 10: Implement VaultWithGap (Demonstrates Storage Gaps)
// =============================================================
/// @notice Demonstrates using storage gaps for future-proofing.
/// @dev Gap allows adding variables in future versions without collision.
contract VaultWithGap is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public totalDeposits;
    mapping(address => uint256) public balances;

    // =============================================================
    //  TODO 11: Add storage gap
    // =============================================================
    // TODO: Reserve 48 slots for future use
    // uint256[48] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
    }

    function deposit(uint256 amount) external {
        totalDeposits += amount;
        balances[msg.sender] += amount;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

// =============================================================
//  TODO 12: Implement VaultWithGapV2 (Uses Gap Correctly)
// =============================================================
/// @notice V2 of VaultWithGap - adds variables using the gap.
contract VaultWithGapV2 is VaultWithGap {
    // =============================================================
    //  TODO 13: Add new variables
    // =============================================================
    // TODO: Add new state variables
    address public feeCollector;
    uint256 public feeBps;

    // =============================================================
    //  TODO 14: Reduce gap size
    // =============================================================
    // TODO: Reduce gap by number of variables added
    // uint256[46] private __gapV2;  // Reduced by 2 (added 2 variables)

    function setFeeCollector(address _feeCollector) external onlyOwner {
        // TODO: Implement
        // feeCollector = _feeCollector;
        revert("Not implemented");
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        // TODO: Implement
        // feeBps = _feeBps;
        revert("Not implemented");
    }
}
