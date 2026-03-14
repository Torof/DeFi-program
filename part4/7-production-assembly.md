# Part 4 — Module 7: Reading Production Assembly

> **Difficulty:** Intermediate-Advanced
>
> **Estimated reading time:** ~30 minutes | **Exercises:** ~2-3 hours

---

## 📚 Table of Contents

**A Reading Methodology**
- [The Systematic Approach](#reading-methodology)
- [The Audit Lens](#audit-lens)
- [Build Exercise: AssemblyReader](#exercise1)

**Guided Walkthroughs**
- [Walkthrough — Uniswap V3 FullMath](#walkthrough-fullmath)
- [Walkthrough — Solady sqrt() and log2()](#walkthrough-sqrt-log2)
- [Walkthrough — Solady ERC20 Transfer](#walkthrough-erc20)
- [Other Precompiles](#other-precompiles)
- [Build Exercise: AssemblyAuditor](#exercise2)

---

## 💡 A Reading Methodology

Modules 1-6 gave you the pieces: how memory is laid out ([M2](2-memory-calldata.md)), how storage slots are computed ([M3](3-storage.md)), how dispatch works ([M4](4-control-flow.md)), how external calls are built ([M5](5-external-calls.md)), and what optimization tricks look like ([M6](6-gas-optimization.md)). Each module included a "How to Study" section for its specific pattern type. M7 pulls those together into one unified approach, then puts it to work on real code you haven't seen analyzed yet.

The goal isn't to memorize these specific codebases. It's to build the confidence to open *any* assembly-heavy contract and understand what it does — whether you're reviewing a PR, auditing a protocol, or studying a new library.

<a id="reading-methodology"></a>
### 💡 Concept: The Systematic Approach

**Why this matters:** Production assembly can be 200+ lines of dense Yul with no comments. Without a systematic approach, you'll stare at `mstore` and `sload` instructions and lose the thread. With one, you can break any assembly block into understandable pieces.

**The 5-step method:**

**Step 1 — Identify the pattern type.** Before reading any opcodes, ask: what *kind* of assembly is this? The answer tells you which mental model to reach for.

| Pattern Type | Signals | Reach For |
|---|---|---|
| Memory-heavy | `mstore`, `mload`, `keccak256`, FMP manipulation | Memory layout diagram ([M2](2-memory-calldata.md#memory-layout)) |
| Storage-heavy | `sload`, `sstore`, `shr`/`shl` on stored values | Storage slot computation, packing diagrams ([M3](3-storage.md#slot-computation)) |
| Dispatch-heavy | `calldataload(0)`, selector comparison, `JUMP` | Selector matching, dispatch pattern ([M4](4-control-flow.md#dispatch-problem)) |
| Call-heavy | `call`, `staticcall`, `delegatecall`, return data handling | Call lifecycle, return value checks ([M5](5-external-calls.md#call-lifecycle)) |
| Optimization-heavy | `returndatasize()` as zero, branchless patterns, scratch space | Solady playbook tricks ([M6](6-gas-optimization.md#branchless)) |

Most production assembly combines 2-3 of these. A Solady `safeTransfer` is call-heavy + memory-heavy + optimization-heavy. An Aave storage getter is storage-heavy + optimization-heavy. Identifying the dominant pattern narrows your focus.

**Step 2 — Read the interface first.** Look at the function signature, NatSpec, and return types *before* reading any assembly. Understanding what goes in and what comes out gives you the frame.

```solidity
// Before diving into the assembly, you already know:
//   - Input: an address and a uint256 (token transfer parameters)
//   - Output: nothing (void) — but may revert
//   - Side effects: must modify token balances
function safeTransfer(address token, address to, uint256 amount) internal {
    assembly {
        // ... 30 lines of assembly become much less intimidating
        // when you already know what they're trying to accomplish
    }
}
```

**Step 3 — Draw the data layout.** Based on the pattern type from Step 1, sketch the relevant layout:

- **Memory-heavy:** Draw a memory map — what's at 0x00, 0x20, 0x40, FMP, and beyond. Track every `mstore` and `mload`.
- **Storage-heavy:** Use `forge inspect ContractName storageLayout` to see which variables live at which slots. For mappings, compute the slot with `keccak256(abi.encode(key, baseSlot))`.
- **Calldata-heavy:** Map out the ABI encoding — selector at bytes 0-3, first arg at bytes 4-35, etc.

```
Example memory map for a safeTransfer assembly block:

Offset    Content              Purpose
──────    ──────────────────   ─────────────────────
0x00      selector (4 bytes)   transfer(address,uint256)
0x04      recipient address    argument 1
0x24      amount               argument 2
0x00      return value         overwritten by call output
```

This map is your reference as you trace through the opcodes. Every `mstore(0x04, to)` now means "write the recipient into the calldata layout."

**Step 4 — Trace one execution path.** Don't try to understand every branch at once. Pick the happy path (the most common execution) and follow it opcode by opcode. Mark values on your data layout as you go.

For a `safeTransfer`, the happy path is: encode calldata → `call()` succeeds → return data is `true` → done. Only after understanding this path should you look at error handling, edge cases, and fallbacks.

**Step 5 — Identify the tricks.** Now that you understand *what* the code does, ask *why* it does it that way. This is where M6's playbook comes in:

- Why `returndatasize()` instead of `push 0`? → Free zero trick ([M6](6-gas-optimization.md#free-zero))
- Why `xor` + `mul` instead of an `if` statement? → Branchless pattern ([M6](6-gas-optimization.md#branchless))
- Why writing at `0x00` instead of allocating from FMP? → Scratch space / dirty memory ([M6](6-gas-optimization.md#memory-tricks))
- Why `revert(0x1c, 0x04)` instead of `revert(0x00, 0x04)`? → Selector-only revert trick ([M2](2-memory-calldata.md#offset-explained))

The tricks are the *style* layer on top of the *logic* layer. Separate them mentally — first understand the logic, then appreciate the optimizations.

**Quick reference — the "How to Study" sections from M1-M6:**

| Module | Reading Strategy | Best For |
|---|---|---|
| [M1](1-evm-fundamentals.md#how-to-study) | evm.codes, Remix debugger, `forge inspect`, Dedaub | Raw bytecode, opcode-level analysis |
| [M2](2-memory-calldata.md#how-to-study) | Draw memory layout, track FMP, follow calldata flow | SafeTransferLib, ABI encoding, error handling |
| [M3](3-storage.md#how-to-study) | `forge inspect storageLayout`, trace mapping formulas, draw packing diagrams | Aave ReserveData, bitmap configs, proxy slots |
| [M4](4-control-flow.md#how-to-study) | `cast disassemble`, count selectors, trace one call end-to-end | ERC20 dispatch, proxy forwarding, Huff contracts |
| [M5](5-external-calls.md#how-to-study) | Start with simplest function, compare implementations | SafeTransferLib, Proxy.sol, Multicall |
| [M6](6-gas-optimization.md#how-to-study) | Build up from simple patterns (min → abs → mulDiv) | FixedPointMathLib, branchless math |

#### 🔗 DeFi Pattern Connection

**Where systematic reading matters most:**

1. **Audit reviews** — Security firms read every assembly block in scope. A systematic approach prevents missing subtle bugs hidden in dense Yul.

2. **Protocol integration** — Before integrating with a protocol (calling their contracts from yours), you need to understand their assembly-level behavior: what reverts look like, what return data to expect, what gas they consume.

3. **Incident response** — When an exploit happens, the first step is reading the vulnerable assembly to understand the attack vector. Speed matters; methodology beats staring.

<a id="audit-lens"></a>
### 💡 Concept: The Audit Lens

**Why this matters:** Reading assembly to *understand* it is Step 1. Reading assembly to *find bugs* is Step 2 — and it's what gets you hired at audit firms and security-focused protocol teams.

Here's the checklist. Each item is a specific thing to look for when reviewing assembly with security in mind:

**1. Unchecked call return values**
The `call()` opcode returns 0 on failure, 1 on success. If the return value is `pop()`'d or ignored, a failed external call is silently swallowed. This is the most common assembly bug.
```solidity
// BUG: ignoring whether the call succeeded
pop(call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20))

// CORRECT: check and revert
if iszero(call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)) { revert(0, 0) }
```
See: [M5 — The Call Lifecycle](5-external-calls.md#call-lifecycle)

**2. Missing return data validation**
Even when `call()` returns 1 (didn't revert), the called function might return `false`. Tokens like USDT return nothing; others return a bool. The `and(success, or(iszero(returndatasize()), eq(mload(0x00), 1)))` pattern from SafeTransferLib handles both.
See: [M5 — The SafeERC20 Pattern](5-external-calls.md#safe-erc20)

**3. Dirty memory corruption**
Writing past the free memory pointer is safe *only* if no Solidity code allocates memory afterward. If assembly writes at `mload(0x40)` without advancing the FMP, and the function continues in Solidity (e.g., creating a dynamic array), the new allocation overwrites the assembly's data.
See: [M6 — Memory Tricks](6-gas-optimization.md#memory-tricks)

**4. Off-by-one in shift amounts**
When reading packed storage, `shr(128, data)` and `shr(127, data)` produce very different results. A single-bit error in the shift amount reads the wrong field — and the values might *look* plausible, making the bug hard to catch without edge-case testing.
See: [M3 — Storage Packing](3-storage.md#manual-packing)

**5. Incorrect ABI encoding lengths**
The `call(gas, addr, value, inputOffset, inputSize, outputOffset, outputSize)` opcode requires exact byte counts. An `inputSize` of `0x44` (68 bytes) is correct for `transfer(address,uint256)` — selector (4) + address (32) + uint256 (32). Using `0x40` (64 bytes) silently truncates the last argument.

**6. Returndata confusion after calls**
Using `returndatasize()` as a free zero push only works *before* any external call. After a call, `returndatasize()` reflects the callee's return data. Code that uses `returndatasize()` as zero after a call that returned data will silently misbehave.
See: [M6 — Free Zero Tricks](6-gas-optimization.md#free-zero)

**7. Missing overflow checks in unchecked arithmetic**
Assembly arithmetic is always unchecked. `add(a, b)` wraps silently on overflow. Any arithmetic on user-supplied values needs explicit overflow checking — either `lt(result, a)` for addition or the `mul(div(x,y),y) != x` trick for multiplication.

**8. Reentrancy through unprotected callbacks**
Assembly-level external calls (`call`, `delegatecall`) transfer execution to untrusted code. If storage state hasn't been updated before the call, the classic reentrancy vector applies. Assembly doesn't have Solidity's modifier sugar — the check-effects-interactions pattern must be followed manually.

**9. Gas griefing via unbounded returndata**
A malicious callee can return megabytes of data, forcing the caller to pay for memory expansion. The `returndatasize()` value after an untrusted call should be bounded before any `returndatacopy`.
See: [M5 — The Returnbomb Attack](5-external-calls.md#returnbomb)

#### 💼 Job Market Context

**"What do you look for when auditing inline assembly?"**

- Good answer: "Unchecked return values, missing overflow checks, and dirty memory assumptions."
- Great answer: "I use a checklist: return value checks on all external calls, return data validation for non-standard tokens, shift amount correctness for packed storage, memory safety when Solidity code follows the assembly block, and gas griefing vectors from unbounded returndata. I trace one execution path first to understand the logic, then check each branch against these patterns."

---

<a id="exercise1"></a>
## 🎯 Build Exercise: AssemblyReader

**Workspace:** [AssemblyReader.sol](../workspace/src/part4/module7/exercise1-assembly-reader/AssemblyReader.sol) | [Tests](../workspace/test/part4/module7/exercise1-assembly-reader/AssemblyReader.t.sol)

**The challenge:** Three fully-implemented assembly functions with no comments. Your job is to read each one, understand what it does, and prove your understanding by writing a pure Solidity equivalent that produces the same output.

**What you'll practice:**
- Reading packed storage access (M3 skills)
- Reading branchless math patterns (M6 skills)
- Reading custom calldata decoding (M2 skills)

**3 TODOs** — implement `solveA()`, `solveB()`, and `solveC()` in Solidity. Tests compare your output against the assembly version for various inputs including edge cases.

**🎯 Goal:** Build the habit of translating assembly back to Solidity. If you can write a Solidity function that matches the assembly output for all inputs, you truly understand the assembly.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module7/exercise1-assembly-reader/*"
```

---

## 📋 Key Takeaways: A Reading Methodology

After this section, you should be able to:

- Apply a 5-step reading methodology to any assembly block: identify the pattern type, read the interface, draw the data layout, trace one path, identify the tricks
- Choose the right "How to Study" strategy from M1-M6 based on the assembly pattern (memory-heavy, storage-heavy, dispatch-heavy, call-heavy, optimization-heavy)
- Scan assembly for the 9 most common bug classes: unchecked return values, missing return data validation, dirty memory, shift off-by-ones, encoding length errors, returndata confusion, unchecked overflow, reentrancy, and gas griefing

<details>
<summary>Check your understanding</summary>

- **5-step reading methodology**: (1) Identify the pattern type (memory-heavy, storage-heavy, call-heavy, etc.) to pick the right mental model. (2) Read the interface (signature, NatSpec, return types) before any opcodes. (3) Draw the data layout (memory, storage, or calldata). (4) Trace one execution path end-to-end. (5) Identify optimization tricks used (PUSH0, branchless, scratch space).
- **Module-specific study strategies**: Each M1-M6 module has a "How to Study" section tuned to its pattern type — M2 for memory layouts, M3 for storage slot computation, M4 for dispatch tracing, M5 for call lifecycle, M6 for opcode tricks. Choose the strategy that matches the dominant pattern in the assembly you're reading.
- **9 common assembly bug classes**: The most critical are unchecked call return values (silent failure), missing return data validation (non-standard tokens like USDT), and dirty memory corruption (writing past FMP without advancing it when Solidity code follows). Each maps to a specific module's content and has a known defensive pattern.

</details>

---

## 💡 Guided Walkthroughs

The methodology from the previous section is abstract until you see it in action. This section applies all 5 steps to three production codebases — Uniswap V3's `FullMath`, Solady's `FixedPointMathLib`, and Solady's `ERC20`. Each walkthrough demonstrates the approach, not just the code.

After these walkthroughs, you'll have seen the methodology applied to arithmetic-heavy, algorithm-heavy, and application-heavy assembly. The exercises then ask you to apply it yourself.

---

<a id="walkthrough-fullmath"></a>
### 💡 Walkthrough: Uniswap V3 FullMath

**Why this file:** `FullMath.mulDiv` has been mentioned across [M1](1-evm-fundamentals.md), [M2](2-memory-calldata.md), and [M6](6-gas-optimization.md) but never fully walked through. It's the most referenced piece of DeFi assembly — every protocol that computes `a * b / denominator` without intermediate overflow either uses it directly or reimplements the same trick.

> **Source:** [Uniswap V3 FullMath.sol](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol)

**Step 1 — Identify the pattern:** Arithmetic-heavy. The assembly uses `mul`, `mulmod`, `div`, `sub`, `lt` — no `sload`, no `call`, no `mstore` beyond local variables. This is pure computation on the stack.

**Step 2 — Read the interface:**

```solidity
function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result)
```

Computes `(a * b) / denominator` with full 512-bit precision on the intermediate product. No overflow, no precision loss, deterministic rounding (down). This is the foundation of fee calculations, price conversions, and liquidity math.

**Step 3 — Draw the data layout:** No memory or storage — everything lives on the stack. The key data structure is a 512-bit number represented as two `uint256` variables:

```
┌───────────────────────────────┬───────────────────────────────┐
│          prod1 (high)         │          prod0 (low)          │
│      upper 256 bits           │       lower 256 bits          │
└───────────────────────────────┴───────────────────────────────┘
                     512-bit product = a × b
```

**Step 4 — Trace the happy path:**

The core trick — computing `a * b` as a 512-bit number:

```solidity
assembly {
    // mulmod gives (a * b) mod (2^256 - 1) — NOT mod 2^256
    // mul gives (a * b) mod 2^256 — the lower 256 bits
    let mm := mulmod(a, b, not(0))    // mm = (a*b) mod (2^256 - 1)
    prod0 := mul(a, b)                // prod0 = (a*b) mod 2^256

    // The difference tells us the upper 256 bits
    prod1 := sub(sub(mm, prod0), lt(mm, prod0))
}
```

**Why this works — the two-`mod` trick:**

The EVM has two multiplication opcodes that keep different remainders:
- `mul(a, b)` computes `a × b mod 2^256` — the standard wraparound. This gives us `prod0`, the lower 256 bits.
- `mulmod(a, b, not(0))` computes `a × b mod (2^256 - 1)`. This is almost the same as `prod0` but differs by exactly `prod1` (the carry/overflow) when the product exceeds 256 bits.

The subtraction `sub(mm, prod0)` gives us a value related to `prod1`, and the `lt(mm, prod0)` handles the borrow when `mm < prod0`. The result: `prod1` contains the upper 256 bits of the full product.

Think of it like this: if you multiply two 3-digit numbers and only keep the last 3 digits, you lose the carry. But if you also keep the remainder after dividing by 999, the difference between those two remainders *is* the carry. Same principle, at 256-bit scale.

**The fast path — when the product fits in 256 bits:**

```solidity
if (prod1 == 0) {
    require(denominator > 0);
    assembly {
        result := div(prod0, denominator)
    }
    return result;
}
```

If `prod1` is zero, the entire product fits in `prod0` — standard division works. This handles the majority of real-world cases (small numbers, reasonable fee rates).

**The 512-bit division path** handles the case where `prod1 > 0`. It uses number-theoretic tricks to perform the full division: first it reduces the 512-bit product modulo the denominator (removing the denominator's power-of-2 factor), then computes the denominator's *modular multiplicative inverse* — a number `inv` such that `denominator * inv ≡ 1 (mod 2^256)`. Multiplying the reduced product by this inverse gives the exact quotient. The inverse is found using Newton's method (the same convergence idea as `sqrt()`), starting from a 4-bit seed and doubling precision each step. The key insight: 512-bit division is *possible* entirely in 256-bit EVM arithmetic, and FullMath does it in constant gas.

**Step 5 — Identify the tricks:**

- `not(0)` instead of `type(uint256).max` — saves bytecode (1 opcode vs a PUSH32)
- `lt(mm, prod0)` as a borrow flag — branchless subtraction with carry
- Modular inverse computation — number theory, not branchless tricks. This is algorithm design, not gas optimization
- No memory allocation — everything on the stack. Pure stack manipulation keeps gas minimal

#### 🔗 DeFi Pattern Connection

`mulDiv` appears everywhere precise token math is needed:

- **AMM price calculations:** `amountOut = reserveOut * amountIn / (reserveIn + amountIn)` — but with full precision
- **Fee computation:** `fee = amount * feeRate / 1e6` — rounding matters when millions of dollars flow through
- **Vault share conversion:** `shares = assets * totalShares / totalAssets` — the ERC-4626 core calculation
- **Liquidity math:** Uniswap V3's concentrated liquidity formulas use `mulDiv` dozens of times per swap

Solady's `FixedPointMathLib.mulDiv` is a refined version of the same algorithm with additional gas optimizations and branchless patterns layered on top.

<a id="walkthrough-sqrt-log2"></a>
### 💡 Walkthrough: Solady sqrt() and log2()

**Why this section:** [M6](6-gas-optimization.md#how-to-study) explicitly deferred `sqrt()` and `log2()` to M7: *"Don't get stuck on the bit-manipulation in sqrt() and log2() — come back to them after M7."* Time to deliver on that promise.

> **Source:** [Solady FixedPointMathLib.sol](https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)

Both functions use the same core technique: **binary search by bit-shifting.** Instead of looping, they test progressively smaller bit ranges to narrow in on the answer — all branchless, all in constant gas.

#### sqrt() — Integer Square Root

**Step 1 — Identify the pattern:** Arithmetic-heavy, optimization-heavy. No storage, no calls. Uses `shr`, `shl`, `lt`, `add`, `div` — the signature tools of bit-level binary search.

**Step 2 — Read the interface:**

```solidity
function sqrt(uint256 x) internal pure returns (uint256 z)
```

Returns `floor(sqrt(x))` — the largest integer whose square is less than or equal to `x`.

**Step 3 — Data layout:** Pure stack. The key variables are `x` (input), `z` (running result), and intermediate comparison values.

**Step 4 — Trace the algorithm (using x = 625, expected result = 25):**

The function works in two phases:

**Phase 1 — Bit-length estimation (binary search for the initial guess):**

```solidity
assembly {
    z := 181    // starting constant (chosen for convergence properties)

    // Is x >= 2^128? If yes, work with the upper half
    let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
    // r = 128 if x > 2^128, else 0

    r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
    // After shifting x right by r bits, is it still > 2^64?
    // If yes, add 64 to r

    r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
    // Continue halving: add 32 if remaining > 2^40

    r := or(r, shl(4, lt(0xfffff, shr(r, x))))
    // Add 16 if remaining > 2^20

    z := shl(shr(1, r), z)
    // Scale z by 2^(r/2) — initial approximation of sqrt(x)
}
```

Each line asks: "Is the number bigger than this threshold?" If yes, it adds a power of 2 to the bit-length estimate `r` and shifts `x` down. After 4 tests, `r` approximates the bit-length of `x`, and `z` is scaled to be a rough initial guess for sqrt(x).

With x = 625: `625 < 2^128`, `625 < 2^64`, `625 < 2^40`, `625 < 2^20`. So `r` stays 0, and `z` remains 181.

**Phase 2 — Newton-Raphson refinement (7 fixed iterations):**

```solidity
assembly {
    z := shr(1, add(z, div(x, z)))    // iteration 1
    z := shr(1, add(z, div(x, z)))    // iteration 2
    z := shr(1, add(z, div(x, z)))    // iteration 3
    z := shr(1, add(z, div(x, z)))    // iteration 4
    z := shr(1, add(z, div(x, z)))    // iteration 5
    z := shr(1, add(z, div(x, z)))    // iteration 6
    z := shr(1, add(z, div(x, z)))    // iteration 7
}
```

Each line computes `z = (z + x/z) / 2` — the [Newton-Raphson](https://en.wikipedia.org/wiki/Newton%27s_method) formula for square roots. This converges quadratically (doubles the number of correct bits each step), so 7 iterations are enough for any 256-bit input given a reasonable initial guess.

With x = 625, z starts at 181:
- After iteration 1: `(181 + 625/181) / 2 = (181 + 3) / 2 = 92`
- After iteration 2: `(92 + 625/92) / 2 = (92 + 6) / 2 = 49`
- After iteration 3: `(49 + 625/49) / 2 = (49 + 12) / 2 = 30`
- After iteration 4: `(30 + 625/30) / 2 = (30 + 20) / 2 = 25`
- Iterations 5-7: `(25 + 625/25) / 2 = (25 + 25) / 2 = 25` — converged.

**Phase 3 — Branchless final adjustment:**

```solidity
assembly {
    z := sub(z, lt(div(x, z), z))
}
```

Newton-Raphson can overshoot by 1. This subtracts 1 from `z` if `x/z < z` (meaning `z*z > x`). The `lt()` returns 0 or 1 — branchless.

**Step 5 — Tricks spotted:**
- No loops — fixed iteration count means constant gas cost
- Branchless binary search — `shl(N, lt(threshold, x))` adds 2^N without JUMPI
- Branchless final correction — `sub(z, lt(...))` instead of `if/else`
- Unrolled Newton-Raphson — 7 copies of the same line. Looks repetitive, but eliminates loop overhead (JUMPI + JUMPDEST + counter management per iteration)

#### log2() — Integer Base-2 Logarithm

**The same binary search pattern, taken further.** Where `sqrt()` uses 4 comparison levels, `log2()` uses 8 — one for each power of 2 from 128 down to 1:

```solidity
assembly {
    // Start with the largest possible contribution: 128
    r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))

    // Each subsequent line tests the next power, working on the shifted value
    r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
    r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
    r := or(r, shl(4, lt(0xffff, shr(r, x))))
    r := or(r, shl(3, lt(0xff, shr(r, x))))
    r := or(r, shl(2, lt(0xf, shr(r, x))))
    r := or(r, shl(1, lt(0x3, shr(r, x))))
    r := or(r,         lt(0x1, shr(r, x)))
}
```

**How to read each line** — take line 3 as an example:
```
r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
```
1. `shr(r, x)` — shift `x` right by the bits we've already accounted for
2. `lt(0xffffffff, ...)` — is the remaining value > 2^32 - 1? Returns 0 or 1
3. `shl(5, ...)` — if yes, the contribution is 2^5 = 32
4. `or(r, ...)` — add this contribution to the running total

After all 8 lines, `r` contains `floor(log2(x))`. No loops, no branches, constant gas.

**Example:** `log2(256)` = `log2(2^8)` = 8.
- Line 1: `256 > 2^128`? No → +0. `r = 0`
- Line 2: `256 > 2^64`? No → +0. `r = 0`
- Line 3: `256 > 2^32`? No → +0. `r = 0`
- Line 4: `256 > 2^16`? No → +0. `r = 0`
- Line 5: `256 > 255` (0xff)? Yes → +8. `r = 8`
- Line 6: `shr(8, 256) = 1`. `1 > 15`? No → +0. `r = 8`
- Line 7: `1 > 3`? No → +0. `r = 8`
- Line 8: `1 > 1`? No → +0. `r = 8` ✓

#### 💼 Job Market Context

**"How does Solady implement sqrt()?"**

- Good answer: "Binary search for the initial guess using bit-shifting, then Newton-Raphson refinement."
- Great answer: "It uses a branchless binary search that tests 4 thresholds to estimate the bit-length, scales an initial constant by 2^(bitLength/2), then runs exactly 7 unrolled Newton-Raphson iterations. A branchless final adjustment handles off-by-one. The whole thing runs in constant gas — no loops, no JUMPI."

<a id="walkthrough-erc20"></a>
### 💡 Walkthrough: Solady ERC20 Transfer

**Why this file:** [M4](4-control-flow.md) showed a dispatch snippet from Solady's ERC20. But the *transfer flow itself* — balance lookup, underflow check, storage update, event emission — ties together M3 (storage), M5 (events), and M6 (optimization tricks) in one function. It's the complete picture.

> **Source:** [Solady ERC20.sol](https://github.com/Vectorized/solady/blob/main/src/tokens/ERC20.sol)

**Step 1 — Identify the pattern:** Storage-heavy + optimization-heavy. The function reads and writes balance slots, emits an event, and uses scratch space throughout. No external calls.

**Step 2 — Read the interface:**

```solidity
function transfer(address to, uint256 amount) public virtual returns (bool)
```

Transfers `amount` tokens from `msg.sender` to `to`. Reverts on insufficient balance. Emits `Transfer(from, to, amount)`. Returns `true`.

**Step 3 — Draw the data layout:**

Storage: balances are stored in a mapping. Each address maps to a unique storage slot computed via:
```
balanceSlot(owner) = keccak256(owner . BALANCE_SLOT_SEED)
```

Memory (scratch space — no FMP allocation):
```
Offset    Content                   Purpose
──────    ──────────────────────    ────────────────────
0x00      owner address             } hashed together to
0x20      BALANCE_SLOT_SEED         } compute balance slot
0x20      amount                    event data (overwritten)
```

The same memory region is reused for different purposes at different points in the function. This is the dirty memory pattern from [M6](6-gas-optimization.md#memory-tricks) — safe because the function ends with an assembly `return` and never allocates Solidity memory.

**Step 4 — Trace the transfer flow:**

```solidity
assembly {
    // 1. Compute sender's balance slot
    mstore(0x20, _BALANCE_SLOT_SEED)
    mstore(0x00, caller())
    let fromBalanceSlot := keccak256(0x0c, 0x20)
    let fromBalance := sload(fromBalanceSlot)

    // 2. Check sufficient balance
    if gt(amount, fromBalance) {
        mstore(0x00, 0xf4d678b8)         // InsufficientBalance selector
        revert(0x1c, 0x04)               // revert with just the selector
    }

    // 3. Update sender balance
    sstore(fromBalanceSlot, sub(fromBalance, amount))

    // 4. Compute receiver's balance slot (reuses scratch space)
    mstore(0x00, to)
    let toBalanceSlot := keccak256(0x0c, 0x20)

    // 5. Update receiver balance
    sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))

    // 6. Emit Transfer event
    mstore(0x20, amount)
    log3(
        0x20,                            // data offset (amount)
        0x20,                            // data size (32 bytes)
        _TRANSFER_EVENT_SIGNATURE,       // topic 0: event signature
        caller(),                        // topic 1: from
        shr(96, shl(96, to))            // topic 2: to (cleaned)
    )

    // 7. Return true
    mstore(0x00, 1)
    return(0x00, 0x20)
}
```

**The slot computation trick (step 1):** `mstore(0x00, caller())` writes the 20-byte address right-aligned at offset 0x00 (bytes 12-31). `mstore(0x20, _BALANCE_SLOT_SEED)` writes the seed at offset 0x20. `keccak256(0x0c, 0x20)` then hashes 32 bytes starting at byte 12 — the 20-byte address (bytes 12-31) followed by the high 12 bytes of the seed word at offset 0x20 (bytes 32-43). Together these 32 bytes form a unique key for the balance mapping. This is a compact mapping slot computation using overlapping memory writes.

**The error trick (step 2):** `revert(0x1c, 0x04)` — not `revert(0x00, 0x04)`. The selector was written at offset 0x00 as a full 32-byte word (left-padded). The actual 4-byte selector sits at bytes 28-31 (0x1c-0x1f). Reverting from 0x1c with length 4 sends exactly the selector. This is the same pattern covered in [M2](2-memory-calldata.md#offset-explained).

**The address cleaning trick (step 6):** `shr(96, shl(96, to))` — shifts left 96 bits (clearing the top 96 bits) then shifts right 96 bits (moving back). This masks the address to exactly 20 bytes, discarding any dirty upper bits. The `log3` opcode expects clean 32-byte topics.

**Step 5 — Tricks spotted:**

| Line | Trick | From |
|------|-------|------|
| `keccak256(0x0c, 0x20)` | Overlapping scratch space writes | M2, M3 |
| `revert(0x1c, 0x04)` | Selector-only revert from 32-byte word | M2 |
| No `mload(0x40)` anywhere | Entire function uses scratch space only | M6 |
| `return(0x00, 0x20)` at the end | Manual return bypasses Solidity ABI encoding | M4 |
| `shr(96, shl(96, to))` | Address cleaning / masking | M1 |

#### 🔗 DeFi Pattern Connection

This exact transfer pattern (with minor variations) appears in every Solady token: ERC20, ERC721, ERC1155. The slot computation and event emission techniques are the same — only the storage layout and event signatures change. Once you can read one Solady token transfer, you can read them all.

<a id="other-precompiles"></a>
### 💡 Brief: Other Precompiles

[M5](5-external-calls.md#precompile-calls) covered `ecrecover` (precompile at address `0x01`) in depth and noted: *"Module 7 covers reading production code that uses these precompiles."* Here's the landscape beyond ecrecover.

Precompiled contracts are EVM built-ins at addresses `0x01` through `0x0a`. They perform computationally expensive operations in native code rather than EVM bytecode. All are called with `staticcall`:

```solidity
// General pattern:
let success := staticcall(gas(), PRECOMPILE_ADDR, inputPtr, inputLen, outputPtr, outputLen)
```

| Address | Name | What It Does | Where in DeFi |
|---------|------|-------------|---------------|
| `0x01` | ecrecover | Recover signer from ECDSA signature | Permit, EIP-712 (covered in [M5](5-external-calls.md#precompile-calls)) |
| `0x02` | SHA-256 | SHA-256 hash | Bitcoin SPV proofs, cross-chain bridges |
| `0x03` | RIPEMD-160 | RIPEMD-160 hash | Bitcoin address derivation in bridges |
| `0x04` | Identity | Copies input to output (memory copy) | Used internally by the compiler for `bytes` copying |
| `0x05` | ModExp | Modular exponentiation (`base^exp mod modulus`) | RSA verification, some ZK schemes |
| `0x06` | ecAdd | BN256 curve point addition | ZK proof verification |
| `0x07` | ecMul | BN256 curve scalar multiplication | ZK proof verification |
| `0x08` | ecPairing | BN256 pairing check | ZK proof verification (Tornado Cash, ZK rollups) |
| `0x09` | Blake2 | BLAKE2b compression | Zcash interoperability |
| `0x0a` | Point evaluation | KZG point evaluation (EIP-4844) | Blob verification for L2 rollups |

**When you'll encounter them:**

- **`0x02`-`0x03` (SHA-256, RIPEMD-160):** Cross-chain bridges that verify Bitcoin transactions. You'll see `staticcall(gas(), 2, ...)` in Bitcoin relay contracts.
- **`0x05` (ModExp):** Rare in DeFi. Shows up in specialized cryptographic operations. The input encoding is complex — three length-prefixed values.
- **`0x06`-`0x08` (BN256):** ZK proof verification. Tornado Cash's verifier calls `ecPairing` to verify Groth16 proofs. ZK rollup verifier contracts (zkSync, Polygon zkEVM) use all three. The calling convention involves packed point coordinates.
- **`0x0a` (Point evaluation):** Post-Dencun. Used by L2 contracts to verify blob data. You'll see this in rollup settlement contracts.

You don't need to memorize the input formats — they're well-documented in the [EVM precompiles reference](https://www.evm.codes/precompiled). The important thing is to *recognize* a precompile call when you see one: any `staticcall` to an address between `0x01` and `0x0a` is a precompile, not a contract.

---

<a id="exercise2"></a>
## 🎯 Build Exercise: AssemblyAuditor

**Workspace:** [AssemblyAuditor.sol](../workspace/src/part4/module7/exercise2-assembly-auditor/AssemblyAuditor.sol) | [Tests](../workspace/test/part4/module7/exercise2-assembly-auditor/AssemblyAuditor.t.sol)

**The challenge:** Three assembly functions, each containing a subtle bug from the audit checklist. Your job is to find each bug and implement the fixed version.

**What you'll practice:**
- Spotting unchecked call return values (audit item #1)
- Catching off-by-one errors in bit shifts (audit item #4)
- Identifying dirty memory / FMP corruption (audit item #3)

**3 TODOs** — implement `fixedApprove()`, `fixedUnpack()`, and `fixedCache()`. Tests verify your fixes produce correct behavior. Bonus: the tests also demonstrate the bugs — read the buggy function tests to see exactly how each vulnerability manifests.

**🎯 Goal:** Train your audit instincts. After this exercise, you should be able to spot these three bug classes (unchecked return values, shift off-by-ones, dirty memory) on sight in any assembly review.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module7/exercise2-assembly-auditor/*"
```

---

## 📋 Key Takeaways: Guided Walkthroughs

After this section, you should be able to:

- Walk through FullMath's 512-bit multiplication trick and explain why two different `mod` operations recover the upper 256 bits
- Trace Solady's binary search pattern for `sqrt()` and `log2()` — branchless bit-shifting that replaces loops with unrolled comparisons
- Read a complete Solady ERC20 transfer and identify each trick: scratch space slot computation, selector-only revert, address cleaning, manual return
- Recognize precompile calls (`staticcall` to addresses `0x01`-`0x0a`) and know which DeFi patterns use which precompiles

<details>
<summary>Check your understanding</summary>

- **FullMath 512-bit multiplication**: `mul(a, b)` computes `(a * b) mod 2^256`, giving the lower 256 bits (`prod0`). `mulmod(a, b, not(0))` computes `(a * b) mod (2^256 - 1)` — a slightly different remainder. The difference between these two values, with a borrow correction, recovers the upper 256 bits (`prod1`). Together they represent the full 512-bit product, enabling `mulDiv` without intermediate overflow — critical for fixed-point math in AMMs and vaults.
- **Solady binary search for sqrt/log2**: Instead of a loop, Solady unrolls the binary search into fixed steps, each using a branchless bit-shift: compare against a threshold, shift the result, repeat. This eliminates loop overhead and branch mispredictions, computing sqrt in ~9 steps and log2 in ~8 steps.
- **Solady ERC20 transfer tricks**: Uses scratch space (0x00-0x3f) instead of allocating memory for slot computation, emits events with selector-only revert on failure (no string errors), cleans addresses with `and(addr, 0xffffffffffffffffffffffffffffffffffffffff)`, and manually writes return data — all avoiding compiler overhead.
- **Precompile calls**: `staticcall` to addresses 0x01-0x0a invokes EVM precompiles. DeFi uses ecrecover (0x01) for permit signatures, SHA-256 (0x02) for Bitcoin SPV proofs, modexp (0x05) for RSA verification, and the bn128 curve precompiles (0x06-0x08) for ZK proof verification.

</details>

---

## 📚 Resources

**Production Code (read alongside the walkthroughs):**
- [Uniswap V3 FullMath.sol](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol) — 512-bit mulDiv
- [Solady FixedPointMathLib.sol](https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol) — sqrt, log2, mulDiv, and more
- [Solady ERC20.sol](https://github.com/Vectorized/solady/blob/main/src/tokens/ERC20.sol) — full assembly token implementation

**Reading Tools:**
- [evm.codes](https://www.evm.codes/) — Opcode reference with gas costs and stack effects
- [Dedaub](https://app.dedaub.com/) — Decompiler for deployed contracts
- `forge inspect ContractName asm` — View compiler-generated assembly
- `cast disassemble` — Disassemble raw bytecode

**Precompile Reference:**
- [EVM precompiles (evm.codes)](https://www.evm.codes/precompiled) — Input/output formats for all precompiles
- [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) — Point evaluation precompile specification

---

**Navigation:** [← Module 6: Gas Optimization Patterns](6-gas-optimization.md) | [Module 8: Pure Yul Contracts →](8-pure-yul.md)
