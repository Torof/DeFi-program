// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: YulDispatcher — Mini ERC-20 in Pure Yul Assembly
//
// Implement a function dispatcher and 5 ERC-20 functions entirely in Yul.
// The contract has NO Solidity functions — everything routes through fallback().
//
// Concepts exercised:
//   - switch-based selector dispatch
//   - Calldata decoding (calldataload + masking)
//   - Mapping slot computation: keccak256(abi.encode(key, baseSlot))
//   - sload / sstore for balances and totalSupply
//   - Access control (onlyOwner) in assembly
//   - Custom error reverts in assembly
//
// Storage Layout (DO NOT MODIFY):
//   Slot 0: totalSupply (uint256)
//   Slot 1: owner (address) — set in constructor
//   Mapping base slot 2: balances (mapping(address => uint256))
//     balances[addr] lives at keccak256(abi.encode(addr, 2))
//
// Function Selectors:
//   totalSupply()              → 0x18160ddd
//   balanceOf(address)         → 0x70a08231
//   transfer(address,uint256)  → 0xa9059cbb
//   mint(address,uint256)      → 0x40c10f19
//   owner()                    → 0x8da5cb5b
//
// Error Selectors:
//   InsufficientBalance()      → 0xf4d678b8
//   Unauthorized()             → 0x82b42900
//
// Run: FOUNDRY_PROFILE=part4 forge test --match-contract YulDispatcherTest -vvv
// ============================================================================

contract YulDispatcher {
    /// @dev Sets the contract owner. This is the ONLY Solidity code.
    constructor() {
        assembly {
            sstore(1, caller()) // slot 1 = owner = msg.sender
        }
    }

    /// @dev All logic lives here. Implement the dispatcher and functions in assembly.
    fallback() external payable {
        assembly {
            // ================================================================
            // TODO 1: Selector Dispatch
            // ================================================================
            // Extract the 4-byte function selector from calldata and route to
            // the correct function implementation using a switch statement.
            //
            // Steps:
            //   1. Load the first 32 bytes of calldata: calldataload(0)
            //   2. Shift right by 224 bits to isolate the selector: shr(224, ...)
            //   3. Use switch/case to dispatch to each function selector
            //   4. In the default case, revert (unknown selector)
            //
            // Each case should call a Yul function that you define below:
            //   case 0x18160ddd { _totalSupply() }
            //   case 0x70a08231 { _balanceOf() }
            //   case 0xa9059cbb { _transfer() }
            //   case 0x40c10f19 { _mint() }
            //   case 0x8da5cb5b { _owner() }
            //   default          { revert(0, 0) }
            //
            // Selectors: 0x18160ddd, 0x70a08231, 0xa9059cbb, 0x40c10f19, 0x8da5cb5b
            // Opcodes: calldataload, shr, switch/case
            // See: Module 4 > switch-Based Dispatch (#switch-dispatch)

            revert(0, 0) // TODO: replace with switch dispatch

            // ================================================================
            // TODO 2: totalSupply() → returns (uint256)
            // ================================================================
            // Read totalSupply from storage slot 0 and return it.
            //
            // Implement the _totalSupply() Yul function:
            //   1. Load slot 0: sload(0)
            //   2. Store the value in memory: mstore(0x00, value)
            //   3. Return 32 bytes: return(0x00, 0x20)
            //
            // Opcodes: sload, mstore, return
            // See: Module 3 > SLOAD & SSTORE in Yul (#sload-sstore-yul)

            // function _totalSupply() { ... }

            // ================================================================
            // TODO 3: balanceOf(address) → returns (uint256)
            // ================================================================
            // Decode the address argument, compute its mapping slot, and return
            // the balance.
            //
            // Implement the _balanceOf() Yul function:
            //   1. Decode address from calldata:
            //      let addr := and(calldataload(0x04), 0xffffffffffffffffffffffffffffffffffffffff)
            //      (Mask to 20 bytes — addresses are left-padded in calldata)
            //   2. Compute mapping slot: keccak256(abi.encode(address, 2))
            //      - mstore(0x00, addr)
            //      - mstore(0x20, 2)          // mapping base slot
            //      - let slot := keccak256(0x00, 0x40)
            //   3. Read balance: sload(slot)
            //   4. Return the balance: mstore(0x00, balance) + return(0x00, 0x20)
            //
            // Opcodes: calldataload, and, mstore, keccak256, sload, return
            // See: Module 3 > Mapping Slot Computation (#mapping-slots)

            // function _balanceOf() { ... }

            // ================================================================
            // TODO 4: transfer(address to, uint256 amount) → returns (bool)
            // ================================================================
            // Transfer tokens from caller to recipient. This is the hardest TODO.
            //
            // Implement the _transfer() Yul function:
            //   1. Decode arguments:
            //      - let to := and(calldataload(0x04), 0xffffffffffffffffffffffffffffffffffffffff)
            //      - let amount := calldataload(0x24)
            //   2. Compute sender's balance slot:
            //      - mstore(0x00, caller())
            //      - mstore(0x20, 2)
            //      - let senderSlot := keccak256(0x00, 0x40)
            //   3. Load sender balance: let senderBal := sload(senderSlot)
            //   4. Check sufficient balance:
            //      if lt(senderBal, amount) → revert with InsufficientBalance()
            //      - To revert: mstore(0x00, shl(224, 0xf4d678b8)) then revert(0x00, 0x04)
            //   5. Update sender balance: sstore(senderSlot, sub(senderBal, amount))
            //   6. Compute recipient's balance slot:
            //      - mstore(0x00, to)
            //      - mstore(0x20, 2)
            //      - let recipientSlot := keccak256(0x00, 0x40)
            //   7. Update recipient balance: sstore(recipientSlot, add(sload(recipientSlot), amount))
            //   8. Return true: mstore(0x00, 1) then return(0x00, 0x20)
            //
            // Opcodes: calldataload, and, caller, mstore, keccak256, sload,
            //          sstore, shl, lt, sub, add, return
            // See: Module 4 > if-Chain Dispatch (#if-chain) for guard patterns

            // function _transfer() { ... }

            // ================================================================
            // TODO 5: mint(address to, uint256 amount) — onlyOwner
            // ================================================================
            // Mint new tokens. Only the owner (stored in slot 1) can call this.
            //
            // Implement the _mint() Yul function:
            //   1. Check caller is owner:
            //      if iszero(eq(caller(), sload(1))) → revert Unauthorized()
            //      - To revert: mstore(0x00, shl(224, 0x82b42900)) then revert(0x00, 0x04)
            //   2. Decode arguments:
            //      - let to := and(calldataload(0x04), 0xffffffffffffffffffffffffffffffffffffffff)
            //      - let amount := calldataload(0x24)
            //   3. Compute recipient's balance slot:
            //      - mstore(0x00, to)
            //      - mstore(0x20, 2)
            //      - let slot := keccak256(0x00, 0x40)
            //   4. Update balance: sstore(slot, add(sload(slot), amount))
            //   5. Update totalSupply: sstore(0, add(sload(0), amount))
            //   6. Stop execution: stop()
            //
            // Note: mint has no return value (unlike transfer which returns bool)
            //
            // Opcodes: caller, sload, eq, iszero, mstore, shl, revert,
            //          calldataload, and, keccak256, sstore, add, stop
            // See: Module 4 > Yul if — Conditional Execution (#yul-if)

            // function _mint() { ... }

            // ================================================================
            // owner() → returns (address)  [PROVIDED — no TODO needed]
            // ================================================================
            // This one is provided as a reference implementation.
            // Study it to understand the return encoding pattern, then
            // model your other functions after it.

            function _owner() {
                mstore(0x00, sload(1))
                return(0x00, 0x20)
            }
        }
    }
}
