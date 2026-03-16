# Part 4 — Module 6: Gas Optimization Patterns

> **Difficulty:** Intermediate-Advanced
>
> **Estimated reading time:** ~50 minutes | **Exercises:** ~2-3 hours

---

## 📚 Table of Contents

**Measuring Before Optimizing**
- [Gas Profiling with Foundry](#gas-profiling)
- [Reading Compiler Output](#compiler-output)
- [Optimizer Settings](#optimizer-settings)
- [Build Exercise: GasBenchmark](#exercise1)

**The Solady Playbook — Opcode Tricks**
- [Free Zero Tricks](#free-zero)
- [Branchless Patterns](#branchless)
- [Memory Tricks](#memory-tricks)
- [Arithmetic Shortcuts](#arithmetic-shortcuts)
- [Build Exercise: SoladyTricks](#exercise2)

**Dispatch Optimization**
- [Recap — From Linear to Binary](#dispatch-recap)
- [Jump Table Dispatch — O(1)](#jump-table)
- [Function Selector Ordering](#selector-ordering)
- [Build Exercise: JumpDispatcher](#exercise3)

**The Optimization Decision Framework**
- [When Assembly Is Worth It](#when-worth-it)
- [Architectural Wins That Dwarf Opcode Tricks](#architectural-wins)
- [Deployment Optimization](#deployment-optimization)

---

## 💡 Measuring Before Optimizing

Modules 1-5 gave you the gas cost model ([M1](1-evm-fundamentals.md#gas-costs)), warm/cold access patterns ([M1](1-evm-fundamentals.md#warm-cold)), storage economics ([M3](3-storage.md#sstore-cost-machine)), and memory expansion costs ([M1](1-evm-fundamentals.md#memory-expansion)). You know *what* costs gas. M6 teaches *how* to find where gas is wasted, *which* tricks make it faster, and *when* the effort is worth it.

The first rule of optimization: **measure before you optimize.** The second rule: **measure after you optimize.** Intuition about gas costs is often wrong — the EVM's pricing model has enough quirks (warm/cold access, memory quadratic scaling, refund caps) that only measurement tells the truth.

<a id="gas-profiling"></a>
### 💡 Concept: Gas Profiling with Foundry

**Why this matters:** You can't optimize what you can't measure. Every protocol team profiles gas costs before and after changes. An engineer who says "I optimized this function" without numbers is guessing.

**Tool 1: `forge test --gas-report`**

The gas report shows every external function call made during tests, grouped by contract:

```
┌──────────────────────┬─────────────────┬────────┬────────┬────────┬─────────┐
│ MyToken contract     ┆                 ┆        ┆        ┆        ┆         │
╞══════════════════════╪═════════════════╪════════╪════════╪════════╪═════════╡
│ Function Name        ┆ min             ┆ avg    ┆ median ┆ max    ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ transfer             ┆ 29,484          ┆ 34,291 ┆ 34,291 ┆ 51,384 ┆ 200     │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ approve              ┆ 24,362          ┆ 24,362 ┆ 24,362 ┆ 46,262 ┆ 50      │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ balanceOf            ┆ 561             ┆ 561    ┆ 561    ┆ 2,561  ┆ 300     │
└──────────────────────┴─────────────────┴────────┴────────┴────────┴─────────┘
```

**How to read it:**

- **min vs max:** The gap tells you about cold vs warm access. `transfer` shows min=29,484 (warm storage) vs max=51,384 (cold storage — first access costs ~22,000 more due to the zero-to-nonzero SSTORE). `balanceOf` shows 561 (warm SLOAD) vs 2,561 (cold SLOAD — the 2,000 gap matches EIP-2929's cold surcharge).
- **avg vs median:** If they differ significantly, you have outlier cases (cold access, edge cases with different code paths).
- **# calls:** High call count = hot path. `balanceOf` at 300 calls is the optimization target — saving 100 gas there saves 30,000 total.

**Tool 2: `forge snapshot` — tracking gas across commits**

```bash
# Save a gas baseline
forge snapshot

# Make your optimization changes, then compare
forge snapshot --diff
```

This outputs a diff showing which tests got cheaper or more expensive. Use it to verify that your "optimization" actually optimized.

**Tool 3: `gasleft()` for micro-benchmarking**

When you need to measure a specific operation, not an entire function:

```solidity
function test_measureTransferGas() public {
    uint256 gasBefore = gasleft();
    token.transfer(alice, 100e18);
    uint256 gasUsed = gasBefore - gasleft();

    // Now you have the exact gas cost of this specific call
    emit log_named_uint("transfer gas", gasUsed);
}
```

In assembly, `gasleft()` is just the `gas()` opcode:

```solidity
assembly {
    let before := gas()
    // ... operation to measure ...
    let used := sub(before, gas())
}
```

#### ⚠️ Measurement Overhead

The `gas()` opcode itself costs 2 gas, and the `sub` costs 3. So your measurement includes ~5 gas of overhead. For micro-benchmarks (measuring single opcodes), this matters. For function-level benchmarks, it's negligible.

💻 **Quick Try:**

Run this on one of your Module 5 exercise tests:
```bash
forge test --match-contract SafeCallerTest --gas-report
```
Find the most expensive function. Is the min-max gap large? That gap is warm/cold access — the exact pattern [Module 1](1-evm-fundamentals.md#warm-cold) explained.

#### ⚠️ Common Mistake: Optimizing Cold Paths

A constructor runs once. A `setFee()` admin function runs maybe 10 times in a contract's lifetime. A `transfer()` runs millions of times. The gas report's `# calls` column tells you where to focus. Spending a week optimizing a constructor is almost always wasted effort.

---

<a id="compiler-output"></a>
### 💡 Concept: Reading Compiler Output

**Why this matters:** Before writing assembly, check what the compiler already generates. Sometimes the optimizer already does what you'd write by hand. Other times, it generates surprisingly wasteful code — and knowing where those gaps are tells you exactly where assembly pays off.

**`forge inspect` — your compiler X-ray:**

```bash
# See the optimized Yul IR (most readable)
forge inspect MyContract ir-optimized

# See the final EVM assembly (opcodes)
forge inspect MyContract asm

# See the deployed bytecode (raw hex)
forge inspect MyContract bytecode
```

**What to look for in `ir-optimized`:**

The Yul IR shows you what the optimizer actually produces. Compare it to what you'd write by hand:

```
// Solidity:
function getBalance(address user) external view returns (uint256) {
    return balances[user];
}

// Compiler generates (simplified ir-optimized):
//   1. ABI-decode the address from calldata
//   2. Compute mapping slot: keccak256(abi.encode(user, slot))
//   3. SLOAD the slot
//   4. ABI-encode and return the uint256

// Your hand-written assembly would do the same 4 steps.
// No savings here — the compiler wins.
```

But for something like SafeERC20 `transfer`:

```
// Compiler generates for: require(token.transfer(to, amount))
//   1. Allocate memory at FMP
//   2. Bump FMP
//   3. Write selector + args to allocated memory
//   4. CALL
//   5. Check returndatasize >= 32
//   6. ABI-decode the bool
//   7. Require it's true
//   8. Revert with Error(string) if false — stores full string in bytecode

// Solady's hand-written assembly:
//   1. Write selector + args to scratch space (0x00)
//   2. CALL
//   3. and(ok, or(iszero(rds), eq(mload(0), 1)))
//   4. Revert with 4-byte custom error if false
```

The compiler version: 7 steps, memory allocation, string in bytecode. Solady's version: 4 steps, scratch space, 4-byte error. That's where assembly wins — the compound optimization of scratch space + custom errors + the `or(iszero(rds), ...)` trick is something the compiler can't synthesize from Solidity source.

**When to bother reading compiler output:**

- Before writing assembly for a function — check if the compiler already generates tight code
- When profiling shows unexpected gas costs — the compiler might be adding checks you don't need
- During audits — verify that optimizer settings produce the expected code

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How do you verify that your assembly is actually faster than Solidity?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "I use `forge test --gas-report` and `forge snapshot --diff` to measure before and after."
   - Great answer: "I also check `forge inspect` IR output to see what the compiler already optimizes, so I only write assembly where it actually helps. Sometimes the compiler's output is already optimal."

   </details>

**Interview Red Flags:**
- 🚩 Writing assembly without measuring — "I assumed it was faster"
- 🚩 Not knowing `forge inspect` exists

**Pro tip:** In code reviews, link to gas snapshots showing the improvement. "This assembly saves 2,100 gas per call" with a snapshot diff is more convincing than "assembly is faster."

---

<a id="optimizer-settings"></a>
### 💡 Concept: Optimizer Settings

**Why this matters:** The `solc` optimizer is the single highest-leverage optimization tool — it affects every function in your contract with zero code changes. Choosing the right settings can save more gas than hand-written assembly.

**The `runs` parameter:**

The optimizer has one key tuning knob: `runs`. This tells the compiler how many times you expect each function to be called:

| Setting | Optimizes for | Best when |
|---------|--------------|-----------|
| `runs = 200` (default) | Smaller bytecode → cheaper deployment | Factory patterns (deploy many instances), one-off contracts |
| `runs = 1,000,000` | Faster runtime → cheaper function calls | Router contracts, tokens, pools — anything called millions of times |

```toml
# foundry.toml
[profile.default]
optimizer = true
optimizer_runs = 200         # default — small bytecode
# optimizer_runs = 1000000   # for hot contracts
```

**What changes between low and high runs:**

With low runs, the compiler favors code reuse (shared helper functions, shorter bytecode). With high runs, it favors inlining (duplicates code to avoid JUMP overhead, unrolls small loops). The difference can be 5-15% on runtime gas for complex contracts.

**The via-IR pipeline:**

```toml
[profile.default]
via_ir = true   # Enable the Yul-based optimizer pipeline
```

The standard optimizer works on the EVM assembly directly. The via-IR pipeline compiles Solidity → Yul IR → optimized Yul → EVM bytecode, which enables:

- **Cross-function optimization:** The optimizer can see through function boundaries and eliminate redundant operations across calls
- **Better stack management:** Fewer "stack too deep" errors, smarter register allocation
- **More aggressive inlining:** Can inline across complex call chains

**Trade-offs:**

| | Standard optimizer | via-IR |
|---|---|---|
| Compile time | Fast | 2-10x slower |
| Stack management | Basic | Advanced (fewer stack-too-deep) |
| Cross-function optimization | Limited | Full |
| Maturity | Battle-tested since 2017 | Stable since ~2023, still improving |

**Practical guidance:**

1. Start with `optimizer = true`, `runs = 200` (the default)
2. Profile with `forge test --gas-report`
3. If runtime gas matters more than deployment, increase `runs` to 1,000,000 and re-profile
4. If you hit stack-too-deep or want maximum optimization, enable `via_ir = true` and re-profile
5. **Always measure both.** Don't assume higher runs or via-IR is universally better — it depends on your contract's structure

💻 **Quick Try:**

```bash
# Profile with default settings
forge test --gas-report > gas_default.txt

# Change optimizer_runs in foundry.toml to 1000000, then:
forge test --gas-report > gas_high_runs.txt

# Compare the two reports — which functions got cheaper?
diff gas_default.txt gas_high_runs.txt
```

#### 🔗 DeFi Pattern Connection

**Where optimizer settings matter in DeFi:**

1. **Uniswap:** Uses high optimizer runs for the core Pool contract (called millions of times) but default runs for peripheral/helper contracts
2. **Factory patterns:** Aave deploys many pool instances via CREATE2 — lower runs keeps deployment gas reasonable
3. **Proxy patterns:** The implementation contract's deployment cost is paid once (low runs is fine), but every delegatecall pays the runtime cost (high runs for the implementation)

---

<a id="exercise1"></a>
## 🎯 Build Exercise: GasBenchmark

**Workspace:** [`GasBenchmark.sol`](../workspace/src/part4/module6/exercise1-gas-benchmark/GasBenchmark.sol)
**Tests:** [`GasBenchmark.t.sol`](../workspace/test/part4/module6/exercise1-gas-benchmark/GasBenchmark.t.sol)

Practice gas measurement techniques. You'll use assembly `gas()` to measure specific operations and compare implementations.

**3 TODOs:**
1. `measureTransferGas()` — measure the gas cost of a token transfer using assembly `gas()` deltas
2. `compareImplementations()` — call two implementations of the same logic, return which is cheaper
3. `sumPrices()` — sum a storage array with cached length (storage caching optimization)

**🎯 Goal:** Learn to measure, compare, and apply the most impactful optimization (storage caching) — the skills from Topic Block 1.

---

## 📋 Key Takeaways: Measuring Before Optimizing

After this section, you should be able to:

- Run `forge test --gas-report` to identify hot functions and use `forge snapshot --diff` to track gas changes across commits
- Read compiler output with `forge inspect ContractName ir-optimized` and identify wasteful patterns the optimizer missed
- Choose optimizer settings based on contract usage: low `runs` for factory-deployed clones, high `runs` for frequently-called routers, and explain what `via_ir` enables
- Apply the hot-path rule: focus optimization effort on functions called millions of times, not setup or admin functions

<details>
<summary>Check your understanding</summary>

- **Gas profiling with Foundry**: `forge test --gas-report` shows per-function gas costs across all tests; `forge snapshot --diff` tracks gas changes between commits. These are the only reliable way to know where gas is actually spent — intuition is often wrong due to warm/cold access quirks and memory expansion costs.
- **Reading compiler output**: `forge inspect ContractName ir-optimized` shows the Yul IR the optimizer produces, letting you spot patterns it missed (redundant SLOADs, unnecessary checks). This is how you find optimization targets the compiler can't fix.
- **Optimizer settings**: Low `runs` optimizes for deployment cost (good for factory-deployed clones), high `runs` optimizes for runtime cost (good for frequently-called routers). `via_ir` enables cross-function optimization but increases compile time.
- **Hot-path rule**: Functions called millions of times (swaps, transfers) are the only ones worth optimizing aggressively. Admin functions, constructors, and setup code are called rarely — optimizing them wastes engineering time for negligible savings.

</details>

---

## 💡 The Solady Playbook — Opcode Tricks

Modules 1-5 taught the fundamental gas costs: SSTORE is expensive ([M3](3-storage.md#sstore-cost-machine)), memory expansion is quadratic ([M1](1-evm-fundamentals.md#memory-expansion)), scratch space avoids FMP overhead ([M2](2-memory-calldata.md#scratch-space)). Those are the *rules*. This section teaches the *moves* — specific opcode-level tricks that production libraries like [Solady](https://github.com/vectorized/solady) use to squeeze out every last gas unit. These are the tricks that make Solady's SafeTransferLib, FixedPointMathLib, and MerkleProofLib faster than anything the compiler generates from Solidity.

<a id="free-zero"></a>
### 💡 Concept: Free Zero Tricks

**Why this matters:** Pushing zero onto the stack is one of the most common EVM operations — function arguments default to zero, memory is initialized to zero, many comparisons check against zero. Two opcodes produce zero, and they cost different amounts.

**PUSH0 (EIP-3855, Shanghai upgrade):**

| Opcode | Gas | Bytecode size | Availability |
|--------|-----|---------------|-------------|
| `PUSH1 0x00` | 3 | 2 bytes | All chains |
| `PUSH0` | 2 | 1 byte | Shanghai+ (mainnet since April 2023) |

One gas and one byte doesn't sound like much. But zero is pushed *everywhere*: every function's return, every `call()` with no value, every `mstore` initializing memory. Across an entire contract, PUSH0 can save dozens of gas at runtime and hundreds at deployment (each bytecode byte costs 200 gas to deploy via code deposit).

**Solidity handles this automatically** since version 0.8.20 — it targets Shanghai and uses PUSH0. If you're writing inline assembly on a Shanghai+ chain, the compiler also emits PUSH0 for literal zeros in Yul.

**`returndatasize()` as zero — the pre-Shanghai trick:**

Before any external call has been made, the return data buffer is empty. `RETURNDATASIZE` returns 0 and costs 2 gas (same as PUSH0), but it's only 1 byte of bytecode:

```
Bytecode comparison:
  6080604052   →  PUSH1 0x80  PUSH1 0x40  MSTORE    (5 bytes, 9 gas)
  3d604052     →  RETURNDATASIZE  PUSH1 0x40  MSTORE  (4 bytes, 7 gas)
```

Solady uses `returndatasize()` as zero in constructor bytecode (where PUSH0 might not be available on all target chains) and in library code that needs to support pre-Shanghai chains.

💻 **Quick Try:**

Compile a minimal contract with `forge inspect` and search for `PUSH1 0x00` vs `PUSH0` in the assembly output:
```bash
forge inspect MyContract asm | grep -c "PUSH0"
forge inspect MyContract asm | grep -c "PUSH1 0x00"
```
On Solidity 0.8.20+, you should see PUSH0 everywhere and zero PUSH1 0x00 entries. Switch to `evm_version = "london"` in foundry.toml and re-inspect — now all zeros become PUSH1 0x00.

#### ⚠️ When returndatasize() Is NOT Safe as Zero

After an external call, `returndatasize()` reflects the callee's return data — it's no longer zero. Only use it as zero *before* any `call`, `staticcall`, or `delegatecall` in the current execution context. Inside a constructor (before any calls) is always safe.

---

<a id="branchless"></a>
### 💡 Concept: Branchless Patterns

**Why this matters:** Conditional jumps (`if`/`else`, ternary operator) compile to JUMPI + JUMPDEST, which costs at least 11 gas (JUMPI = 10, JUMPDEST = 1) plus the comparison opcodes. On hot paths called millions of times, eliminating branches saves meaningful gas. But more importantly, branchless code has *constant gas cost* regardless of the input — no variable-cost branches that could leak information or cause unexpected gas spikes.

This is the signature technique that separates Solady from other libraries. When you see `xor(a, mul(xor(a, b), lt(a, b)))` in production code, this section teaches you exactly what's happening.

**Branchless `min(a, b)`:**

The Solidity ternary `a < b ? a : b` compiles to:

```
// Compiler output (simplified):
LT          // compare a < b  → 0 or 1
PUSH dest   // push jump target
JUMPI       // jump if true
// fall through: push b, JUMP to end
// dest: push a
// end: continue
```

That's ~20 gas for the branch logic. The branchless version:

```solidity
assembly {
    result := xor(b, mul(xor(a, b), lt(a, b)))
}
```

**Step-by-step trace — `min(3, 7)`:**

```
Given: a = 3, b = 7

Step 1: lt(a, b)    →  lt(3, 7)    →  1       // 3 < 7? yes → 1
Step 2: xor(a, b)   →  xor(3, 7)   →  4       // the "diff mask"
Step 3: mul(4, 1)   →  4                        // condition is true → keep diff
Step 4: xor(b, 4)   →  xor(7, 4)   →  3       // apply diff to b → gets a ✓

Result: 3 (the minimum) ✓
```

**Trace — `min(7, 3)`:**

```
Given: a = 7, b = 3

Step 1: lt(a, b)    →  lt(7, 3)    →  0       // 7 < 3? no → 0
Step 2: xor(a, b)   →  xor(7, 3)   →  4       // same diff mask
Step 3: mul(4, 0)   →  0                        // condition is false → zero out diff
Step 4: xor(b, 0)   →  xor(3, 0)   →  3       // no diff applied → stays b ✓

Result: 3 (the minimum) ✓
```

**Why it works:**

The core idea: `xor(a, b)` captures the "difference" between `a` and `b`. Multiplying by the condition (0 or 1) acts as a select — it either applies the difference or doesn't. XOR-ing with `b` either flips `b` to `a` (when the diff is applied) or leaves `b` unchanged.

| Expression | When `a < b` (lt=1) | When `a >= b` (lt=0) |
|---|---|---|
| `mul(xor(a,b), lt(a,b))` | `xor(a,b)` (the diff) | `0` (no diff) |
| `xor(b, ...)` | `xor(b, xor(a,b))` = `a` | `xor(b, 0)` = `b` |
| **Result** | `a` (the smaller) | `b` (the smaller) |

**Gas comparison:**

| Approach | Opcodes | Gas |
|----------|---------|-----|
| Solidity ternary `a < b ? a : b` | LT, JUMPI, JUMPDEST, JUMP | ~20 gas |
| Branchless `xor(b, mul(xor(a,b), lt(a,b)))` | LT, XOR, MUL, XOR | ~14 gas |

Saving ~6 gas per call. On a function called 10 million times per year, that's 60 million gas saved.

**Branchless `max(a, b)`:**

Same pattern, swap `lt` for `gt`:

```solidity
assembly {
    result := xor(b, mul(xor(a, b), gt(a, b)))
}
```

When `a > b`, XOR flips `b` to `a`. When `a <= b`, `b` stays. Result: the larger value.

**Branchless `abs(x)` for signed integers:**

For `int256`, absolute value without branching:

```solidity
assembly {
    let mask := sar(255, x)    // arithmetic shift right by 255
                                // if x >= 0: mask = 0x00...00
                                // if x < 0:  mask = 0xFF...FF
    result := xor(add(x, mask), mask)
}
```

**How the mask works:**

- **Positive `x`:** `sar(255, x)` = 0 (sign bit is 0). `add(x, 0) = x`. `xor(x, 0) = x`. Result: `x` ✓
- **Negative `x`:** `sar(255, x)` = `0xFFFF...FFFF` (sign bit propagated). `add(x, 0xFFFF...FFFF) = x - 1` (two's complement). `xor(x-1, 0xFFFF...FFFF)` = bitwise NOT of `(x-1)` = `-x` (two's complement negation). Result: `-x` ✓

**Trace — `abs(-5)`:**

```
x = -5  (0xFFFF...FFFB in two's complement)

Step 1: mask = sar(255, x) = 0xFFFF...FFFF      // negative → all ones
Step 2: add(x, mask) = -5 + (-1) = -6           // 0xFFFF...FFFA
Step 3: xor(-6, mask) = xor(0x...FFFA, 0x...FFFF) = 0x...0005 = 5  ✓
```

**The general branchless select pattern:**

All these tricks derive from one meta-pattern:

```
select(a, b, condition) = xor(b, mul(xor(a, b), condition))
```

Where `condition` is 0 or 1. When condition=1, result=a. When condition=0, result=b. This replaces any `condition ? a : b` ternary without branching.

💻 **Quick Try:**

Test the branchless min in Remix:
```solidity
function testMin(uint256 a, uint256 b) external pure returns (uint256) {
    assembly {
        mstore(0x00, xor(b, mul(xor(a, b), lt(a, b))))
        return(0x00, 0x20)
    }
}
```
Compare gas against `function testMinSol(uint256 a, uint256 b) external pure returns (uint256) { return a < b ? a : b; }`. The branchless version should be ~6 gas cheaper per call.

#### 🔍 Deep Dive: Why Branchless Matters Beyond Gas

Constant-gas execution prevents **gas-based side channels**. In a branching implementation, the gas cost depends on which branch is taken. An observer monitoring gas usage could infer information about private inputs. In privacy-sensitive protocols (e.g., encrypted order books, sealed auctions), branchless patterns ensure the gas cost reveals nothing about the values being compared.

This is also why Solady's `FixedPointMathLib.mulDiv` uses branchless patterns for its 512-bit intermediate math — the function's gas cost is the same regardless of the input values, making it safer for price computation in AMMs.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How does Solady implement `min()` without branching?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "It uses XOR and multiplication to select between two values without JUMPI."
   - Great answer: "The pattern `xor(b, mul(xor(a,b), lt(a,b)))` uses XOR as a reversible diff. Multiplying by the boolean condition either keeps or zeroes the diff. XOR-ing with b either applies the diff (giving a) or doesn't (giving b). It saves ~6 gas per call and provides constant gas cost regardless of inputs."

   </details>

**Interview Red Flags:**
- 🚩 Not recognizing the XOR-MUL-XOR pattern when reading Solady code
- 🚩 Thinking branchless is only about gas — missing the constant-gas / side-channel angle

**Pro tip:** In an interview, if you can trace through the branchless min on a whiteboard with concrete numbers, it demonstrates deep understanding. This is one of the most impressive things you can show.

<a id="how-to-study"></a>
#### 📖 How to Study Solady's FixedPointMathLib

1. **Start with `min()` and `max()`** — these are the simplest branchless patterns (the ones above). Trace them with 2-3 number pairs.
2. **Read `abs()`** — the SAR-based mask is the next step up. Trace with a positive and negative value.
3. **Move to `mulDiv()`** — this uses branchless patterns inside 512-bit intermediate math. Read the comments first, then trace the branchless selections.
4. **Don't read `fullMulDiv` first** — it's the most complex function. Build up to it through the simpler patterns.

**Don't get stuck on:** The bit-manipulation in `sqrt()` and `log2()` — these are number theory optimizations that go beyond gas optimization into algorithm design. Come back to them after M7 (Reading Production Assembly).

---

<a id="memory-tricks"></a>
### 💡 Concept: Memory Tricks

**Why this matters:** [Module 2](2-memory-calldata.md#scratch-space) taught scratch space usage and the free memory pointer. This section covers three specific tricks that Solady uses to push memory optimization further — patterns the compiler cannot generate from Solidity source.

```
EVM Memory Layout:
┌──────────┬──────────┬──────────────┬──────────────────────────────┐
│ 0x00     │ 0x20     │ 0x40         │ 0x60         │ 0x80...      │
│ Scratch  │ Scratch  │ Free Memory  │ Zero Slot    │ Allocated    │
│ Space 1  │ Space 2  │ Pointer      │ (0x00...00)  │ Memory →     │
└──────────┴──────────┴──────────────┴──────────────┴──────────────┘
│← Dirty memory writes here (0x00-0x43) →│
│  Overwrites FMP and zero slot!          │
```

**Trick 1: Dirty Memory**

The "clean" approach to assembly memory usage:

```solidity
assembly {
    let ptr := mload(0x40)       // load FMP
    mstore(ptr, someData)        // write data
    mstore(0x40, add(ptr, 0x20)) // advance FMP
    // ... use the data ...
    // Memory after FMP is "clean" (unused)
}
```

The dirty memory pattern skips the FMP update:

```solidity
assembly {
    mstore(0x00, shl(224, 0xa9059cbb))  // selector at scratch space
    mstore(0x04, to)                      // arg 1
    mstore(0x24, amount)                  // arg 2 — overwrites FMP at 0x40!
    // Don't care — we're about to call() and then return/revert
    let ok := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
}
```

This writes 68 bytes starting at 0x00, which overwrites the free memory pointer at 0x40 and the zero slot at 0x60. This is **safe** only when:

1. No Solidity code after the assembly block allocates memory (would use corrupted FMP)
2. No Solidity code after the assembly block reads from the zero slot (would get wrong value)

Solady's `SafeTransferLib.safeTransfer` does exactly this — the function either succeeds and returns, or reverts. No Solidity memory operations follow. The dirty memory saves the 3 gas for `mload(0x40)` and 6 gas for updating the FMP (`mstore` 3 gas + `add` 3 gas to compute the new pointer) — 9 gas per call.

#### ⚠️ Common Mistake: Dirty Memory After Solidity Code

Using dirty memory when Solidity code follows the assembly block. If `safeTransfer` were called from a function that later concatenates strings or allocates arrays, the corrupted FMP would cause silent memory corruption. Solady is safe because its functions are self-contained — they either return or revert immediately after the assembly block.

**Trick 2: Skipping the ETH Balance Pre-Check**

[Module 5](5-external-calls.md#safe-erc20) mentioned Solady's ETH transfer optimization but deferred the explanation. Here's how it works.

The standard pattern for sending ETH with a safety check:

```solidity
assembly {
    // Check: does this contract have enough ETH?
    if lt(selfbalance(), amount) {
        // revert InsufficientBalance()
        mstore(0x00, shl(224, errorSelector))
        revert(0x00, 0x04)
    }
    let ok := call(gas(), to, amount, 0, 0, 0, 0)
}
```

That's a `selfbalance()` (5 gas) + `lt` (3 gas) + conditional JUMPI (10 gas) = 18 gas for the check. Solady's trick: skip the pre-check entirely.

```solidity
assembly {
    // CALL sends ETH. If the contract doesn't have enough,
    // CALL itself returns 0 (fails). No pre-check needed.
    if iszero(call(gas(), to, amount, 0, 0, 0, 0)) {
        mstore(0x00, shl(224, errorSelector))
        revert(0x00, 0x04)
    }
}
```

The insight: CALL already checks for sufficient balance internally — if the contract doesn't have enough ETH, CALL returns 0. There's no need to pre-check with `selfbalance()` and branch on the result. Just attempt the CALL and handle failure. This saves 18 gas on the happy path (which is almost all calls), because the `selfbalance` + `lt` + `JUMPI` are eliminated entirely.

**Trick 3: Boolean Logic Ordering**

In [Module 5](5-external-calls.md#safe-erc20), you saw the SafeERC20 compound check:

```solidity
assembly {
    let ok := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
    if iszero(and(ok, or(iszero(returndatasize()), eq(mload(0x00), 1)))) {
        revert(...)
    }
}
```

Why `call()` is executed before the check reads `returndatasize()`: the `and/or` chain is evaluated **after** `call()` completes, so `returndatasize()` reflects the callee's return data. But there's a subtler ordering trick in some Solady code:

```solidity
// Instead of: let ok := call(...); if iszero(ok) { revert }
// Solady sometimes writes:
if iszero(call(gas(), target, amount, 0, 0, 0, 0)) {
    mstore(0x00, shl(224, errorSelector))
    revert(0x00, 0x04)
}
```

Placing the `call()` directly inside `iszero()` means `returndatasize()` is available immediately after the `call` — no intermediate stack operations. In more complex checks (like SafeTransferLib), this ordering ensures the return data buffer hasn't been modified by anything between the call and the check.

---

<a id="arithmetic-shortcuts"></a>
### 💡 Concept: Arithmetic Shortcuts

**Why this matters:** The EVM's opcode pricing creates specific substitution opportunities. These aren't huge savings individually (2-3 gas each), but they appear in tight inner loops — AMM tick computations, token balance updates, Merkle proof verification — where they compound.

**Bit shifting for multiply/divide by powers of 2:**

| Solidity | Assembly equivalent | Gas saved |
|----------|-------------------|-----------|
| `x * 2` | `shl(1, x)` | 2 gas (SHL=3 vs MUL=5) |
| `x * 4` | `shl(2, x)` | 2 gas |
| `x * 256` | `shl(8, x)` | 2 gas |
| `x / 2` | `shr(1, x)` | 2 gas (SHR=3 vs DIV=5) |
| `x / 8` | `shr(3, x)` | 2 gas |
| `x % 256` | `and(x, 0xff)` | 2 gas (AND=3 vs MOD=5) |
| `x % 1024` | `and(x, 0x3ff)` | 2 gas |

The pattern: any power-of-2 multiply → left shift. Power-of-2 divide → right shift. Power-of-2 modulo → AND with `(n-1)`.

#### ⚠️ Only Works for Powers of 2

`x * 3` cannot be replaced with a single shift. (Though `add(shl(1, x), x)` = `2x + x` = `3x` for 9 gas vs MUL's 5 gas — actually more expensive! Only use shifts for actual powers of 2.)

**Inequality checks:**

| Solidity | Assembly equivalent | Opcodes | Gas |
|----------|-------------------|---------|-----|
| `a != b` | `iszero(eq(a, b))` | EQ(3) + ISZERO(3) | 6 gas |
| `a != b` | `sub(a, b)` | SUB(3) | 3 gas |
| `a != b` | `xor(a, b)` | XOR(3) | 3 gas |

Both `sub` and `xor` return non-zero when `a != b` and zero when `a == b`. In a Yul `if` statement (which checks for non-zero), they work as inequality checks: `if sub(a, b) { ... }` executes the block only when `a != b`.

#### ⚠️ Subtle Difference: sub vs xor

`sub(a, b)` and `xor(a, b)` have different non-zero values when `a != b`. `sub(5, 3)` = 2, but `xor(5, 3)` = 6. This doesn't matter for boolean checks (`if` only cares about zero vs non-zero), but it matters if you use the result as a value.

**Boolean normalization:**

```solidity
// Convert any non-zero value to 1:
assembly {
    let boolean := iszero(iszero(x))
    // x = 0  →  iszero(0) = 1  →  iszero(1) = 0  →  0 ✓
    // x = 42 →  iszero(42) = 0 →  iszero(0) = 1  →  1 ✓
    // x = 1  →  iszero(1) = 0  →  iszero(0) = 1  →  1 ✓
}
```

This is 6 gas (2 × ISZERO at 3 gas each). Useful when you need a strict 0/1 value for multiplication in branchless patterns.

**Branchless select (generalized):**

Combining the boolean normalization with multiplication gives a general conditional select:

```solidity
assembly {
    // If condition is non-zero, result = valueIfTrue
    // If condition is zero, result = valueIfFalse
    let c := iszero(iszero(condition))  // normalize to 0 or 1
    result := or(mul(valueIfTrue, c), mul(valueIfFalse, iszero(c)))
}
```

This is the general-purpose branchless ternary: `condition ? valueIfTrue : valueIfFalse` without JUMPI. Total: ~21 gas vs ~20 gas for a branch — it's roughly equal for the general case. The branchless versions win when one of the values is a simple transformation of the other (like the XOR trick in `min`/`max`).

💻 **Quick Try:**

Test the SHL substitution in [Remix](https://remix.ethereum.org/):
```solidity
contract ShiftTest {
    function mulBy8_naive(uint256 x) external pure returns (uint256) {
        return x * 8;
    }
    function mulBy8_shift(uint256 x) external pure returns (uint256 r) {
        assembly { r := shl(3, x) }
    }
}
```
Call both with the same input. The results are identical, but `mulBy8_shift` uses 3 gas (SHL) instead of 5 gas (MUL). The difference is small per call, but multiply by millions of iterations in a Merkle proof loop or AMM tick traversal.

**Quick reference — opcode substitution table:**

| Operation | Naive | Optimized | Saving |
|-----------|-------|-----------|--------|
| Push zero | `PUSH1 0x00` (3 gas, 2 bytes) | `PUSH0` (2 gas, 1 byte) | 1 gas, 1 byte |
| Push zero (pre-Shanghai) | `PUSH1 0x00` (3 gas, 2 bytes) | `RETURNDATASIZE` (2 gas, 1 byte) | 1 gas, 1 byte |
| Multiply by 2^n | `MUL` (5 gas) | `SHL(n, x)` (3 gas) | 2 gas |
| Divide by 2^n | `DIV` (5 gas) | `SHR(n, x)` (3 gas) | 2 gas |
| Modulo by 2^n | `MOD` (5 gas) | `AND(x, 2^n - 1)` (3 gas) | 2 gas |
| Not equal | `ISZERO(EQ(...))` (6 gas) | `XOR` or `SUB` (3 gas) | 3 gas |
| Min(a,b) | Ternary with JUMPI (~20 gas) | `XOR+MUL+XOR+LT` (~14 gas) | ~6 gas |
| Normalize to bool | N/A | `ISZERO(ISZERO(x))` (6 gas) | N/A (no naive equivalent) |

---

<a id="exercise2"></a>
## 🎯 Build Exercise: SoladyTricks

**Workspace:** [`SoladyTricks.sol`](../workspace/src/part4/module6/exercise2-solady-tricks/SoladyTricks.sol)
**Tests:** [`SoladyTricks.t.sol`](../workspace/test/part4/module6/exercise2-solady-tricks/SoladyTricks.t.sol)

Implement the Solady opcode tricks from Topic Block 2. Each function must use inline assembly — no Solidity control flow.

**4 TODOs:**
1. `branchlessMin(uint256 a, uint256 b)` — return the smaller value without JUMPI
2. `branchlessMax(uint256 a, uint256 b)` — return the larger value without JUMPI
3. `branchlessAbs(int256 x)` — return the absolute value without JUMPI
4. `efficientMultiTransfer(address token, address[] calldata to, uint256[] calldata amounts)` — loop through arrays, calling SafeTransferLib-style `transfer` with scratch space encoding and dirty memory

**🎯 Goal:** Internalize the branchless XOR-MUL pattern and the scratch space + dirty memory pattern — the core tricks from Topic Block 2.

---

## 📋 Key Takeaways: The Solady Playbook — Opcode Tricks

After this section, you should be able to:

- Explain PUSH0 (EIP-3855) and `returndatasize()` as zero-push alternatives: when each applies, the gas and bytecode savings
- Implement branchless min/max using the XOR-multiply pattern `xor(b, mul(xor(a,b), lt(a,b)))` and trace it step by step with concrete numbers
- Describe the dirty memory pattern (writing past FMP) and identify when it's safe (self-contained functions that return/revert immediately)
- Apply the SELFBALANCE skip for ETH transfers: skip the pre-check, handle CALL failure instead, saving ~18 gas on the happy path
- Use arithmetic shortcuts in assembly: SHL/SHR for power-of-2 multiply/divide, AND for power-of-2 modulo, XOR/SUB for inequality checks

<details>
<summary>Check your understanding</summary>

- **PUSH0 and returndatasize-as-zero**: PUSH0 (EIP-3855, Shanghai) costs 2 gas and 1 byte, replacing `PUSH1 0x00` (3 gas, 2 bytes). Before Shanghai, `returndatasize()` returns 0 before any external call and costs the same 2 gas — Solady uses this for pre-Shanghai compatibility.
- **Branchless min/max**: The pattern `xor(b, mul(xor(a,b), lt(a,b)))` computes min(a,b) without branching. When `lt(a,b)` is 1, it XORs b with `xor(a,b)` to produce a; when 0, it returns b unchanged. Eliminating branches avoids the JUMPI + JUMPDEST opcode costs and saves gas.
- **Dirty memory pattern**: Writing past the free memory pointer without advancing it saves the FMP update cost. This is safe only when the function returns or reverts immediately after — if Solidity allocates memory later, it overwrites the dirty region.
- **SELFBALANCE skip for ETH transfers**: Instead of checking `selfbalance() >= amount` before calling, skip the pre-check and handle the CALL failure. This saves ~18 gas on the happy path by avoiding the `selfbalance` (5 gas) + `lt` (3 gas) + `JUMPI` (10 gas) check sequence.
- **Arithmetic shortcuts**: `shl(n, x)` replaces `mul(x, 2^n)`, `shr(n, x)` replaces `div(x, 2^n)`, and `and(x, 2^n - 1)` replaces `mod(x, 2^n)` — each saving 3+ gas by using cheaper opcodes.

</details>

---

## 💡 Dispatch Optimization

<a id="dispatch-recap"></a>
### 💡 Concept: Recap — From Linear to Binary

[Module 4](4-control-flow.md#dispatch-patterns) covered the three dispatch strategies the Solidity compiler uses:

```
Incoming calldata: [selector (4 bytes)] [arguments...]
                        │
                        ▼
              ┌─── Linear if-chain ──── O(n)     ~13 gas × function count
              │
Dispatch ─────┼─── Switch statement ─── O(n)     Same gas, cleaner syntax
              │
              └─── Binary search ────── O(log n)  ~13 gas × log₂(function count)
```

The compiler automatically uses binary search for contracts with ~4+ external functions. For a contract with 16 functions, binary search needs ~4 comparisons instead of 16 — a meaningful improvement. But for contracts with 32+ functions (like Uniswap V4's PoolManager), even binary search costs `~13 × 5 = 65 gas` in the worst case.

**The question M4 deferred:** Can we do better than O(log n)? Yes — O(1) constant-gas dispatch, regardless of function count.

---

<a id="jump-table"></a>
### 💡 Concept: Jump Table Dispatch — O(1)

**Why this matters:** This is the dispatch pattern used by ultra-optimized frameworks like Huff. In contracts with many external functions (routers, diamond proxies, pool managers), the dispatch overhead is paid on *every single call*. Making it constant-time eliminates a scaling penalty that grows with contract complexity.

**The idea:**

Instead of comparing the selector against each known value, compute a *jump destination* directly from the selector using a mathematical transformation:

```
selector (4 bytes)
    │
    ▼
(selector >> SHIFT) & MASK  →  index (0, 1, 2, ... N-1)
    │
    ▼
JUMP to handler[index]
```

If you can find SHIFT and MASK values such that every function's selector maps to a unique index, you have O(1) dispatch.

**Step 1: Finding the magic constants**

Given a set of function selectors, you need SHIFT and MASK values where `(selector >> SHIFT) & MASK` produces unique indices for every selector. This is a **minimal perfect hash** — a hash function with no collisions for a known key set.

Example with 4 functions:

```
Function          Selector     Binary (last 16 bits)
──────────────    ──────────   ─────────────────────
getA()            0x1060e542   ...0101 0100 0010
getB()            0x7f1b7ecf   ...0110 1100 1111
getC()            0x99f1ead3   ...1010 1101 0011
getD()            0x7f40a3ed   ...1010 0011 1110 1101

Try SHIFT=0, MASK=0x03 (keep lowest 2 bits):
  getA: 0x42 & 0x03 = 2
  getB: 0xcf & 0x03 = 3
  getC: 0xd3 & 0x03 = 3  ← COLLISION with getB!

Try SHIFT=2, MASK=0x03 (bits 2-3):
  getA: (0x42 >> 2) & 0x03 = 0x10 & 0x03 = 0
  getB: (0xcf >> 2) & 0x03 = 0x33 & 0x03 = 3
  getC: (0xd3 >> 2) & 0x03 = 0x34 & 0x03 = 0  ← COLLISION!

Try SHIFT=4, MASK=0x03 (bits 4-5):
  getA: (0x42 >> 4) & 0x03 = 0x04 & 0x03 = 0
  getB: (0xcf >> 4) & 0x03 = 0x0c & 0x03 = 0  ← COLLISION!

Try SHIFT=1, MASK=0x03:
  getA: (0x42 >> 1) & 0x03 = 0x21 & 0x03 = 1
  getB: (0xcf >> 1) & 0x03 = 0x67 & 0x03 = 3
  getC: (0xd3 >> 1) & 0x03 = 0x69 & 0x03 = 1  ← COLLISION!
```

In practice, you write a script that brute-forces SHIFT and MASK combinations until it finds one with no collisions. For 4-8 functions, a 3-bit mask (8 slots) usually works. For larger function sets, a wider mask or more creative hashing is needed.

**Step 2: Building the jump table**

Once you have SHIFT and MASK, the dispatch code is fixed-cost:

```
// Pseudocode (inline assembly):
//   1. Extract selector from calldata
//   2. Compute index = (selector >> SHIFT) & MASK
//   3. Load jump destination from a table
//   4. JUMP to the handler

assembly {
    let selector := shr(224, calldataload(0))
    let index := and(shr(SHIFT, selector), MASK)

    // Each handler address is stored sequentially in code
    // Jump table: [handler0_dest, handler1_dest, handler2_dest, ...]
    // Compute: dest = JUMP_TABLE_START + index * 2  (each PUSH2 + JUMPDEST = 2 bytes)

    // Method: computed JUMP
    // Load the destination from a lookup array, then JUMP
    switch index
    case 0 { /* handler for getA */ }
    case 1 { /* handler for getB */ }
    case 2 { /* handler for getC */ }
    case 3 { /* handler for getD */ }
    default { revert(0, 0) }
}
```

Wait — that's still a switch statement! The *real* O(1) dispatch requires raw EVM opcodes, not Yul's `switch`. In pure bytecode (or Huff), you'd compute a jump destination and use a raw JUMP:

```
// EVM bytecode (conceptual):
CALLDATALOAD(0)          // load first 32 bytes
SHR(224)                 // shift right to get 4-byte selector
SHR(SHIFT)               // apply shift
AND(MASK)                // apply mask → index
MUL(ENTRY_SIZE)          // index × bytes per entry
ADD(TABLE_START)         // offset into jump table
JUMP                     // go to handler
```

This is 7 opcodes with constant cost: `3 + 3 + 3 + 3 + 5 + 3 + 8 = 28 gas` for the dispatch itself, plus ~65 gas overhead for calldata loading and table lookup. Total: **~93 gas regardless of function count**.

#### ⚠️ Important Limitation: Yul and Computed JUMPs

Yul does not support computed JUMPs — `switch` compiles to sequential comparisons. True O(1) jump table dispatch requires either:
- **Huff:** Designed for this — has native jump table support
- **Raw bytecode in `CREATE` or constructor:** Deploy pre-computed bytecode
- **M8 (Pure Yul contracts):** Where you have full control over the code layout

For inline assembly within Solidity, the best you can do is an optimized `switch` (which is still O(n), but with very small constants). True O(1) dispatch is a topic that bridges M6 (understanding the concept) and M8 (implementing it in pure Yul).

**Gas comparison table:**

| Strategy | Functions | Worst-case gas | When to use |
|----------|-----------|---------------|-------------|
| Linear if-chain | N | ~13 × N | 1-3 functions |
| Binary search (Solidity default) | N | ~13 × log₂(N) | 4-20 functions |
| Jump table O(1) | N | ~93 (constant) | 128+ functions, or when constant-cost dispatch is required |

At 25 functions, binary search worst case: `13 × 5 = 65 gas`. Jump table: ~93 gas. Binary search is still cheaper! The jump table overtakes binary search at around 128 functions (`13 × 7 = 91 < 93`), but jump tables really shine when you need **guaranteed constant cost** or when combined with other optimizations in Huff/pure Yul contracts where the overhead is lower.

#### 🔍 Deep Dive: The Philogy Approach

[Philogy's analysis](https://philogy.github.io/posts/selector-switches/) explores a different approach: instead of shift+mask, use the *entire selector as an offset into a sparse table*. The table has empty slots for non-matching selectors (which jump to a revert handler) and valid destinations for matching ones.

The advantage: no collision-finding needed. The disadvantage: the table is large (up to 2^16 entries for a 2-byte index). In practice, a careful choice of which bits of the selector to use as the index keeps the table small.

The key insight from Philogy's work: **the optimal dispatch strategy depends on your specific selector set.** There's no universal "best" approach — you must analyze your selectors and choose the strategy that minimizes gas for your contract.

#### 🔗 DeFi Pattern Connection

**Where dispatch optimization matters in DeFi:**

1. **Uniswap V4 PoolManager:** 20+ external functions. Every swap, every liquidity operation, every hook callback goes through dispatch. At millions of calls per day, saving even 20 gas per dispatch = millions of gas saved.
2. **Diamond proxies (EIP-2535):** Multiple facets, each with its own function set. The dispatch has two levels: first find the facet, then dispatch within it. Jump tables at either level help.
3. **L2 sequencers:** On L2, compute gas is cheap but calldata is expensive. The dispatch cost is less important than calldata encoding, but constant-time dispatch prevents gas spikes that could affect block building.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you implement O(1) function dispatch?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "Compute an index from the selector using shift and mask operations to find a unique mapping, then use that index to jump to the handler."
   - Great answer: "Find a minimal perfect hash for your selector set — a SHIFT and MASK such that `(selector >> SHIFT) & MASK` produces unique indices. In Huff or pure Yul, this becomes a computed JUMP for ~93 constant gas. In Solidity inline assembly, you're limited to switch statements since Yul doesn't support computed jumps. The real value is in protocols with 25+ functions where binary search's O(log n) starts to add up."

   </details>

2. **"When is jump table dispatch worth the complexity?"**
   <details>
   <summary>Answer</summary>

   - Great answer: "Almost never in inline assembly — binary search is good enough for most contracts. It matters in Huff/pure Yul for high-function-count contracts like Uniswap V4, or in frameworks where dispatch overhead must be constant regardless of function count."

   </details>

**Interview Red Flags:**
- 🚩 Claiming jump tables are always faster than binary search (they're not, below ~128 functions)
- 🚩 Not knowing the limitation of Yul's `switch` (it compiles to sequential comparisons)

**Pro tip:** Understanding *why* jump tables exist and when they help shows architectural thinking. You don't need to implement one from memory — you need to know the trade-offs.

---

<a id="selector-ordering"></a>
### 💡 Concept: Function Selector Ordering

**Why this matters:** Beyond dispatch logic, the *selector value itself* affects gas. This matters most on L2, where calldata cost dominates.

**Calldata byte costs (EIP-2028):**

| Byte type | Cost |
|-----------|------|
| Zero byte (`0x00`) | 4 gas |
| Non-zero byte | 16 gas |

A function selector is 4 bytes in calldata. A selector like `0x00000081` costs `4 + 4 + 4 + 16 = 28 gas`, while `0x6a761202` costs `16 + 16 + 16 + 16 = 64 gas`. That's 36 gas difference just from the selector.

**Vanity selector mining:**

By renaming functions, you can influence their selectors. The selector is `keccak256("functionName(argTypes)")` — even a small name change produces a completely different selector.

```bash
# Check a selector with cast:
cast sig "transfer(address,uint256)"
# 0xa9059cbb — no leading zeros

cast sig "transfer_Y8i(address,uint256)"
# 0x00000... — mined to have leading zeros (hypothetical)
```

In practice, tools like [function-selector-miner](https://github.com/kadenzipfel/function-selector-miner) brute-force function name suffixes to find selectors with leading zeros.

**When teams actually do this:**

- **L2 deployments:** On Optimism/Arbitrum, calldata is the dominant gas cost. Leading-zero selectors save 12 gas per zero byte × ~3 zero bytes = ~36 gas per call. At millions of calls, this adds up.
- **Uniswap V4:** The team considered selector mining for their most-called functions.
- **Most L1 contracts:** Not worth it. The 36 gas savings is negligible compared to storage and compute costs. The readability cost of mangled function names usually isn't justified.

**Break-even analysis:** Mining a selector with 3 leading zero bytes saves ~36 gas per call. On L2 at $0.01 per 1M gas, that's $0.00036 per call. At 1M calls/year = $360/year. Mining takes minutes with modern tools. On L1 the savings are similarly small in dollar terms — only worth it for hyper-hot paths.

**Dispatch order within binary search:**

The Solidity compiler sorts selectors numerically for binary search. You can't control the tree structure directly. But if you're writing your own dispatch in assembly (M4's `switch` or an if-chain), place the most-called functions first:

```solidity
assembly {
    let sel := shr(224, calldataload(0))

    // Hot functions first — most calls hit these
    if eq(sel, 0xa9059cbb) { /* transfer — called 10M times */ }
    if eq(sel, 0x70a08231) { /* balanceOf — called 5M times */ }
    if eq(sel, 0x095ea7b3) { /* approve — called 1M times */ }

    // Cold functions last — rarely called
    if eq(sel, 0x8da5cb5b) { /* owner — called 100 times */ }

    revert(0, 0) // unknown selector
}
```

In a linear if-chain, `transfer` is found on the first comparison. In the compiler's binary search, it might be 3 comparisons deep. For hot functions, manual ordering in a linear chain can beat binary search.

---

<a id="exercise3"></a>
## 🎯 Build Exercise: JumpDispatcher

**Workspace:** [`JumpDispatcher.sol`](../workspace/src/part4/module6/exercise3-jump-dispatcher/JumpDispatcher.sol)
**Tests:** [`JumpDispatcher.t.sol`](../workspace/test/part4/module6/exercise3-jump-dispatcher/JumpDispatcher.t.sol)

Implement an optimized dispatcher for a contract with 8 functions. The selectors are pre-computed — you implement the dispatch logic.

**2 TODOs:**
1. Implement the `fallback()` dispatcher: extract selector → switch to the right handler
2. Each handler: store the return value at scratch space and `return(0x00, 0x20)`

**🎯 Goal:** Understand the mechanics of selector-based dispatch and why constant-cost matters for large contracts — the concepts from Topic Block 3.

---

## 📋 Key Takeaways: Dispatch Optimization

After this section, you should be able to:

- Explain jump table dispatch: how `(selector >> SHIFT) & MASK` computes a unique index for O(1) function routing, and why finding collision-free constants requires brute-force search
- Compare dispatch strategies by gas cost: linear if-chain O(n), binary search O(log n), jump table O(1), and identify the crossover points (~128 functions)
- Describe the Yul limitation for jump tables (no computed JUMPs in inline assembly) and when to use Huff or pure Yul (M8) instead
- Explain selector mining: renaming functions to get leading-zero selectors saves calldata gas (12 gas per zero byte), primarily valuable on L2

<details>
<summary>Check your understanding</summary>

- **Jump table dispatch**: `(selector >> SHIFT) & MASK` maps each 4-byte selector to a unique table index in O(1) time. Finding collision-free SHIFT and MASK constants requires brute-force search over the selector set — no analytical solution exists.
- **Dispatch strategy comparison**: Linear if-chain costs ~13 gas per function (O(n)); binary search costs ~13 gas per log2(n) comparisons (O(log n)); jump tables cost a fixed ~93 gas regardless of function count (O(1), including calldata loading overhead). Jump tables only justify their complexity at ~128+ functions.
- **Yul limitation for jump tables**: Yul does not allow computed JUMPs — all jump destinations must be known at compile time. True O(1) dispatch requires Huff or pure Yul (M8), which have direct access to JUMP with computed destinations.
- **Selector mining**: Renaming functions (e.g., `swap_k1d4()` instead of `swap()`) to produce selectors with leading zero bytes saves 12 gas per zero byte in calldata. This matters primarily on L2 where calldata is the dominant cost.

</details>

---

## 💡 The Optimization Decision Framework

<a id="when-worth-it"></a>
### 💡 Concept: When Assembly Is Worth It

**Why this matters:** The hardest skill in gas optimization isn't writing fast code — it's knowing *when* to write it. Assembly is harder to read, harder to audit, and harder to maintain. The question isn't "can I make this faster?" (you almost always can), but "should I?"

[Module 5](5-external-calls.md) promised this framework. Here it is.

**The hot path rule:**

```
Optimization value = gas_saved × expected_calls × gas_price × ETH_price
Optimization cost  = engineering_hours × rate + audit_hours × auditor_rate + maintenance_tax
```

If value > cost, optimize. If not, write clean Solidity.

**Concrete example:**

```
Scenario: Optimize an ERC20 transfer function
- Gas savings: 500 gas per call (assembly SafeTransferLib vs Solidity)
- Expected calls: 10M per year
- Gas price: 30 gwei average
- ETH price: $3,000

Value = 500 × 10,000,000 × 30 × 10⁻⁹ × 3,000
      = 500 × 10M × 0.00000003 × 3,000
      = $450,000 per year

Cost = 40 hours × $200/hr (engineering) + 20 hours × $500/hr (audit)
     = $8,000 + $10,000 = $18,000

ROI = $450,000 / $18,000 = 25x  → Absolutely worth it
```

Now the same calculation for an admin `setFee()` function:

```
- Gas savings: 500 gas
- Expected calls: 10 per year
- Same gas/ETH prices

Value = 500 × 10 × 0.00000003 × 3,000 = $0.45 per year

Cost = same $18,000

ROI = $0.45 / $18,000 = 0.000025x  → Absolutely NOT worth it
```

**The Solady philosophy:**

Solady's approach is the gold standard: **optimize the primitives, write the application in Solidity.**

- SafeTransferLib, FixedPointMathLib, MerkleProofLib → assembly. These are called billions of times across all protocols that import them. Every gas saved multiplies across the entire ecosystem.
- Your application's `deposit()`, `withdraw()`, `harvest()` → clean Solidity. These are called by one protocol. The audit cost of assembly outweighs the gas savings.

**Optimization tiers:**

| Tier | Example | Optimize with assembly? | Why |
|------|---------|------------------------|-----|
| Ecosystem primitives | SafeTransferLib, mulDiv | **Yes** | Called by every protocol. Savings multiply across ecosystem |
| Hot protocol functions | AMM swap, lending supply | **Profile first** | High call volume, but audit cost is real |
| Standard protocol functions | Deposit, withdraw | **No — use Solidity** | Moderate call volume, readability matters more |
| Admin functions | setFee, pause, upgrade | **No — clean Solidity** | Called rarely, security is paramount |
| Constructor / deployment | One-time init | **No** | Runs once, literally |

💻 **Quick Try:**

Pick one of your existing exercises from Part 4. Run `forge test --gas-report` and identify the most-called function. Calculate the ROI: if you saved 500 gas per call, how many calls per year would justify 40 hours of engineering + 20 hours of audit? (Hint: use 30 gwei and $3,000 ETH.) Most functions don't cross the threshold.

#### ⚠️ Common Mistake: "I Optimized Everything!"

This is a red flag in code reviews. If every function is hand-written assembly, the audit cost triples, the bug surface triples, and the gas savings on cold paths are negligible. Protocol teams want to see *judgment* — knowing where to optimize and where to stop.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"When is assembly-level gas optimization worth it?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "When the function is on a hot path — high call volume, high gas cost per call."
   - Great answer: "I'd calculate the ROI: gas saved times expected calls times gas price, versus the audit and maintenance cost. Assembly makes sense for ecosystem primitives and hot protocol paths. For everything else, Solidity with the right optimizer settings is better. The Solady model — optimize the library, not the application — is the smartest approach."

   </details>

2. **"You're building a new lending protocol. Which functions would you write in assembly?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "The core supply/borrow/liquidation functions after profiling shows they're bottlenecks."
   - Great answer: "I'd import Solady for token transfers and math (already optimized, already audited), then write everything else in Solidity. If profiling shows a specific function is a bottleneck, I'd optimize that one function — not the whole protocol. I'd also tune optimizer settings (high runs for the core contract) before reaching for assembly."

   </details>

**Interview Red Flags:**
- 🚩 "I always use assembly for gas optimization" — shows no judgment
- 🚩 "Assembly is too risky, I never use it" — shows no willingness to optimize hot paths
- 🚩 Not mentioning measurement or profiling

**Pro tip:** In an interview, mentioning the Solady model and the concept of ROI on optimization shows you think about engineering economics, not just opcodes. This is what separates senior engineers from enthusiastic juniors.

---

<a id="architectural-wins"></a>
### 💡 Concept: Architectural Wins That Dwarf Opcode Tricks

**Why this matters:** The optimization hierarchy is: **architecture > algorithm > opcode tricks.** Changing your architecture can save 100,000+ gas per operation. Opcode tricks save 2-20 gas each. Before micro-optimizing, ask: "Can I eliminate an entire operation?"

**The hierarchy in action:**

```
┌──────────────────────────────────────────────────────┐
│ Architecture: eliminate operations entirely           │  100,000+ gas
│ (singleton, flash accounting, batch settlement)       │
├──────────────────────────────────────────────────────┤
│ Algorithm: better approach for same operation         │  10,000+ gas
│ (binary search vs linear, packed storage vs separate) │
├──────────────────────────────────────────────────────┤
│ Opcode: faster version of same approach               │  2-20 gas each
│ (branchless min, shift vs multiply, PUSH0)            │
└──────────────────────────────────────────────────────┘
```

**Example 1: Uniswap V3 → V4 (Singleton architecture)**

V3: Each pool is a separate contract. A 3-hop swap (ETH → USDC → DAI → WBTC) makes 3 cross-contract calls. Each cold CALL costs 2,600 gas + overhead.

V4: All pools live in one contract (the PoolManager singleton). The same 3-hop swap is 3 internal function calls. No cross-contract overhead.

| | V3 (factory) | V4 (singleton) |
|---|---|---|
| 3-hop swap: call overhead | 3 × 2,600 = 7,800 gas | ~0 (internal calls) |
| Token transfers per hop | 6 (2 per hop: in + out) | 2 total (flash accounting) |
| Estimated total savings | — | ~200,000 gas per multi-hop |

No amount of assembly optimization in V3 could achieve what V4's architecture change does.

**Example 2: Flash Accounting (net settlement)**

Without flash accounting, a 3-hop swap transfers tokens at every hop:

```
Hop 1: transfer ETH in, transfer USDC out     (2 SSTORE = ~40,000 gas)
Hop 2: transfer USDC in, transfer DAI out      (2 SSTORE = ~40,000 gas)
Hop 3: transfer DAI in, transfer WBTC out      (2 SSTORE = ~40,000 gas)
                                          Total: ~120,000 gas in transfers
```

With flash accounting, you track balance deltas in [transient storage](3-storage.md#transient-storage) (100 gas per TSTORE) and settle at the end:

```
Hop 1: delta[ETH] += amountIn, delta[USDC] -= amountOut     (2 TSTORE = 200 gas)
Hop 2: delta[USDC] += amountIn, delta[DAI] -= amountOut     (2 TSTORE = 200 gas)
Hop 3: delta[DAI] += amountIn, delta[WBTC] -= amountOut     (2 TSTORE = 200 gas)
Settle: transfer ETH in, transfer WBTC out                   (2 SSTORE = ~40,000 gas)
                                                        Total: ~40,600 gas
```

Savings: ~79,000 gas. And this scales — a 10-hop swap saves even more, because settlement is always just 2 transfers regardless of hops.

**Example 3: Access Lists (EIP-2930)**

Pre-declare which addresses and storage slots you'll access:

```solidity
// Transaction with access list:
{
    "accessList": [
        { "address": "0xPool...", "storageKeys": ["0x0", "0x1", "0x5"] }
    ]
}
```

Each pre-warmed slot costs 1,900 gas in the access list (vs 2,100 for a cold SLOAD in the transaction). Net saving: 200 gas per slot. For a swap touching 10 storage slots, that's 2,000 gas saved with zero code changes.

#### ⚠️ Caveat: Suboptimal Access Lists

~20% of real-world access lists are suboptimal — they include slots that won't actually be accessed, wasting the pre-warming cost. Always measure.

**Example 4: L2 Calldata Optimization**

On L2 rollups (Optimism, Arbitrum), computation is cheap but calldata is expensive (it's posted to L1). The dominant gas cost shifts from SSTORE to calldata bytes:

| L2 | Calldata zero byte | Calldata non-zero byte |
|----|--------------------|----------------------|
| Mainnet | 4 gas | 16 gas |
| Optimism/Arbitrum | ~4 gas + L1 posting | ~16 gas + L1 posting |

On L2, the "L1 posting" component makes calldata 10-100x more expensive relative to compute. Strategies:

- **Custom packed encoding:** Skip ABI's 32-byte padding. Pack arguments tightly and decode in the contract. Reduces calldata by 30-40%.
- **Zero-byte awareness:** Use addresses with leading zeros (CREATE2 mining). Use uint128 instead of uint256 when the top 16 bytes would be zero.
- **Batch operations:** One multicall with 10 operations has less per-operation calldata overhead than 10 separate transactions.

---

<a id="deployment-optimization"></a>
### 💡 Concept: Deployment Optimization

**Why this matters:** Deployment gas is paid once, but for factory patterns that deploy many instances (Uniswap pairs, Aave pools, clone factories), "once" can mean thousands of times.

**Payable constructors and admin functions:**

```solidity
// Default (non-payable):
constructor() {
    // Compiler adds: require(msg.value == 0)
    // That check costs ~200 gas of bytecode
}

// Payable — removes the check:
constructor() payable {
    // No msg.value check
    // Saves ~200 gas deployment
}
```

For admin-only functions (onlyOwner), making them `payable` removes the msg.value check. Since only the owner calls these (and wouldn't accidentally send ETH), the check is unnecessary. Saves a few bytes of bytecode per function.

**PUSH0 minimal proxy (ERC-1167):**

[Module 4](4-control-flow.md) covered the ERC-1167 minimal proxy — a 45-byte contract that DELEGATECALLs everything to an implementation. With PUSH0, the proxy bytecode shrinks slightly and saves 4 gas at runtime (one `PUSH1 0x00` → `PUSH0` in the delegation code).

**Metadata hash:**

The Solidity compiler appends a CBOR-encoded metadata hash (IPFS hash of the source + compiler version) to every contract's bytecode. This adds 43 bytes = 8,600 gas deployment cost.

```bash
# Remove it:
forge build --extra-output-files metadata --no-cbor-metadata
```

Only do this if you have another way to verify source code (e.g., Etherscan verification, deterministic builds). Removing metadata makes verification harder.

**EIP-170 code size limit:**

Deployed contracts cannot exceed 24,576 bytes (EIP-170). Large contracts must split functionality across multiple contracts (using inheritance, libraries, or proxy patterns). Aggressive inlining from high `optimizer_runs` can push contracts over this limit — always check: `forge build --sizes`.

---

## 📋 Key Takeaways: The Optimization Decision Framework

After this section, you should be able to:

- Apply the optimization hierarchy — architecture > algorithm > opcode tricks — and give examples where each level dominates (Uniswap V4 singleton saves 200,000+ gas, no opcode trick comes close)
- Evaluate whether assembly optimization is worth it for a given function: gas saved x expected calls vs engineering + audit cost
- Describe architectural gas wins: singleton pattern, flash accounting (net settlement), access lists (EIP-2930), and L2 calldata optimization
- Explain the Solady philosophy: optimize ecosystem primitives in assembly, write applications in clean Solidity — maximizing ROI while minimizing audit risk

<details>
<summary>Check your understanding</summary>

- **Optimization hierarchy**: Architecture changes (singleton pattern, flash accounting) save 100,000+ gas per operation. Algorithm changes (binary search, packed storage) save 10,000+ gas. Opcode tricks save 2-20 gas each. Always exhaust higher levels before micro-optimizing.
- **ROI evaluation**: Multiply gas saved per call by expected annual calls by gas price by ETH price, then compare against engineering + audit cost. A 500-gas savings on a function called 10M times/year is worth ~$450K; the same savings on a function called 10 times/year is worth $0.45.
- **Architectural wins**: Uniswap V4's singleton eliminates cross-contract call overhead (~200,000 gas for multi-hop swaps). Flash accounting replaces per-hop token transfers with transient storage deltas settled once at the end. Access lists (EIP-2930) pre-warm storage slots for 200 gas savings each.
- **Solady philosophy**: Optimize ecosystem primitives (SafeTransferLib, FixedPointMathLib) in assembly because they're called billions of times across all protocols. Write application logic (deposit, withdraw, harvest) in clean Solidity because audit cost outweighs gas savings for single-protocol functions.

</details>

---

## 📚 Resources

**Essential References:**
- [Solady](https://github.com/vectorized/solady) — the reference for gas-optimized Solidity/assembly patterns
- [Foundry Gas Reports](https://book.getfoundry.sh/forge/gas-reports) — official docs for `--gas-report` and `forge snapshot`
- [EVM Codes](https://www.evm.codes/) — interactive opcode reference with gas costs

**Dispatch Optimization:**
- [Philogy: Constant Gas Function Dispatchers](https://philogy.github.io/posts/selector-switches/) — deep analysis of O(1) dispatch strategies
- [Huff Language](https://docs.huff.sh/) — assembly-first EVM language with native jump table support

**EIPs:**
- [EIP-3855](https://eips.ethereum.org/EIPS/eip-3855) — PUSH0 instruction
- [EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) — Optional access lists for pre-warming
- [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) — Blob transactions for L2 data availability
- [EIP-170](https://eips.ethereum.org/EIPS/eip-170) — Contract code size limit (24,576 bytes)

**Tools:**
- `cast sig "function(types)"` — compute function selectors from the command line
- `forge inspect ContractName asm` — view compiler-generated assembly
- `forge inspect ContractName ir-optimized` — view optimized Yul IR
- `forge build --sizes` — check contract bytecode sizes against EIP-170 limit

---

**Navigation:** [← Module 5: External Calls](5-external-calls.md) | [Module 7: Reading Production Assembly →](7-production-assembly.md)
