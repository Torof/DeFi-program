// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Gas Optimization Patterns
//
// This file contains examples of common gas optimization techniques. Each
// pattern has two implementations: unoptimized and optimized. Use
// `forge snapshot` to compare gas costs.
//
// See: Module 5 > Gas Optimization Workflow (#gas-optimization)
//
// Day 13: Master gas optimization for DeFi.
//
// Run: forge test --match-contract GasOptimizationTest --gas-report
// Run: forge snapshot --match-contract GasOptimizationTest
// ============================================================================

// --- Custom Errors ---
error InsufficientBalance();
error InvalidAmount();
error Unauthorized();

// =============================================================
//  Pattern 1: Custom Errors vs Require Strings
// =============================================================

/// @notice Unoptimized: Uses require with string messages.
contract TokenTransferUnoptimized {
    mapping(address => uint256) public balances;

    function transfer(address to, uint256 amount) external {
        // TODO: Implement transfer using require strings for validation
        // Validate: sender has enough balance, amount > 0, recipient != zero address
        // Then update both sender and receiver balances
        revert("Not implemented");
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }
}

/// @notice Optimized: Uses custom errors.
contract TokenTransferOptimized {
    mapping(address => uint256) public balances;

    function transfer(address to, uint256 amount) external {
        // TODO: Implement transfer using custom errors instead of require strings
        // Use: if (condition) revert CustomError();
        // Don't forget to update both sender and receiver balances
        revert("Not implemented");
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }
}

// =============================================================
//  Pattern 2: Storage Packing
// =============================================================

/// @notice Unoptimized: Interleaved types prevent packing (uses 4 slots).
contract StorageUnoptimized {
    uint128 public value2;  // Slot 0 (wastes 16 bytes — can't pack with uint256)
    uint256 public value1;  // Slot 1 (full slot)
    address public owner;   // Slot 2 (wastes 12 bytes — can't pack with uint128)
    uint128 public value3;  // Slot 3 (wastes 16 bytes)

    function setValue(uint256 _v1, uint128 _v2, uint128 _v3, address _owner) external {
        // TODO: Assign all four values to storage
        // Remember: the storage LAYOUT causes waste, not the assignment order
        revert("Not implemented");
    }
}

/// @notice Optimized: Efficient storage packing (uses 3 slots).
contract StorageOptimized {
    // Slot 0: value1 (32 bytes)
    uint256 public value1;

    // Slot 1: value2 (16 bytes) + value3 (16 bytes) — packed!
    uint128 public value2;
    uint128 public value3;

    // Slot 2: owner (20 bytes) — could pack more here
    address public owner;

    function setValue(uint256 _v1, uint128 _v2, uint128 _v3, address _owner) external {
        // TODO: Assign all four values to storage
        // The packing benefit comes from the DECLARATION ORDER above
        revert("Not implemented");
    }
}

// =============================================================
//  Pattern 3: Calldata vs Memory
// =============================================================

/// @notice Unoptimized: Uses memory for read-only parameters.
contract CalldataUnoptimized {
    function processArray(uint256[] memory data) external pure returns (uint256 sum) {
        // TODO: Sum all elements in the array and return the total
        revert("Not implemented");
    }

    function processBytes(bytes memory data) external pure returns (uint256) {
        // TODO: Return the length of the bytes data
        revert("Not implemented");
    }
}

/// @notice Optimized: Uses calldata for read-only parameters.
contract CalldataOptimized {
    function processArray(uint256[] calldata data) external pure returns (uint256 sum) {
        // TODO: Sum all elements in the array and return the total
        // Same logic as unoptimized — the savings come from calldata vs memory
        revert("Not implemented");
    }

    function processBytes(bytes calldata data) external pure returns (uint256) {
        // TODO: Return the length of the bytes data
        revert("Not implemented");
    }
}

// =============================================================
//  Pattern 4: Loop Optimization
// =============================================================

/// @notice Unoptimized: Suboptimal loop patterns.
contract LoopUnoptimized {
    uint256[] public values;

    function sumArray() external view returns (uint256 sum) {
        // TODO: Sum the storage array using a standard for loop with i++
        // Read .length directly in the loop condition (re-reads each iteration)
        revert("Not implemented");
    }

    function addValues(uint256[] memory newValues) external {
        // TODO: Push each element from newValues into the storage array
        // Use a standard for loop with i++
        revert("Not implemented");
    }
}

/// @notice Optimized: Efficient loop patterns.
contract LoopOptimized {
    uint256[] public values;

    function sumArray() external view returns (uint256 sum) {
        // TODO: Sum the storage array, but cache .length in a local variable
        // and use ++i instead of i++
        revert("Not implemented");
    }

    function addValues(uint256[] calldata newValues) external {
        // TODO: Push each element into storage array
        // Use cached length, unchecked { ++i } for the increment
        revert("Not implemented");
    }
}

// =============================================================
//  Pattern 5: Unchecked Arithmetic
// =============================================================

/// @notice Unoptimized: All arithmetic is checked.
contract ArithmeticUnoptimized {
    function calculateSum(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        // TODO: Return a + b + c (with default checked arithmetic)
        revert("Not implemented");
    }

    function decrementCounter(uint256 count) external pure returns (uint256) {
        // TODO: Return count - 1 (with default checked arithmetic)
        revert("Not implemented");
    }
}

/// @notice Optimized: Uses unchecked for safe operations.
contract ArithmeticOptimized {
    function calculateSum(uint256 a, uint256 b, uint256 c) external pure returns (uint256 result) {
        // TODO: Return a + b + c inside an unchecked block
        // Note: Only use unchecked when you KNOW overflow is impossible
        revert("Not implemented");
    }

    function decrementCounter(uint256 count) external pure returns (uint256 result) {
        // TODO: Return count - 1 inside an unchecked block
        // Caller must ensure count > 0
        revert("Not implemented");
    }
}

// =============================================================
//  Pattern 6: Short-Circuiting
// =============================================================

/// @notice Unoptimized: Expensive checks first.
contract ShortCircuitUnoptimized {
    mapping(address => bool) public isWhitelisted;

    function canAccess(address user, uint256 balance) external view returns (bool) {
        // TODO: Return true if user is whitelisted AND balance > 100e18
        // Put the storage read (expensive) FIRST — this is the unoptimized version
        revert("Not implemented");
    }
}

/// @notice Optimized: Cheap checks first.
contract ShortCircuitOptimized {
    mapping(address => bool) public isWhitelisted;

    function canAccess(address user, uint256 balance) external view returns (bool) {
        // TODO: Return true if balance > 100e18 AND user is whitelisted
        // Put the cheap comparison FIRST — if it fails, the storage read is skipped
        revert("Not implemented");
    }
}
