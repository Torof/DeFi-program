// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Transient Reentrancy Guard
//
// Implement three versions of a reentrancy guard:
//   1. Using the `transient` keyword (Solidity 0.8.28+)
//   2. Using raw tstore/tload inline assembly (Solidity 0.8.24+)
//   3. Using classic storage (for gas comparison)
//
// The vault and attacker contracts are provided — only implement the guards.
//
// Run: forge test --match-contract TransientGuardTest -vvv
// ============================================================================

// =============================================================
//  TODO 1: Transient keyword guard
// =============================================================
/// @notice Reentrancy guard using the `transient` storage keyword.
/// @dev The `transient` keyword makes _locked live in transient storage —
///      same slot-based addressing as regular storage, but discarded at
///      the end of every transaction. ~100 gas per op vs ~5000+ for storage.
// See: Module 1 > Transient Storage (#transient-storage)
contract TransientReentrancyGuard {
    bool transient _locked;

    modifier nonReentrant() {
        // TODO: Implement
        // 1. Check that _locked is false (revert if already locked)
        // 2. Set _locked to true
        // 3. Execute the function body (_)
        // 4. Set _locked back to false
        _;
    }
}

// =============================================================
//  TODO 2: Assembly tstore/tload guard
// =============================================================
/// @notice Reentrancy guard using raw tstore/tload opcodes.
/// @dev Uses slot 0 for the lock flag. tstore(slot, value) writes,
///      tload(slot) reads. Same transient storage, manual control.
// See: Module 1 > Transient Storage (#transient-storage) — assembly syntax
contract AssemblyReentrancyGuard {
    modifier nonReentrant() {
        // TODO: Implement using inline assembly
        //
        // Steps:
        //   1. In an assembly block, read slot 0 with tload(0)
        //      - If the value is non-zero, the lock is held → revert
        //      - Hint: revert(0, 0) reverts with empty data in assembly
        //   2. Still in the same assembly block, write 1 to slot 0 with tstore(0, 1)
        //   3. Execute the function body (_)
        //   4. In a second assembly block, clear the lock: tstore(0, 0)
        _;
    }
}

// =============================================================
//  TODO 3: Classic storage guard
// =============================================================
/// @notice Reentrancy guard using regular storage (for gas comparison).
/// @dev Uses the 1/2 pattern: 1 = unlocked, 2 = locked. This avoids
///      the gas refund difference between zero→nonzero and nonzero→nonzero
///      SSTORE operations.
// See: Module 1 > Transient Storage (#transient-storage) — gas comparison
contract StorageReentrancyGuard {
    uint256 private _locked = 1;

    modifier nonReentrant() {
        // TODO: Implement using _locked
        // 1. Check that _locked == 1 (revert if != 1)
        // 2. Set _locked to 2
        // 3. Execute the function body (_)
        // 4. Set _locked back to 1
        _;
    }
}

// ============================================================================
//  PROVIDED — Do not modify below this line
// ============================================================================

// --- Vault interface ---
interface IVault {
    function deposit() external payable;
    function withdraw() external;
    function balances(address) external view returns (uint256);
}

// --- Guarded vaults (use your guard implementations) ---

contract TransientGuardedVault is TransientReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @dev Intentionally sends ETH before zeroing balance (vulnerable pattern).
    ///      The nonReentrant modifier is the only protection.
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] = 0;
    }
}

contract AssemblyGuardedVault is AssemblyReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] = 0;
    }
}

contract StorageGuardedVault is StorageReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] = 0;
    }
}

/// @dev Unguarded vault — demonstrates the vulnerability without any guard.
contract UnguardedVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] = 0;
    }
}

// --- Attacker contract ---

/// @notice Attempts reentrancy on any vault implementing IVault.
/// @dev Deposits ETH, then during withdrawal tries to re-enter up to
///      maxReentries times. If the guard works, re-entry reverts and the
///      attacker only gets their deposit back.
contract ReentrancyAttacker {
    IVault public target;
    uint256 public reentrantCalls;
    uint256 public maxReentries;
    bool private _attacking;

    constructor(address _target, uint256 _maxReentries) {
        target = IVault(_target);
        maxReentries = _maxReentries;
    }

    function attack() external payable {
        target.deposit{value: msg.value}();
        _attacking = true;
        target.withdraw();
        _attacking = false;
    }

    receive() external payable {
        if (_attacking && reentrantCalls < maxReentries) {
            reentrantCalls++;
            try target.withdraw() {} catch {}
        }
    }
}
