# Part 4 — Module 4: Control Flow & Functions

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~50 minutes | **Exercises:** ~3 hours

---

## 📚 Table of Contents

**Control Flow in Yul**
- [Yul `if` — Conditional Execution](#yul-if)
- [`switch/case/default` — Multi-Branch Logic](#yul-switch)
- [`for` Loops — Gas-Efficient Iteration](#yul-for)
- [`leave` — Early Exit](#yul-leave)

**Yul Functions (Internal)**
- [Defining and Calling Yul Functions](#yul-functions)
- [Inlining Behavior — When Functions Become JUMPs](#inlining)
- [Stack Depth and Yul Functions](#stack-depth)
- [Build Exercise: LoopAndFunctions](#exercise2)

**Function Selector Dispatch**
- [The Dispatch Problem](#dispatch-problem)
- [if-Chain Dispatch](#if-chain)
- [switch-Based Dispatch](#switch-dispatch)
- [Fallback and Receive in Assembly](#fallback-receive)
- [Build Exercise: YulDispatcher](#exercise1)

**Error Handling Patterns in Yul**

---

## 💡 Control Flow in Yul

Modules 1-3 gave you the building blocks: opcodes and gas costs, memory and calldata layout, storage slots and packing. Now you write programs. In [Module 1](1-evm-fundamentals.md#first-yul) you saw `if`, `switch`, and `for` in passing as Yul syntax elements. This module goes deep on each one — how they compile to bytecode, what they cost, and how to use them in production assembly.

By the end of this section, you'll understand why every `require()` in Solidity is an `if iszero(...) { revert }` under the hood, and you'll be able to write complete dispatch tables by hand.

---

<a id="yul-if"></a>
### 💡 Concept: Yul `if` — Conditional Execution

**Why this matters:** The `if` statement is the most common control flow in assembly. Every access check, every balance validation, every sanity guard compiles to an `if` in Yul. Mastering its quirks — especially the lack of `else` — is essential for writing correct assembly.

Yul's `if` is simpler than Solidity's:

```yul
if condition {
    // executed when condition is nonzero
}
```

**Key rules:**
- **Any nonzero value is true.** There is no boolean type. `1`, `42`, `0xffffffffffffffff` — all true. Only `0` is false.
- **There is no `else`.** This is by design. You use `switch` for if/else patterns.
- **Negation uses `iszero()`:** To express "if NOT condition," write `if iszero(condition) { }`.

**Pattern: Guard clauses** — the bread and butter of assembly:

```yul
assembly {
    // Ownership check: revert if caller is not owner
    if iszero(eq(caller(), sload(0))) {   // slot 0 = owner
        revert(0, 0)
    }

    // Zero-address validation
    if iszero(calldataload(4)) {          // first arg is address
        mstore(0x00, 0x00000000)          // could store error selector
        revert(0x00, 0x04)
    }

    // Balance check: revert if balance < amount
    let bal := sload(balanceSlot)
    let amount := calldataload(36)
    if lt(bal, amount) {
        revert(0, 0)
    }
}
```

Every `require(condition, "message")` in Solidity compiles to exactly this pattern: `if iszero(condition) { /* encode error */ revert(...) }`. When you write assembly, you're writing what the compiler would generate.

💻 **Quick Try:**

Test the `iszero` pattern in Remix:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract GuardTest {
    address public owner;

    constructor() { owner = msg.sender; }

    function onlyOwnerAction() external view returns (uint256) {
        assembly {
            if iszero(eq(caller(), sload(0))) {
                revert(0, 0)
            }
            mstore(0x00, 42)
            return(0x00, 0x20)
        }
    }
}
```

Deploy, call `onlyOwnerAction()` from the deployer (returns 42), then switch accounts and call again (reverts). That `if iszero(eq(...))` pattern is the one you'll write most often.

#### ⚠️ Common Mistakes

- **Forgetting `iszero()` for negation.** `if eq(x, 0) { }` does NOT mean "if x equals 0, do nothing." It means "if eq returns 1 (true), execute the block." This does execute when x is 0. The confusion is thinking `if` with a condition that evaluates to "zero equals zero" skips — it doesn't. For clarity, always use `if iszero(x) { }` when you mean "if x is zero."
- **Using `if` when `switch` is clearer.** If you have more than two branches, chained `if` statements are harder to read than a `switch`. Prefer `switch` for value-matching dispatch.
- **Not masking addresses.** `if eq(caller(), addr)` can fail if `addr` has dirty upper bits (bits 160-255 nonzero). Addresses are 20 bytes, but stack values are 32 bytes. Always ensure address values are clean, or mask with `and(addr, 0xffffffffffffffffffffffffffffffffffffffff)`.
- **Using `if` for early return.** `if` cannot return a value — it only gates a block. For early-return patterns in Yul, you need `leave` inside a Yul function (covered below).

#### 💼 Job Market Context

**"Why doesn't Yul have `else`?"**
- Good: "You use `switch` with two cases instead"
- Great: "Yul is intentionally minimal — it maps closely to EVM opcodes. There's no JUMPELSE opcode, only JUMPI (conditional jump). An if-else would compile to JUMPI + JUMP, same as a `switch` with `case 0` / `default`. Yul makes you choose the right construct explicitly rather than hiding the cost. In practice, most assembly code uses guard-clause-style `if iszero(...) { revert }` — you rarely need `else` because the revert terminates execution"

🚩 **Red flag:** Not knowing `iszero` is the standard negation pattern

**Pro tip:** Every `require()` in Solidity compiles to `if iszero(condition) { revert }` — the pattern you'll write most often. Interviewers who see you instinctively write `if iszero(...)` instead of struggling with negation know you've written real assembly

---

<a id="yul-switch"></a>
### 💡 Concept: `switch/case/default` — Multi-Branch Logic

**Why this matters:** `switch` is how you write if/else logic in Yul, and it's the foundation of function selector dispatch — the most important control flow pattern in smart contracts.

```yul
switch expr
case value1 {
    // executed if expr == value1
}
case value2 {
    // executed if expr == value2
}
default {
    // executed if no case matched
}
```

**Key rules:**
- **No fall-through.** Unlike C, JavaScript, or Go's `switch`, Yul cases do NOT fall through to the next case. Each case is independent — no `break` needed.
- **Must have at least one `case` OR a `default`.** You can't have an empty switch.
- **Cases must be literal values.** You can't use variables or expressions as case values — only integer literals or string literals.
- **The "else" replacement:** Since Yul has no `else`, use a two-branch switch:

```yul
// "if condition { A } else { B }" in Yul:
switch condition
case 0 {
    // else branch (condition was false/zero)
}
default {
    // if branch (condition was nonzero/true)
}
```

Note the inversion: `case 0` is the false branch because `0` means false. `default` catches all nonzero values (true).

**Example: Classify a value into tiers:**

```yul
assembly {
    let amount := calldataload(4)
    let tier

    // Determine tier based on thresholds
    switch gt(amount, 1000000000000000000) // > 1 ETH?
    case 0 {
        tier := 1  // small
    }
    default {
        switch gt(amount, 100000000000000000000) // > 100 ETH?
        case 0 {
            tier := 2  // medium
        }
        default {
            tier := 3  // large (whale)
        }
    }

    mstore(0x00, tier)
    return(0x00, 0x20)
}
```

💻 **Quick Try:**

Rewrite this Solidity if-chain as a Yul `switch`:

```solidity
function classify(uint256 x) external pure returns (uint256) {
    // Solidity version:
    // if (x == 1) return 10;
    // else if (x == 2) return 20;
    // else if (x == 3) return 30;
    // else return 0;

    assembly {
        switch x
        case 1 { mstore(0x00, 10) }
        case 2 { mstore(0x00, 20) }
        case 3 { mstore(0x00, 30) }
        default { mstore(0x00, 0) }
        return(0x00, 0x20)
    }
}
```

Deploy, call with different values. Verify the outputs match. At the bytecode level, both the if-chain and switch compile to the same JUMPI sequence — but `switch` makes intent explicit.

**Gas comparison:** `switch` and chained `if` produce identical bytecode — both are linear JUMPI chains. The choice is about readability, not performance.

#### 💼 Job Market Context

**"When do you use `switch` vs `if` in Yul?"**
- Good: "`switch` for matching specific values, `if` for boolean conditions"
- Great: "`switch` when dispatching on a known set of values — selector dispatch, enum handling, error codes. `if` for boolean guards — access control, balance checks, zero-address validation. At the bytecode level they compile to the same JUMPI chains, but `switch` makes the intent explicit — especially important in audit-facing code. The Solidity compiler itself uses `switch` internally for selector dispatch in the Yul IR output"

🚩 **Red flag:** Assuming `switch` has fall-through like C

**Pro tip:** The Solidity compiler uses `switch` internally for selector dispatch — you're writing what the compiler would generate. Knowing this shows you understand the compilation pipeline, not just the surface syntax

---

<a id="yul-for"></a>
### 💡 Concept: `for` Loops — Gas-Efficient Iteration

**Why this matters:** Loops are where assembly gas savings are most dramatic — and where bugs are most dangerous. A single unbounded loop can make a contract DoS-vulnerable. Understanding the exact gas cost per iteration lets you make informed decisions about loop design.

Yul's `for` loop has explicit C-like syntax:

```yul
for { /* init */ } /* condition */ { /* post */ } {
    /* body */
}
```

A concrete example — iterate 0 to 9:

```yul
for { let i := 0 } lt(i, 10) { i := add(i, 1) } {
    // body: runs with i = 0, 1, 2, ..., 9
}
```

**Key differences from Solidity:**
- No `i++` or `++i` syntax. Use `i := add(i, 1)`.
- No `<=` opcode. There's `lt` (less than) and `gt` (greater than), but no `le` or `ge`. For "less than or equal," use `iszero(gt(i, limit))` or restructure: `lt(i, add(limit, 1))` (but watch for overflow if `limit` is `type(uint256).max`).
- No `break` or `continue`. If you need early exit, wrap the loop in a Yul function and use `leave`. To skip iterations, use an `if` guard inside the body.

**Gas-efficient patterns:**

```yul
// GOOD: Cache array length outside the loop
let len := mload(arr)              // read length once
for { let i := 0 } lt(i, len) { i := add(i, 1) } {
    let element := mload(add(add(arr, 0x20), mul(i, 0x20)))
    // process element
}

// BAD: Read length every iteration (for storage arrays)
// for { let i := 0 } lt(i, sload(lenSlot)) { i := add(i, 1) } {
//     ^^^^ SLOAD every iteration = 2100 gas cold, 100 warm per loop!
// }
```

**When loops are safe vs dangerous:**

| Pattern | Safety | Why |
|---------|--------|-----|
| Fixed bounds (`i < 10`) | Safe | Gas cost is constant, known at compile time |
| Bounded by constant (`i < MAX_BATCH`) | Safe | Worst case is bounded, auditable |
| Bounded by storage length | Dangerous | Attacker can grow the array to exhaust gas |
| Unbounded iteration | Critical risk | Block gas limit is the only bound — DoS vector |

💻 **Quick Try:**

Sum an array of 5 `uint256`s in Yul and compare gas to Solidity:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract LoopGas {
    function sumSolidity(uint256[] calldata arr) external pure returns (uint256 total) {
        for (uint256 i = 0; i < arr.length; i++) {
            total += arr[i];
        }
    }

    function sumYul(uint256[] calldata arr) external pure returns (uint256) {
        assembly {
            let total := 0
            // arr.offset is at position calldataload(4), arr.length at calldataload(36)
            // For calldata arrays: offset is in arg slot 0, length at the offset
            let offset := add(4, calldataload(4))   // skip selector + follow offset
            let len := calldataload(offset)
            let dataStart := add(offset, 0x20)       // elements start after length

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                total := add(total, calldataload(add(dataStart, mul(i, 0x20))))
            }

            mstore(0x00, total)
            return(0x00, 0x20)
        }
    }
}
```

Call both with `[10, 20, 30, 40, 50]` and compare gas. The Yul version skips bounds checks and overflow checks, saving ~15-20 gas per iteration.

---

<a id="loop-gas-anatomy"></a>
#### 🔍 Deep Dive: Loop Gas Anatomy

Every loop iteration has fixed overhead from the control flow opcodes, regardless of what the body does:

```
Per-iteration overhead:
┌──────────────────────────────────────────────────────────────┐
│ JUMPDEST        │  1 gas  │ loop_start label                 │
│ [condition]     │  ~6 gas │ e.g., LT(3) on two stack vals   │
│ ISZERO          │  3 gas  │ negate for skip pattern          │
│ PUSH2 loop_end  │  3 gas  │ destination for exit             │
│ JUMPI           │ 10 gas  │ conditional jump                 │
│ [body]          │  ? gas  │ your actual work                 │
│ [post]          │  ~6 gas │ e.g., ADD(3) + DUP/SWAP         │
│ PUSH2 loop_start│  3 gas  │ destination for loop back        │
│ JUMP            │  8 gas  │ unconditional jump               │
├──────────────────┼─────────┼──────────────────────────────────┤
│ Total overhead   │ ~31 gas │ per iteration, excluding body   │
└──────────────────┴─────────┴──────────────────────────────────┘
```

**Practical impact:**
- 100 iterations x 31 gas overhead = 3,100 gas just for loop control
- If the body does an SLOAD (100 gas warm), total per iteration = ~131 gas
- If the body does an SSTORE (5,000 gas), the 31 gas overhead is negligible

**Why `unchecked { ++i }` in Solidity matches Yul's `i := add(i, 1)`:**
Both skip the overflow check. In checked Solidity, `i++` adds ~20 gas per iteration for the overflow comparison. Since loop indices almost never overflow (you'd need 2^256 iterations), `unchecked` is standard practice in gas-optimized Solidity. In Yul, you get this by default — `add` does not check for overflow.

#### 🔗 DeFi Pattern Connection

**Where loops matter in DeFi:**

1. **Batch operations:** Airdrop contracts, multi-transfer, batch liquidation. These iterate over recipients and amounts. Uniswap V3's `collect()` and Aave V3's `executeBatchFlashLoan()` both use bounded loops.

2. **Array iteration:** Token allowlist checks, validator set updates, reward distribution. The gas cost of iterating a 100-element array is ~3,100 gas overhead + body cost — manageable for most operations.

3. **The "bounded loop" audit rule:** Auditors flag unbounded loops as **high severity**. If a user can grow the array (e.g., by calling `addToList()` repeatedly), they can make any function that iterates the list exceed the block gas limit. The standard fix: paginated iteration with `startIndex` and `batchSize` parameters.

4. **Curve's StableSwap:** The `get_D()` function uses a Newton-Raphson loop to find the invariant. It's bounded by `MAX_ITERATIONS = 255` — if it doesn't converge, it reverts. This is the textbook example of a safe math loop.

#### ⚠️ Common Mistakes

- **Off-by-one with `lt`.** `for { let i := 0 } lt(i, len) { i := add(i, 1) }` iterates `0` to `len-1` (correct for array indexing). Using `gt(len, i)` is equivalent but less readable. Using `iszero(eq(i, len))` also works but costs an extra opcode.
- **Forgetting there's no `break` in Yul for-loops.** You cannot exit a loop early with `break`. The workaround: wrap the loop body in a Yul function and use `leave` to exit, or restructure the loop condition to include your exit criteria. Example: `for { let i := 0 } and(lt(i, len), iszero(found)) { ... }`.
- **Modifying the loop variable inside the body.** `i := add(i, 2)` inside the body, combined with `i := add(i, 1)` in the post block, increments by 3 total. This leads to skipped or repeated iterations. Only modify the loop variable in the post block.
- **Not caching storage reads.** `for { let i := 0 } lt(i, sload(lenSlot)) { ... }` does an SLOAD every iteration. Cold first access = 2,100 gas, then 100 gas per subsequent check. For a 100-iteration loop, that's 12,000 gas wasted on length reads alone. Always cache: `let len := sload(lenSlot)`.

#### 💼 Job Market Context

**"How do you iterate arrays safely in assembly?"**
- Good: "Use a `for` loop with `lt(i, length)`, pre-compute the length"
- Great: "Cache the length in a local variable to avoid repeated SLOAD/MLOAD. Use `lt(i, len)` for the condition — there's no `le` opcode, so `<=` requires `iszero(gt(i, len))` or `lt(i, add(len, 1))`, which can overflow at type max. For storage arrays, load the length once with `sload` and compute element slots with `add(baseSlot, i)`. Always ensure the loop is bounded — unbounded loops are an audit finding because an attacker can grow the array to make the function exceed the block gas limit"

🚩 **Red flag:** Writing unbounded loops over user-controlled arrays

**Pro tip:** In interviews, always mention the DoS vector — it shows security awareness alongside assembly skill. If you can also cite Curve's Newton-Raphson bounded loop or Aave's batch size limits, you demonstrate real protocol knowledge

---

<a id="yul-leave"></a>
### 💡 Concept: `leave` — Early Exit

**Why this matters:** `leave` is Yul's equivalent of `return` in other languages — it exits the current Yul function immediately. Without it, you'd need deeply nested `if` blocks for guard-then-compute patterns.

```yul
function findIndex(arr, len, target) -> idx {
    idx := 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  // not found sentinel
    for { let i := 0 } lt(i, len) { i := add(i, 1) } {
        if eq(mload(add(arr, mul(add(i, 1), 0x20))), target) {
            idx := i
            leave   // exit the function immediately
        }
    }
    // if we get here, target wasn't found; idx is still the sentinel
}
```

**Key rules:**
- `leave` only works inside **Yul functions**, not in top-level `assembly { }` blocks. If you try to use `leave` outside a function, the compiler will error.
- It exits the **innermost** function — if you have nested Yul functions, `leave` exits the one it's in, not the outer one.
- For top-level assembly blocks, use `return(ptr, size)` or `revert(ptr, size)` to exit execution entirely.

**How `leave` compiles:** It's a JUMP to the function's exit JUMPDEST — the cleanup point where return values are on the stack and the return program counter is used. No special opcode, just a JUMP.

**Pattern: Guard-and-compute in Yul functions:**

```yul
function safeDiv(a, b) -> result {
    if iszero(b) {
        result := 0
        leave   // don't divide by zero
    }
    result := div(a, b)
}
```

This is cleaner than the alternative without `leave`:

```yul
function safeDiv(a, b) -> result {
    switch iszero(b)
    case 1 { result := 0 }
    default { result := div(a, b) }
}
```

Both work, but `leave` scales better when you have multiple guard conditions — each can `leave` independently without nesting.

---

<a id="yul-to-bytecode"></a>
#### 🔍 Deep Dive: From Yul to JUMP/JUMPI — Bytecode Comparison

In [Module 1](1-evm-fundamentals.md#opcode-categories) you learned that JUMP costs 8 gas, JUMPI costs 10 gas, and JUMPDEST costs 1 gas. Now you can see exactly how your Yul code maps to these opcodes.

**`if` compiles to JUMPI (skip pattern):**

```
Yul:                        Bytecode:

if condition {              [push condition value]
    body                    ISZERO            ; negate: skip body if false
}                           PUSH2 end_label
                            JUMPI             ; jump past body if condition was 0
                            [body opcodes]
                            JUMPDEST          ; end_label — execution continues here
```

The compiler inverts the condition with ISZERO so JUMPI *skips* the body when the original condition is false. This is the "skip pattern" — the most common JUMPI usage.

**`switch` (2 cases + default) compiles to chained JUMPI:**

```
Yul:                                  Bytecode:

switch selector                       [push selector]
case 0xAAAAAAAA { case1_body }        DUP1
case 0xBBBBBBBB { case2_body }       PUSH4 0xAAAAAAAA
default { default_body }              EQ
                                      PUSH2 case1_label
                                      JUMPI              ; jump if match
                                      DUP1
                                      PUSH4 0xBBBBBBBB
                                      EQ
                                      PUSH2 case2_label
                                      JUMPI              ; jump if match
                                      POP                ; clean up selector
                                      [default body]
                                      PUSH2 end
                                      JUMP
                                      JUMPDEST           ; case1_label
                                      POP                ; clean up selector
                                      [case1 body]
                                      PUSH2 end
                                      JUMP
                                      JUMPDEST           ; case2_label
                                      POP                ; clean up selector
                                      [case2 body]
                                      JUMPDEST           ; end
```

Notice: each case costs EQ(3) + JUMPI(10) = 13 gas to check. A switch with 10 cases means up to 130 gas just searching for the right case (linear scan). This is why Solidity's compiler switches to binary search for larger contracts.

**`for` loop compiles to JUMP + JUMPI:**

```
Yul:                                  Bytecode:

for { let i := 0 }                   PUSH1 0x00         ; [init] i = 0
    lt(i, 10)                         JUMPDEST           ; loop_start
    { i := add(i, 1) }               DUP1
{                                     PUSH1 0x0A         ; 10
    body                              LT
}                                     ISZERO
                                      PUSH2 loop_end
                                      JUMPI              ; exit if i >= 10
                                      [body opcodes]
                                      PUSH1 0x01
                                      ADD                ; [post] i = i + 1
                                      PUSH2 loop_start
                                      JUMP               ; back to condition
                                      JUMPDEST           ; loop_end
```

Each iteration: JUMPDEST(1) + condition(~6) + ISZERO(3) + PUSH2(3) + JUMPI(10) + body + post(~6) + PUSH2(3) + JUMP(8) = **~31 gas overhead** plus whatever the body costs.

💻 **Quick Try:**

Compile a simple contract and inspect the bytecode:

```bash
# Create a minimal contract
cat > /tmp/Switch.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
contract Switch {
    fallback() external payable {
        assembly {
            switch calldataload(0)
            case 1 { mstore(0, 10) return(0, 32) }
            case 2 { mstore(0, 20) return(0, 32) }
            default { revert(0, 0) }
        }
    }
}
EOF

# Inspect the Yul IR
forge inspect Switch ir-optimized

# Or disassemble the bytecode
cast disassemble $(forge inspect Switch bytecode)
```

Look for the JUMPI instructions in the output. Count them — you should see exactly 2 (one per case).

**Connection back to Module 1:** In [Module 1](1-evm-fundamentals.md#opcode-categories) you learned JUMP costs 8 gas, JUMPI costs 10, JUMPDEST costs 1. Now you can see exactly how many JUMPs your Yul code generates — and why a `switch` with 10 cases creates 10 JUMPI instructions (linear scan), costing up to 130 gas just to find the matching case.

---

## 📋 Key Takeaways: Control Flow in Yul

After this section, you should be able to:

- Write guard clauses with `if condition { }` and explain that Yul has no `else` — use `switch` or `iszero()` for negation
- Implement multi-branch logic with `switch val case X { } default { }` and explain why there's no fall-through
- Write gas-efficient `for` loops with explicit init/condition/post blocks, using `add(i, 1)` and `lt` instead of Solidity's `++` and `<=`
- Use `leave` for early exits from Yul functions and explain that all control flow compiles to JUMP/JUMPI/JUMPDEST sequences

<details>
<summary>Check your understanding</summary>

- **if with no else**: Yul's `if` only has a truthy branch -- there is no `else` keyword. For "if not" logic, wrap the condition in `iszero()`. For multi-branch logic, use `switch` instead.
- **switch statement**: `switch val case 0 { } case 1 { } default { }` with no fall-through between cases. Each case must be a literal constant (not a variable or expression). The `default` branch handles unmatched values.
- **for loops**: `for { let i := 0 } lt(i, n) { i := add(i, 1) } { body }` with explicit init, condition, and post blocks. Use `lt` (not `le` or `<=`) because there is no `le` opcode -- `lt(i, n)` is the idiomatic bound check. `add(i, 1)` replaces `++`.
- **leave and compilation**: `leave` exits the current Yul function immediately (like `return` in other languages but without a value -- use return variables). All Yul control flow compiles to JUMP/JUMPI/JUMPDEST sequences in bytecode, with each branch or loop iteration being a conditional or unconditional jump.

</details>

---

## 💡 Yul Functions (Internal)

Yul functions are how you organize assembly code. Without them, complex assembly becomes an unreadable wall of opcodes. They reduce stack pressure (each function scope has its own variable space), enable code reuse, and make assembly readable enough to audit.

This section covers defining functions, understanding when the optimizer inlines them, and managing the 16-slot stack depth limit.

---

<a id="yul-functions"></a>
### 💡 Concept: Defining and Calling Yul Functions

**Why this matters:** In production assembly (Solady, Uniswap V4), you'll see dozens of Yul functions per contract. They're the primary unit of code organization in assembly — the equivalent of internal functions in Solidity.

**Syntax:**

```yul
// Single return value
function name(param1, param2) -> result {
    result := add(param1, param2)
}

// Multiple return values
function divmod(a, b) -> quotient, remainder {
    quotient := div(a, b)
    remainder := mod(a, b)
}

// No return value (side effects only)
function requireNonZero(value) {
    if iszero(value) { revert(0, 0) }
}
```

**Key rules:**
- Functions can only be **called within the same `assembly` block** where they're defined. They don't exist outside assembly.
- Variables declared inside a function are **scoped to that function**. This is the key benefit for stack management — each function gets a clean variable scope.
- Functions can call other Yul functions defined in the same assembly block.
- **Return values must be assigned.** If you declare `-> result` but don't assign it, `result` defaults to `0`.

💻 **Quick Try:**

Define `min` and `max` as Yul functions:

```solidity
function minMax(uint256 a, uint256 b) external pure returns (uint256, uint256) {
    assembly {
        function min(x, y) -> result {
            result := y
            if lt(x, y) { result := x }
        }

        function max(x, y) -> result {
            result := x
            if lt(x, y) { result := y }
        }

        mstore(0x00, min(a, b))
        mstore(0x20, max(a, b))
        return(0x00, 0x40)
    }
}
```

Deploy and test with `(100, 200)`. You should get `(100, 200)`. Test with `(300, 50)` — should get `(50, 300)`.

---

<a id="utility-library"></a>
#### 🎓 Intermediate Example: Building a Utility Library in Yul

Before you write full contracts in assembly, you need a toolkit. Here are the helper functions you'll reuse across nearly every assembly block:

```yul
assembly {
    // ── Guards ──────────────────────────────────────────────

    // Revert with no data (cheapest revert)
    function require(condition) {
        if iszero(condition) { revert(0, 0) }
    }

    // Revert with a 4-byte error selector
    function requireWithSelector(condition, sel) {
        if iszero(condition) {
            mstore(0x00, shl(224, sel))
            revert(0x00, 0x04)
        }
    }

    // ── Math ────────────────────────────────────────────────

    // Overflow-checked addition
    function safeAdd(a, b) -> result {
        result := add(a, b)
        if lt(result, a) { revert(0, 0) }  // overflow
    }

    // Min / Max
    function min(a, b) -> result {
        result := b
        if lt(a, b) { result := a }
    }

    function max(a, b) -> result {
        result := a
        if lt(a, b) { result := b }
    }

    // ── Storage helpers ─────────────────────────────────────

    // Compute mapping slot: keccak256(key . baseSlot)
    // Reuses the formula from Module 3
    function getMappingSlot(key, baseSlot) -> slot {
        mstore(0x00, key)
        mstore(0x20, baseSlot)
        slot := keccak256(0x00, 0x40)
    }

    // Compute nested mapping slot: mapping[key1][key2]
    function getNestedMappingSlot(key1, key2, baseSlot) -> slot {
        mstore(0x00, key1)
        mstore(0x20, baseSlot)
        let intermediate := keccak256(0x00, 0x40)
        mstore(0x00, key2)
        mstore(0x20, intermediate)
        slot := keccak256(0x00, 0x40)
    }
}
```

Note how `getMappingSlot` reuses the [Module 3 mapping formula](3-storage.md#mapping-slots) as a callable function. This is the pattern in production assembly — define your slot computation functions once at the top of the assembly block, then call them throughout.

**Solady uses this exact pattern.** Open any Solady contract and you'll see a library of internal Yul functions at the top of the assembly block. The naming conventions are consistent: `_get`, `_set`, `_require`, etc.

---

<a id="inlining"></a>
### 💡 Concept: Inlining Behavior — When Functions Become JUMPs

**Why this matters:** Yul functions can either be **inlined** (copied into the call site) or compiled as **JUMP targets** (called via JUMP/JUMPDEST). The optimizer decides which approach to use, and the choice affects both gas cost and bytecode size.

**Inlining:** The compiler copies the function's body directly into every call site. No JUMP, no JUMPDEST, no call overhead. The function "disappears" from the bytecode.

```yul
// This will likely be inlined (tiny body)
function isZero(x) -> result {
    result := iszero(x)
}

// After inlining, "isZero(val)" just becomes "iszero(val)" at the call site
```

**JUMP target:** The compiler emits the function body once, and each call site JUMPs to it and JUMPs back. This saves bytecode size but costs ~20 gas per call (JUMP to function + JUMPDEST + JUMP back + JUMPDEST).

```yul
// This is more likely to be a JUMP target (larger body, multiple call sites)
function getMappingSlot(key, baseSlot) -> slot {
    mstore(0x00, key)
    mstore(0x20, baseSlot)
    slot := keccak256(0x00, 0x40)
}
```

**The optimizer's heuristic:**
- Small functions (1-2 opcodes): almost always inlined
- Large functions called from one site: inlined (no size penalty)
- Large functions called from multiple sites: JUMP target (saves bytecode)
- The decision is automatic — you **cannot force** inlining in Yul

**How to check:** Run `forge inspect Contract ir-optimized` and look for your function names. Inlined functions disappear entirely — their body appears at each call site. JUMP-target functions appear as labeled blocks.

**Trade-off:**

| Approach | Gas per call | Bytecode size | Best when |
|----------|-------------|---------------|-----------|
| Inlined | 0 overhead | Larger (duplicated) | Small functions, few call sites |
| JUMP target | ~20 gas | Smaller (shared) | Large functions, many call sites |

**For production code:** Let the optimizer decide. Only manually inline (by not using a function at all) if gas profiling shows a hot path where the 20-gas JUMP overhead matters. In most DeFi contracts, storage operations dominate gas costs, making the JUMP overhead negligible.

---

<a id="stack-depth"></a>
### 💡 Concept: Stack Depth and Yul Functions

**Why this matters:** "Stack too deep" is one of the most common errors in Solidity, and understanding *why* it happens — it's a hardware constraint, not a language bug — is essential for working in assembly. Yul functions are the primary tool for managing stack depth.

The EVM's DUP and SWAP opcodes can only reach **16 items deep** on the stack. DUP1 copies the top item, DUP16 copies the 16th item from the top. There is no DUP17. If the compiler needs to access a variable that's buried deeper than 16 slots, it can't — hence "stack too deep."

Each Yul function creates a **new scope**. Only the function's parameters, local variables, and return values occupy its stack frame. This means you can have 50 variables across your entire assembly block, but as long as no single function uses more than ~14 simultaneously, you'll never hit the limit.

---

<a id="stack-layout"></a>
#### 🔍 Deep Dive: Stack Layout During a Yul Function Call

When a Yul function is called (not inlined), the stack looks like this:

```
Before call:     [...existing stack items...]

Push args:       [...existing...][arg1][arg2]

JUMP to func:    [...existing...][return_pc][arg1][arg2]
                                  ↑ pushed by the JUMP mechanism

Inside function: [...existing...][return_pc][arg1][arg2][local1][local2][result]
                                                                        ↑ DUP/SWAP
                                                                          can only
                  ←─────────── 16 slots reachable from top ──────────────→  reach
                                                                            here
```

The **reachable window** is always the top 16 slots. Everything below is invisible to DUP/SWAP. This means:

**Parameters + locals + return values must fit in ~12-14 stack slots** (leaving room for temporary values during expression evaluation).

If you exceed this:

**Solution 1: Decompose into smaller functions.** Each function gets its own scope. A function that takes 4 params and uses 4 locals is fine (8 slots). Calling another function from inside passes values as arguments, keeping each scope small.

```yul
// BAD: Too many variables in one function
function doEverything(a, b, c, d, e, f, g, h) -> result {
    let x := add(a, b)
    let y := mul(c, d)
    let z := sub(e, f)
    let w := div(g, h)
    // ... stack too deep when using x, y, z, w together with a-h
}

// GOOD: Decompose
function computeFirst(a, b, c, d) -> partial1 {
    partial1 := add(mul(a, b), mul(c, d))
}

function computeSecond(e, f, g, h) -> partial2 {
    partial2 := add(sub(e, f), div(g, h))
}

function combine(a, b, c, d, e, f, g, h) -> result {
    result := add(computeFirst(a, b, c, d), computeSecond(e, f, g, h))
}
```

**Solution 2: Spill to memory.** Use scratch space (`0x00-0x3f`) or allocated memory for intermediate values. Each spill costs 3 gas (MSTORE) + 3 gas (MLOAD) = 6 gas, but frees a stack slot.

```yul
// Spill intermediate to memory scratch space
mstore(0x00, expensiveComputation)   // save to scratch
// ... do other work with freed stack slot ...
let saved := mload(0x00)             // restore when needed
```

**Solution 3: Restructure.** Sometimes the code can be rewritten to reduce the number of simultaneously live variables. Compute and consume values immediately rather than holding everything until the end.

**What `via_ir` does:** The Solidity compiler's `via_ir` codegen pipeline automatically moves variables to memory when stack depth is exceeded. That's why enabling `via_ir` "fixes" stack-too-deep errors in Solidity. But it adds gas overhead for the memory spills. Hand-written assembly gives you control over *which* values live in memory vs stack — important for gas-critical paths.

#### ⚠️ Common Mistakes

- **Too many local variables in one function.** If you declare 10 `let` variables plus have 4 parameters, that's 14 slots before any temporary values. You'll hit the limit. Split into helper functions.
- **Passing too many parameters.** A function with 8+ parameters is a design smell. Group related values or compute them inside the function from fewer inputs.
- **Forgetting that return values also consume stack slots.** `function f(a, b, c) -> x, y, z` uses 6 slots (3 params + 3 returns) before any locals. Add 3 locals and you're at 9 — getting close.
- **Not accounting for expression temporaries.** `add(mul(a, b), mul(c, d))` needs stack space for the intermediate `mul` results. The compiler handles this, but deeply nested expressions push the limit.

#### 💼 Job Market Context

**"How do you handle 'stack too deep' in assembly?"**
- Good: "Break the code into smaller Yul functions to reduce variables per scope"
- Great: "The stack limit is 16 reachable slots (DUP16/SWAP16 max). Each Yul function gets a clean scope — only its parameters, locals, and return values count. So the fix is decomposition: extract logic into Yul functions with focused parameter lists. For truly complex operations, spill intermediate values to memory (0x00-0x3f scratch space or allocated memory). The `via_ir` compiler does this automatically, but hand-written assembly gives you control over which values live in memory vs stack, which matters for gas-critical paths"

🚩 **Red flag:** Not knowing why "stack too deep" happens (it's not a language bug, it's a hardware constraint — the DUP/SWAP opcodes only reach 16 deep)

**Pro tip:** Counting stack depth by hand is a real skill for auditors. Practice by tracing through Solady's complex functions — pick a function, list the variables, count the max simultaneous live count

---

<a id="exercise2"></a>
## 🎯 Build Exercise: LoopAndFunctions

**Workspace:**
- Implementation: [`workspace/src/part4/module4/exercise2-loop-and-functions/LoopAndFunctions.sol`](../workspace/src/part4/module4/exercise2-loop-and-functions/LoopAndFunctions.sol)
- Tests: [`workspace/test/part4/module4/exercise2-loop-and-functions/LoopAndFunctions.t.sol`](../workspace/test/part4/module4/exercise2-loop-and-functions/LoopAndFunctions.t.sol)

Practice Yul functions and loop patterns. Each function has a Solidity signature with an `assembly { }` body — you write the internals. This exercise focuses on control flow and iteration, not dispatch.

**What's provided:**
- Function signatures with parameter names
- Return types for each function
- Hints in comments pointing to relevant module sections

**5 TODOs:**

1. **`requireWithError(bool condition, bytes4 selector)`** — If condition is false, revert with the given 4-byte error selector. This is your reusable guard function.
2. **`min(uint256,uint256)` + `max(uint256,uint256)`** — Implement both using Yul functions. The Solidity wrappers call the Yul functions internally. Use the `if lt(a, b)` pattern.
3. **`sumArray(uint256[] calldata)`** — Loop through a calldata array and return the sum. You'll need to decode the array offset, read the length, and iterate through elements using `calldataload` with computed offsets.
4. **`findMax(uint256[] calldata)`** — Loop through a calldata array and return the maximum element. Combine the loop pattern from TODO 3 with the `max` Yul function from TODO 2.
5. **`batchTransfer(address[] calldata recipients, uint256[] calldata amounts)`** — Loop through two parallel calldata arrays, performing storage writes for each pair. Validate that both arrays have the same length. This combines loops, storage (from Module 3), and error handling.

**🎯 Goal:** Practice Yul function definition, gas-efficient loops, and calldata array decoding in a controlled environment. Each TODO builds on the previous one.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module4/exercise2-loop-and-functions/*"
```

---

## 📋 Key Takeaways: Yul Functions

After this section, you should be able to:

- Define Yul functions with `function name(a, b) -> result { }` and use multiple return values
- Explain when the optimizer inlines a function (small body → zero overhead) vs generates a JUMP call (~20 gas overhead)
- Diagnose stack-too-deep errors in Yul and resolve them by decomposing large functions or reducing live variables

<details>
<summary>Check your understanding</summary>

- **Yul function syntax**: `function name(a, b) -> result { result := add(a, b) }`. Multiple return values are supported: `-> (x, y)`. Variables are scoped to the function body, reducing stack pressure compared to inline code.
- **Inlining behavior**: The Yul optimizer inlines small functions (eliminating the JUMP/JUMPI overhead entirely). Larger functions remain as calls with ~20 gas overhead per invocation (JUMP to function + JUMP back). You cannot force or prevent inlining -- the optimizer decides based on code size and call count.
- **Stack-too-deep in Yul**: The EVM can only access the top 16 stack slots (DUP1-16, SWAP1-16). If a Yul function has too many live variables at once, the compiler cannot reach them all. Fix by splitting into smaller functions (each gets its own scope), reusing variables, or storing intermediate values in memory.

</details>

---

## 💡 Function Selector Dispatch

The dispatch table is the entry point of every Solidity contract. When you call `transfer()`, the EVM doesn't know what "functions" are — it sees raw bytes. The dispatcher examines the first 4 bytes of calldata and routes execution to the right code. Every Solidity contract has this logic auto-generated. Now you'll build one by hand.

This is where Modules 2, 3, and 4 converge: you need calldata decoding ([Module 2](2-memory-calldata.md#calldata-layout)), storage operations ([Module 3](3-storage.md#sload-sstore-yul)), and control flow (this module) all working together.

---

<a id="dispatch-problem"></a>
### 💡 Concept: The Dispatch Problem

**Why this matters:** Understanding dispatch is understanding how the EVM "finds" your function. This knowledge is essential for proxy patterns, gas optimization (ordering functions by call frequency), and building contracts in raw assembly.

Every external call to a contract follows this sequence:

1. **Extract selector** — read the first 4 bytes of calldata
2. **Find matching function** — compare the selector against known values
3. **Decode arguments** — read parameters from calldata positions 4+
4. **Execute** — run the function logic
5. **Encode return** — write the result to memory and RETURN

Steps 1 and 2 are the **dispatch table**. In Solidity, the compiler generates this automatically. In assembly, you write it yourself.

**Recap from [Module 2](2-memory-calldata.md#calldata-layout):** The selector is extracted with:

```yul
let selector := shr(224, calldataload(0))
```

`calldataload(0)` reads 32 bytes starting at offset 0. `shr(224, ...)` shifts right by 224 bits (256 - 32 = 224), leaving just the first 4 bytes in the low 32 bits of the stack value. What Solidity generates automatically, you'll now write by hand.

---

<a id="if-chain"></a>
### 💡 Concept: if-Chain Dispatch

**Why this matters:** This is the simplest dispatch pattern — straightforward to write and easy to understand. It's what the Solidity compiler generates for small contracts.

```yul
assembly {
    let selector := shr(224, calldataload(0))

    if eq(selector, 0x18160ddd) {   // totalSupply()
        mstore(0x00, sload(0))      // slot 0 = totalSupply
        return(0x00, 0x20)
    }

    if eq(selector, 0x70a08231) {   // balanceOf(address)
        let account := calldataload(4)
        // compute mapping slot
        mstore(0x00, account)
        mstore(0x20, 1)             // slot 1 = balances mapping base
        let bal := sload(keccak256(0x00, 0x40))
        mstore(0x00, bal)
        return(0x00, 0x20)
    }

    if eq(selector, 0xa9059cbb) {   // transfer(address,uint256)
        // decode, validate, update storage...
        mstore(0x00, 1)             // return true
        return(0x00, 0x20)
    }

    revert(0, 0)                    // unknown selector
}
```

**Gas characteristics:**
- **Linear scan** — the first function is cheapest to reach (1 comparison), the last is most expensive (N comparisons).
- Each comparison costs: EQ(3) + JUMPI(10) = **13 gas**.
- For 3 functions: worst case = 39 gas. For 10 functions: worst case = 130 gas.
- **Optimization:** Put the most frequently called function first. For an ERC-20, `transfer` and `balanceOf` are called far more often than `name` or `symbol`.

**When optimal:** Few functions (4 or fewer). Above that, the linear cost starts to matter, and `switch` or binary search becomes better.

💻 **Quick Try:**

Write a 3-function dispatcher and test it:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SimpleDispatch {
    fallback() external payable {
        assembly {
            let sel := shr(224, calldataload(0))

            if eq(sel, 0x18160ddd) {   // totalSupply()
                mstore(0x00, 1000)
                return(0x00, 0x20)
            }

            if eq(sel, 0x70a08231) {   // balanceOf(address)
                mstore(0x00, 42)
                return(0x00, 0x20)
            }

            if eq(sel, 0x06fdde03) {   // name()
                // Return "Test" as string
                mstore(0x00, 0x20)     // offset
                mstore(0x20, 4)        // length
                mstore(0x40, "Test")   // data
                return(0x00, 0x60)
            }

            revert(0, 0)
        }
    }
}
```

Deploy, then test with `cast`:
```bash
cast call <address> "totalSupply()" --rpc-url <rpc>
cast call <address> "balanceOf(address)" 0x1234...
```

---

<a id="switch-dispatch"></a>
### 💡 Concept: switch-Based Dispatch

**Why this matters:** `switch` is the preferred pattern for hand-written dispatchers. It produces the same bytecode as an if-chain but makes the dispatch table structure explicit and readable.

```yul
assembly {
    switch shr(224, calldataload(0))
    case 0x18160ddd {   // totalSupply()
        mstore(0x00, sload(0))
        return(0x00, 0x20)
    }
    case 0x70a08231 {   // balanceOf(address)
        let account := calldataload(4)
        mstore(0x00, account)
        mstore(0x20, 1)
        mstore(0x00, sload(keccak256(0x00, 0x40)))
        return(0x00, 0x20)
    }
    case 0xa9059cbb {   // transfer(address,uint256)
        // ... implementation
        mstore(0x00, 1)
        return(0x00, 0x20)
    }
    default {
        revert(0, 0)     // unknown selector
    }
}
```

**Same gas as if-chain** at the bytecode level (both compile to linear JUMPI chains). But the advantages are:

1. **Cleaner syntax** — the dispatch table is visually obvious.
2. **The `default` branch** naturally handles both unknown selectors and serves as the fallback function.
3. **Easier to maintain** — adding a new function is adding a new `case`, not threading another `if` into the chain.

This is what you'll see in most hand-written assembly contracts and what you'll write in the exercises.

---

<a id="solidity-dispatch"></a>
#### 🔍 Deep Dive: How Solidity Actually Dispatches

For small contracts with 4 or fewer external functions, Solidity generates a simple linear if-chain — similar to what you just wrote. But for larger contracts, it switches to something smarter.

**Binary search dispatch:**

For contracts with more than ~4 external functions, the Solidity compiler **sorts selectors numerically** and generates a **binary search tree**. Instead of checking selectors one by one (O(n)), it compares against the middle value and branches left or right (O(log n)).

Here's how it works for a contract with 8 external functions. Assume the selectors, sorted numerically, are:

```
0x06fdde03 (name)
0x095ea7b3 (approve)
0x18160ddd (totalSupply)
0x23b872dd (transferFrom)
0x70a08231 (balanceOf)
0x95d89b41 (symbol)
0xa9059cbb (transfer)
0xdd62ed3e (allowance)
```

The compiler generates a binary search tree:

```
                        sel < 0x70a08231?
                       ╱                ╲
              sel < 0x18160ddd?    sel < 0xa9059cbb?
             ╱           ╲         ╱           ╲
    sel < 0x095ea7b3?   eq 0x18160ddd?  eq 0x70a08231?  sel < 0xdd62ed3e?
     ╱         ╲        │    ╲       │    ╲       ╱          ╲
eq 0x06fdde03  eq 0x095ea7b3  eq 0x23b872dd  eq 0x95d89b41  eq 0xa9059cbb  eq 0xdd62ed3e
 (name)        (approve)  (totalSupply) (transferFrom) (balanceOf)  (symbol)     (transfer)  (allowance)
```

**Gas impact:**
- Linear dispatch with 8 functions: worst case = 8 x 13 = **104 gas**
- Binary search with 8 functions: worst case = 3 comparisons = **39 gas**
- For 32 functions: linear = 416 gas, binary = 5 comparisons = **65 gas**

> **Perspective:** These are selector-matching costs only, not including function body execution. For a function that does storage operations (2,100+ gas each), the difference between 104 and 39 gas is <5% overhead. Dispatch optimization matters most for contracts with many functions on MEV-critical paths or ultra-optimized deployments (Solady, Huff).

**Why function ordering matters for gas:**

The binary search uses numerically sorted selectors — you can't control the tree structure directly in Solidity. But in assembly, you can:
- Order your if-chain or switch by call frequency (hot functions first)
- Use a jump table for O(1) dispatch (advanced — covered in Module 6)

**How to inspect dispatch logic:**

```bash
# View the Yul IR (shows switch/if structure)
forge inspect MyContract ir-optimized

# Disassemble to raw opcodes
cast disassemble $(forge inspect MyContract bytecode)
```

Look for clusters of `DUP1 PUSH4 EQ PUSH2 JUMPI` — each cluster is one selector comparison.

**Advanced: Beyond binary search:**

Some ultra-optimized frameworks use different strategies:
- **Huff / Solady:** Can use jump tables for O(1) dispatch (one JUMPI regardless of function count). This requires computing the jump destination from the selector — covered in [Module 6](6-gas-optimization.md).
- **Diamond Pattern (EIP-2535):** Puts selectors in different "facets" (contracts), so each facet has a small dispatch table. The main contract looks up which facet handles a selector, then DELEGATECALLs to it.

#### 💼 Job Market Context

**"How does the Solidity compiler handle function dispatch?"**
- Good: "It checks the selector against each function and routes to the right one"
- Great: "For 4 or fewer functions, it's a linear if-chain of JUMPI instructions — each costing 13 gas (EQ + JUMPI). For more functions, it uses binary search: selectors are sorted numerically, and the dispatcher does log(n) comparisons. A contract with 32 functions needs ~5 comparisons (65 gas) to find any function. This is why some protocols put frequently-called functions in a separate facet (Diamond pattern) — to keep the dispatch table small on hot paths. In hand-written assembly, you can go further: arrange selectors by call frequency or use jump tables for O(1) dispatch"

🚩 **Red flag:** Thinking dispatch is free or constant-cost

**Pro tip:** Know that function selector values affect gas cost. `0x00000001` would be found fastest in a binary search (always takes the left branch). Some MEV-optimized contracts pick selectors strategically using vanity selector mining via CREATE2. Tools like [`cast sig`](https://book.getfoundry.sh/reference/cast/cast-sig) compute selectors from signatures

---

<a id="fallback-receive"></a>
### 💡 Concept: Fallback and Receive in Assembly

**Why this matters:** Every Solidity contract has implicit dispatch for two special cases: receiving ETH with no calldata (`receive`), and handling calls with unknown selectors (`fallback`). In assembly, you write these explicitly.

**Receive:** Triggered when `calldatasize() == 0` — a plain ETH transfer with no function call.

**Fallback:** The catch-all after selector matching fails — the `default` branch of your `switch`, or the final `revert` after all `if` checks.

**Complete dispatch skeleton:**

```yul
assembly {
    // ── Step 1: Check for receive (no calldata = plain ETH transfer) ──
    if iszero(calldatasize()) {
        // Receive logic: accept ETH, maybe emit event, then stop
        // log0(0, 0) — or log with Transfer topic
        stop()
    }

    // ── Step 2: Extract selector ──
    let selector := shr(224, calldataload(0))

    // ── Step 3: Dispatch ──
    switch selector
    case 0x18160ddd {
        // totalSupply()
        mstore(0x00, sload(0))
        return(0x00, 0x20)
    }
    case 0x70a08231 {
        // balanceOf(address)
        let account := calldataload(4)
        mstore(0x00, account)
        mstore(0x20, 1)
        mstore(0x00, sload(keccak256(0x00, 0x40)))
        return(0x00, 0x20)
    }
    case 0xa9059cbb {
        // transfer(address,uint256)
        // ... full implementation
        mstore(0x00, 1)
        return(0x00, 0x20)
    }
    default {
        // ── Step 4: Fallback ──
        // Unknown selector: revert (no fallback logic)
        revert(0, 0)
    }
}
```

**Design decisions for the `default` branch:**
- **No fallback:** `revert(0, 0)` — the safest choice. Prevents accidental calls.
- **Accept any call:** `stop()` — dangerous, but used in some proxy patterns.
- **Forward to another contract:** DELEGATECALL in the default branch — this is the Diamond Pattern.

---

<a id="complete-dispatch"></a>
#### 🎓 Intermediate Example: Complete Dispatch with Receive + Fallback

Here's a full, compilable contract that accepts ETH, dispatches three functions, and reverts on unknown selectors:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract YulContract {
    // Storage layout:
    // Slot 0: owner (address)
    // Slot 1: balances mapping base
    // Slot 2: totalDeposited (uint256)

    constructor() {
        assembly {
            sstore(0, caller())   // set owner
        }
    }

    fallback() external payable {
        assembly {
            // ── Receive: plain ETH transfer ──
            if iszero(calldatasize()) {
                // Accept ETH, increment totalDeposited
                let current := sload(2)
                sstore(2, add(current, callvalue()))
                stop()
            }

            // ── Helper functions ──
            function require(condition) {
                if iszero(condition) { revert(0, 0) }
            }

            function getMappingSlot(key, base) -> slot {
                mstore(0x00, key)
                mstore(0x20, base)
                slot := keccak256(0x00, 0x40)
            }

            // ── Dispatch ──
            let selector := shr(224, calldataload(0))

            switch selector

            case 0x8da5cb5b {
                // owner() -> address
                mstore(0x00, sload(0))
                return(0x00, 0x20)
            }

            case 0x70a08231 {
                // balanceOf(address) -> uint256
                let account := calldataload(4)
                mstore(0x00, sload(getMappingSlot(account, 1)))
                return(0x00, 0x20)
            }

            case 0xd0e30db0 {
                // deposit() — payable
                let depositor := caller()
                let amount := callvalue()
                require(amount)  // must send ETH

                // Update balance
                let slot := getMappingSlot(depositor, 1)
                sstore(slot, add(sload(slot), amount))

                // Update total
                sstore(2, add(sload(2), amount))

                // Return success (empty return)
                return(0, 0)
            }

            default {
                // Unknown selector: revert
                revert(0, 0)
            }
        }
    }
}
```

This contract demonstrates the full pattern: receive handling, Yul helper functions, storage operations using Module 3 patterns, and switch-based dispatch. Every piece you've learned in Modules 1-4 is at work here.

---

<a id="dispatch-production"></a>
#### 🔗 DeFi Pattern Connection: Dispatch in Production

**Where dispatch patterns appear in real protocols:**

**1. EIP-1167 Minimal Proxy** — the entire contract IS a dispatcher:

The minimal proxy is ~45 bytes of raw bytecode. No Solidity, no Yul — pure opcodes. It copies all calldata, DELEGATECALLs to a hardcoded implementation address, and returns or reverts the result.

```
363d3d373d3d3d363d73<20-byte-impl-addr>5af43d82803e903d91602b57fd5bf3
```

Annotated bytecode walkthrough:

```
Opcode(s)   Stack (top → right)            Purpose
─────────   ───────────────────            ───────
36          [cds]                          CALLDATASIZE — push calldata length
3d          [0, cds]                       RETURNDATASIZE — push 0 (cheaper than PUSH1 0)
3d          [0, 0, cds]                    push 0 again
37          []                             CALLDATACOPY(0, 0, cds) — copy all calldata to memory[0]

3d          [0]                            push 0 (retOffset for DELEGATECALL)
3d          [0, 0]                         push 0 (retSize — we'll handle return manually)
3d          [0, 0, 0]                      push 0 (argsOffset — calldata starts at memory[0])
36          [cds, 0, 0, 0]                 CALLDATASIZE (argsSize)
3d          [0, cds, 0, 0, 0]             push 0 (value — not used in DELEGATECALL)
73<addr>    [impl, 0, cds, 0, 0, 0]       PUSH20 implementation address
5a          [gas, impl, 0, cds, 0, 0, 0]  GAS — forward all remaining gas
f4          [success, ...]                 DELEGATECALL(gas, impl, 0, cds, 0, 0)

3d          [rds, success]                 RETURNDATASIZE — how much data came back
82          [success, rds, success]        DUP3 (success flag)
80          [success, success, rds, ...]   DUP1
3e          [success]                      RETURNDATACOPY(0, 0, rds) — copy return data to memory[0]

90          [rds, success]                 SWAP — put returndatasize below
3d          [rds, rds, success]            RETURNDATASIZE
91          [success, rds, rds]            SWAP2
602b        [0x2b, success, rds, rds]      PUSH1 0x2b (success JUMPDEST offset)
57          [rds, rds]                     JUMPI — jump to 0x2b if success != 0

fd          []                             REVERT(0, rds) — failure: revert with return data
5b          [rds]                          JUMPDEST — success landing
f3          []                             RETURN(0, rds) — success: return the data
```

This ~45-byte contract does what OpenZeppelin's `Proxy.sol` does in Solidity — pure dispatch via DELEGATECALL, no selector routing needed. It's used everywhere: Uniswap V3 pool clones, Safe wallet proxies, minimal clone factories.

**2. Diamond Pattern (EIP-2535)** — multi-facet dispatch:

Instead of one big contract, the Diamond splits functions across multiple "facets" (implementation contracts). The dispatch works differently:

```yul
// Simplified Diamond dispatch (conceptual)
let selector := shr(224, calldataload(0))

// Look up which facet handles this selector
mstore(0x00, selector)
mstore(0x20, facetMappingSlot)
let facet := sload(keccak256(0x00, 0x40))  // facet address from storage

if iszero(facet) { revert(0, 0) }  // no facet registered

// DELEGATECALL to the facet
// (full delegatecall pattern covered in Module 5)
```

Each facet has its own small dispatch table. The main diamond contract just routes to the right facet. This keeps per-facet dispatch tables small (fast) while allowing unlimited total functions. Reference: [Part 1 Module 6 — Proxy Patterns](../part1/6-proxy-patterns.md).

**3. Solady's Assembly Organization:**

Solady structures assembly with internal Yul functions for reusable logic:

```yul
// Pattern from Solady's ERC20
assembly {
    // Utility functions defined first
    function _revert(offset, size) { revert(offset, size) }
    function _return(offset, size) { return(offset, size) }

    // Storage slot functions (consistent naming)
    function _balanceSlot(account) -> slot {
        mstore(0x0c, account)
        mstore(0x00, _BALANCE_SLOT_SEED)
        slot := keccak256(0x0c, 0x20)
    }

    // Dispatch uses these building blocks
    switch shr(224, calldataload(0))
    case 0xa9059cbb { /* transfer — uses _balanceSlot */ }
    // ...
}
```

Explore the full patterns at [github.com/Vectorized/solady](https://github.com/Vectorized/solady) — particularly `src/tokens/ERC20.sol`.

#### 💼 Job Market Context

**"Walk me through how a minimal proxy works at the bytecode level"**
- Good: "It copies calldata, DELEGATECALLs to the implementation, and returns or reverts the result"
- Great: "The EIP-1167 proxy is ~45 bytes of raw bytecode with no Solidity. It uses CALLDATASIZE to get input length, CALLDATACOPY to move all calldata to memory at offset 0, then DELEGATECALL to the hardcoded implementation address forwarding all gas. After the call, RETURNDATACOPY moves the response to memory. It checks the success flag with JUMPI — REVERT if false (forwards the error), RETURN if true (forwards the response). Every byte is optimized: RETURNDATASIZE is used instead of PUSH1 0 because it produces zero on the stack for 2 gas and 1 byte, versus 3 gas and 2 bytes for PUSH1 0. The implementation address is embedded directly in the bytecode as a PUSH20 literal"

🚩 **Red flag:** Not knowing that minimal proxies exist or how they save deployment gas (deploying a 45-byte clone vs a full contract)

**Pro tip:** Be able to decode the 45 bytes from memory — it's a common interview exercise for L2/infrastructure roles. Practice by reading the EIP-1167 spec and hand-annotating the bytecode

<a id="how-to-study"></a>
#### 📖 How to Study Dispatch-Heavy Contracts

1. **Start with `cast disassemble` or `forge inspect`** to see the dispatch table. Count the JUMPI instructions in the opening section — each one is a selector comparison.

2. **Count the selectors.** More than ~4? The compiler probably used binary search. Fewer? Linear if-chain. In hand-written assembly (Huff, Yul), it's always linear unless the author implemented something custom.

3. **Trace one function call end-to-end:** Extract selector from calldata → match in dispatch table → decode arguments from calldata → execute (storage reads/writes) → encode return value → RETURN. This is the complete lifecycle.

4. **Compare hand-written vs Solidity-generated dispatch.** Compile a simple ERC-20 in Solidity and inspect its bytecode. Then look at Solady's ERC-20 or a Huff ERC-20. Note the differences: hand-written code often has fewer safety checks and more optimized selector ordering.

5. **Good contracts to study:**
   - [Solady ERC20](https://github.com/Vectorized/solady/blob/main/src/tokens/ERC20.sol) — full assembly ERC-20 with Yul dispatch
   - [Huff ERC20](https://github.com/huff-language/huff-examples/tree/main/erc20) — ERC-20 in raw opcodes
   - [OpenZeppelin Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol) — assembly dispatch for proxy forwarding
   - [EIP-1167 reference](https://eips.ethereum.org/EIPS/eip-1167) — the minimal proxy bytecode

---

<a id="exercise1"></a>
## 🎯 Build Exercise: YulDispatcher

**Workspace:**
- Implementation: [`workspace/src/part4/module4/exercise1-yul-dispatcher/YulDispatcher.sol`](../workspace/src/part4/module4/exercise1-yul-dispatcher/YulDispatcher.sol)
- Tests: [`workspace/test/part4/module4/exercise1-yul-dispatcher/YulDispatcher.t.sol`](../workspace/test/part4/module4/exercise1-yul-dispatcher/YulDispatcher.t.sol)

Build a mini ERC-20 entirely in Yul. The contract has a single `fallback()` function containing your dispatch logic. Storage layout, error selectors, and function selectors are provided as constants — you write all the assembly.

**What's provided:**
- Storage slot constants (`TOTAL_SUPPLY_SLOT`, `BALANCES_SLOT`, `OWNER_SLOT`)
- Error selectors (`Unauthorized()`, `InsufficientBalance(uint256,uint256)`, `ZeroAddress()`)
- Function selectors for the 5 functions you'll implement
- The constructor (sets owner and mints initial supply)

**5 TODOs:**

1. **Selector dispatch** — Extract the selector from calldata and implement a `switch` statement routing to 5 function selectors. Revert with empty data on unknown selectors.
2. **`totalSupply()`** — Load total supply from storage slot 0, ABI-encode it, and return. The simplest function — one `sload`, one `mstore`, one `return`.
3. **`balanceOf(address)`** — Decode the address argument from calldata, compute the mapping slot using the [Module 3 formula](3-storage.md#mapping-slots) (`keccak256(key . baseSlot)`), load the balance, and return.
4. **`transfer(address,uint256)`** — Decode both arguments, validate the sender has sufficient balance (revert with `InsufficientBalance` if not), validate the recipient is not zero address, update both balances in storage, and return `true` (ABI-encoded as `uint256(1)`).
5. **`mint(address,uint256)`** — Check that the caller is the owner (revert with `Unauthorized` if not), validate the recipient is not zero address, increment the recipient's balance and the total supply.

**🎯 Goal:** Combine calldata decoding ([Module 2](2-memory-calldata.md#calldata-layout)), storage operations ([Module 3](3-storage.md#sload-sstore-yul)), and selector dispatch (this module) into a working contract. All 5 function calls should work identically to a standard Solidity ERC-20.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module4/exercise1-yul-dispatcher/*"
```

---

## 📋 Key Takeaways: Function Selector Dispatch

After this section, you should be able to:

- Extract a function selector from calldata: `shr(224, calldataload(0))` and route to handlers using `switch` or `if` chains
- Compare if-chain and switch-based dispatch (both linear O(n), same gas) with Solidity's binary search (O(log n) for >4 functions)
- Implement fallback and receive handlers in assembly: `calldatasize() == 0` check before dispatch, `default` branch for unknown selectors
- Describe the EIP-1167 minimal proxy at the bytecode level and explain how 45 bytes handles all dispatch via DELEGATECALL

<details>
<summary>Check your understanding</summary>

- **Selector extraction**: `shr(224, calldataload(0))` loads the first 32 bytes of calldata and shifts right by 224 bits (256 - 32), isolating the 4-byte selector in the low bits. Route with `switch` or `if eq(selector, 0x...)` chains.
- **Linear vs binary dispatch**: Both `if`-chains and `switch` in Yul produce linear O(n) dispatch -- each selector is checked sequentially. Solidity's compiler uses binary search for contracts with more than ~4 external functions, achieving O(log n). For hand-written assembly, order selectors by call frequency (most-called first) to minimize average gas.
- **Fallback and receive in assembly**: Check `calldatasize()` first -- if zero, execute receive logic (ETH transfers with no data). Otherwise, run the dispatch. The `default` branch of a `switch` (or a final `revert`) handles unknown selectors, equivalent to Solidity's `fallback()`.
- **EIP-1167 minimal proxy**: 45 bytes of bytecode that copies all calldata to memory, DELEGATECALLs to a hardcoded implementation address, copies return data, and returns or reverts. No selector dispatch needed -- it forwards everything blindly, making it the cheapest possible proxy at ~200 gas overhead per call.

</details>

---

## 💡 Error Handling Patterns in Yul

<a id="error-patterns"></a>

This topic was covered in depth in [Module 2 — Return Values & Errors](2-memory-calldata.md#return-errors). Here we apply those patterns specifically in the dispatch context, where error handling is most critical.

**Recap: Reverting with a selector:**

```yul
// Custom error: Unauthorized()  selector = 0x82b42900
mstore(0x00, shl(224, 0x82b42900))   // shift selector to high bytes
revert(0x00, 0x04)                     // revert with 4-byte selector
```

> **Two patterns, same result:** In [Module 2](2-memory-calldata.md#offset-explained) you saw `mstore(0x00, selector)` + `revert(0x1c, 0x04)` — the selector lands right-aligned at byte 28, so you read from offset 0x1c. Here we use `shl(224, selector)` + `revert(0x00, 0x04)` — shifting the selector to the high bytes so it starts at byte 0. Both produce identical 4-byte revert data. The `shl` pattern is more common in dispatch contexts because it's consistent with how you pack selectors into memory alongside parameters (at offset 0x04, 0x24, etc.).

**Revert with parameters:**

```yul
// Custom error: InsufficientBalance(uint256 available, uint256 required)
// selector = 0x2e1a7d4d (example)
mstore(0x00, shl(224, 0x2e1a7d4d))    // selector in first 4 bytes
mstore(0x04, availableBalance)          // first param at offset 4
mstore(0x24, requiredAmount)            // second param at offset 36
revert(0x00, 0x44)                      // 4 + 32 + 32 = 68 bytes
```

**Pattern: Define `require`-like functions at the top of your assembly block:**

```yul
assembly {
    // ── Error selectors ──
    // Unauthorized()
    function _revertUnauthorized() {
        mstore(0x00, shl(224, 0x82b42900))
        revert(0x00, 0x04)
    }

    // InsufficientBalance(uint256, uint256)
    function _revertInsufficientBalance(available, required) {
        mstore(0x00, shl(224, 0x2e1a7d4d))
        mstore(0x04, available)
        mstore(0x24, required)
        revert(0x00, 0x44)
    }

    // ── Usage in dispatch ──
    switch shr(224, calldataload(0))
    case 0xa9059cbb {
        // transfer(address,uint256)
        let to := calldataload(4)
        let amount := calldataload(36)
        let bal := sload(/* sender balance slot */)
        if lt(bal, amount) {
            _revertInsufficientBalance(bal, amount)
        }
        // ... rest of transfer
    }
    // ...
}
```

#### ⚠️ Common Mistakes

- **Forgetting to shift the selector left by 224 bits.** Storing raw `0x82b42900` at memory offset 0 puts it in the *low* bytes of the 32-byte word. `mstore` writes a full 32-byte word, so `mstore(0x00, 0x82b42900)` stores `0x0000...0082b42900`. You need `shl(224, 0x82b42900)` to put the selector in the *high* 4 bytes: `0x82b42900000000...00`. Alternatively, pre-compute the shifted value as a constant.
- **Using `revert(0, 0)` everywhere.** This gives no error information — debugging becomes impossible. Always encode a selector for debuggability. Etherscan, Tenderly, and other tools decode custom errors automatically.
- **Not bubbling up revert data from sub-calls.** When your contract calls another contract and it reverts, you should forward the revert data so the caller sees the original error. This is covered in detail in [Module 5 — External Calls](5-external-calls.md).

---

## 📋 Key Takeaways: Error Handling Patterns

After this section, you should be able to:

- Encode custom errors with selector and parameters in assembly using `shl(224, selector)` + `mstore` and explain the two offset patterns (0x00 with shl vs 0x1c without)
- Define reusable `_revertXxx()` Yul functions that centralize error encoding in dispatch contracts
- Explain why `revert(0, 0)` should be avoided in favor of selector-encoded errors for debuggability

<details>
<summary>Check your understanding</summary>

- **Error encoding in dispatch**: Use `mstore(0x00, shl(224, selector))` to place the 4-byte selector in high bytes, then `revert(0x00, 0x04)`. For errors with parameters, add arguments at 0x04, 0x24, etc., and increase the revert size accordingly. The alternative is `mstore(0x00, unshiftedSelector)` + `revert(0x1c, 0x04)`, reading from byte 28 where the low 4 bytes sit.
- **Reusable _revertXxx() functions**: Define Yul helper functions like `function _revertUnauthorized() { mstore(0x00, shl(224, 0x82b42900)) revert(0x00, 0x04) }`. This centralizes error encoding, reduces code duplication across dispatch branches, and makes the assembly easier to audit.
- **Avoiding revert(0, 0)**: An empty revert returns zero bytes of error data. Etherscan, Tenderly, and frontend libraries cannot decode the failure reason, making debugging nearly impossible. Always encode at least a 4-byte selector so tools can identify which error occurred.

</details>

---

## 📚 Resources

**Essential References:**
- [Yul Specification](https://docs.soliditylang.org/en/latest/yul.html) — Official Yul language reference (control flow, functions, scoping rules)
- [evm.codes](https://www.evm.codes/) — Interactive opcode reference with gas costs for JUMP, JUMPI, JUMPDEST
- [EVM Playground](https://www.evm.codes/playground) — Step through bytecode execution to see JUMP/JUMPI in action

**EIPs Referenced:**
- [EIP-1167: Minimal Proxy Contract](https://eips.ethereum.org/EIPS/eip-1167) — Clone factory standard (the 45-byte dispatcher)
- [EIP-2535: Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) — Multi-facet proxy with selector-to-facet dispatch

**Production Code:**
- [Solady](https://github.com/Vectorized/solady) — Gas-optimized Solidity/assembly library; study `src/tokens/ERC20.sol` for dispatch patterns
- [OpenZeppelin Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol) — Proxy dispatch implemented in Solidity inline assembly
- [Huff ERC-20](https://github.com/huff-language/huff-examples/tree/main/erc20) — Full ERC-20 in raw opcodes (no Yul, no Solidity)

**Tools:**
- `forge inspect Contract ir-optimized` — View the Yul IR output to see how Solidity compiles dispatch logic
- `cast disassemble` — Decode deployed bytecode to human-readable opcodes
- `cast sig "transfer(address,uint256)"` — Compute the 4-byte function selector from a signature
- `cast 4byte 0xa9059cbb` — Reverse-lookup a selector to its function signature

---

**Navigation:** [← Module 3: Storage Deep Dive](3-storage.md) | [Module 5: External Calls →](5-external-calls.md)
