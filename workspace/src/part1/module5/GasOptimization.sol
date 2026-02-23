// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Gas Optimization Patterns
//
// This file contains examples of common gas optimization techniques. Each
// pattern has two implementations: unoptimized and optimized. Use
// `forge snapshot` to compare gas costs.
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
        // TODO: Implement using require strings
        // require(balances[msg.sender] >= amount, "Insufficient balance");
        // require(amount > 0, "Invalid amount");
        // require(to != address(0), "Invalid recipient");
        //
        // balances[msg.sender] -= amount;
        // balances[to] += amount;
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
        // TODO: Implement using custom errors
        // if (balances[msg.sender] < amount) revert InsufficientBalance();
        // if (amount == 0) revert InvalidAmount();
        // if (to == address(0)) revert InvalidAmount();
        //
        // balances[msg.sender] -= amount;
        // balances[to] += amount;
        revert("Not implemented");
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }
}

// =============================================================
//  Pattern 2: Storage Packing
// =============================================================

/// @notice Unoptimized: Poor storage packing (uses 3 slots).
contract StorageUnoptimized {
    // Each variable takes a full slot (32 bytes)
    uint256 public value1; // Slot 0
    uint128 public value2; // Slot 1 (wastes 16 bytes)
    uint128 public value3; // Slot 2 (wastes 16 bytes)
    address public owner; // Slot 3 (wastes 12 bytes)

    function setValue(uint256 _v1, uint128 _v2, uint128 _v3, address _owner) external {
        // TODO: Implement
        // value1 = _v1;
        // value2 = _v2;
        // value3 = _v3;
        // owner = _owner;
        revert("Not implemented");
    }
}

/// @notice Optimized: Efficient storage packing (uses 2 slots).
contract StorageOptimized {
    // Slot 0: value1 (32 bytes)
    uint256 public value1;

    // Slot 1: value2 (16 bytes) + value3 (16 bytes)
    uint128 public value2;
    uint128 public value3;

    // Slot 2: owner (20 bytes) - could pack more here
    address public owner;

    function setValue(uint256 _v1, uint128 _v2, uint128 _v3, address _owner) external {
        // TODO: Implement
        // value1 = _v1;
        // value2 = _v2;
        // value3 = _v3;
        // owner = _owner;
        revert("Not implemented");
    }
}

// =============================================================
//  Pattern 3: Calldata vs Memory
// =============================================================

/// @notice Unoptimized: Uses memory for read-only parameters.
contract CalldataUnoptimized {
    function processArray(uint256[] memory data) external pure returns (uint256 sum) {
        // TODO: Implement
        // for (uint256 i = 0; i < data.length; i++) {
        //     sum += data[i];
        // }
        revert("Not implemented");
    }

    function processBytes(bytes memory data) external pure returns (uint256) {
        // TODO: Implement
        // return data.length;
        revert("Not implemented");
    }
}

/// @notice Optimized: Uses calldata for read-only parameters.
contract CalldataOptimized {
    function processArray(uint256[] calldata data) external pure returns (uint256 sum) {
        // TODO: Implement
        // for (uint256 i = 0; i < data.length; i++) {
        //     sum += data[i];
        // }
        revert("Not implemented");
    }

    function processBytes(bytes calldata data) external pure returns (uint256) {
        // TODO: Implement
        // return data.length;
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
        // TODO: Implement with i++
        // for (uint256 i = 0; i < values.length; i++) {
        //     sum += values[i];
        // }
        revert("Not implemented");
    }

    function addValues(uint256[] memory newValues) external {
        // TODO: Implement
        // for (uint256 i = 0; i < newValues.length; i++) {
        //     values.push(newValues[i]);
        // }
        revert("Not implemented");
    }
}

/// @notice Optimized: Efficient loop patterns.
contract LoopOptimized {
    uint256[] public values;

    function sumArray() external view returns (uint256 sum) {
        // TODO: Implement with ++i and cached length
        // uint256 length = values.length;
        // for (uint256 i = 0; i < length; ++i) {
        //     sum += values[i];
        // }
        revert("Not implemented");
    }

    function addValues(uint256[] calldata newValues) external {
        // TODO: Implement with unchecked and ++i
        // uint256 length = newValues.length;
        // for (uint256 i = 0; i < length;) {
        //     values.push(newValues[i]);
        //     unchecked { ++i; }
        // }
        revert("Not implemented");
    }
}

// =============================================================
//  Pattern 5: Unchecked Arithmetic
// =============================================================

/// @notice Unoptimized: All arithmetic is checked.
contract ArithmeticUnoptimized {
    function calculateSum(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        // TODO: Implement with checked arithmetic
        // return a + b + c;
        revert("Not implemented");
    }

    function decrementCounter(uint256 count) external pure returns (uint256) {
        // TODO: Implement
        // return count - 1;
        revert("Not implemented");
    }
}

/// @notice Optimized: Uses unchecked for safe operations.
contract ArithmeticOptimized {
    function calculateSum(uint256 a, uint256 b, uint256 c) external pure returns (uint256 result) {
        // TODO: Implement with unchecked
        // unchecked {
        //     result = a + b + c;
        // }
        // Note: Only use unchecked when you KNOW overflow is impossible
        revert("Not implemented");
    }

    function decrementCounter(uint256 count) external pure returns (uint256 result) {
        // TODO: Implement with unchecked
        // unchecked {
        //     result = count - 1;
        // }
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
        // TODO: Implement with expensive check first
        // return isWhitelisted[user] && balance > 100e18;
        // Note: This reads storage even if balance check would fail
        revert("Not implemented");
    }
}

/// @notice Optimized: Cheap checks first.
contract ShortCircuitOptimized {
    mapping(address => bool) public isWhitelisted;

    function canAccess(address user, uint256 balance) external view returns (bool) {
        // TODO: Implement with cheap check first
        // return balance > 100e18 && isWhitelisted[user];
        // Note: If balance fails, storage read is skipped
        revert("Not implemented");
    }
}
