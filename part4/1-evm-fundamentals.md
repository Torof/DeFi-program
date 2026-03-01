# Part 4 — Module 1: EVM Fundamentals (~3 days)

> **Prerequisites:** Parts 1-3 completed
>
> **Builds on:** Every `assembly { }` block you've encountered — mulDiv internals, proxy forwarding, transient storage guards, Solady optimizations
>
> **Sets up:** Everything in Part 4 — this is the mental model for the machine
>
> **Estimated reading time:** ~45 minutes | **Exercises:** ~2-3 hours

---

## 📚 Table of Contents

**The Machine**
- [The Stack Machine](#stack-machine)
  - [Deep Dive: Tracing Stack Execution](#tracing-stack)
- [Opcode Categories](#opcode-categories)

**Cost & Context**
- [Gas Model — Why Things Cost What They Cost](#gas-model)
  - [Deep Dive: EIP-2929 Warm/Cold Access](#warm-cold)
  - [Deep Dive: Memory Expansion Cost](#memory-expansion)
  - [The 63/64 Rule](#63-64-rule)
- [Execution Context at the Opcode Level](#execution-context)

**Writing Assembly**
- [Your First Yul](#first-yul)
  - [Intermediate Example: Assembly Functions](#intermediate-yul)
- [Contract Bytecode: Creation vs Runtime](#bytecode)
  - [How to Study EVM Bytecode](#how-to-study)
- [Build Exercise: YulBasics](#exercise1)
- [Build Exercise: GasExplorer](#exercise2)

**Wrap-Up**
- [Summary](#summary)
- [Resources](#resources)

---

## The Machine

<a id="stack-machine"></a>
### 💡 Concept: The EVM is a Stack Machine

**Why this matters:** Throughout Parts 1-3, you wrote Solidity and Solidity compiled to EVM bytecode. You've used `assembly { }` blocks for transient storage, seen `mulDiv` internals, read proxy forwarding code. But to truly write assembly — not just copy patterns — you need to understand how the machine actually executes. The EVM is a **stack machine**, and everything flows from that one design choice.

**What "stack machine" means:**

Most CPUs are **register machines** — they have named storage locations (registers like `eax`, `r1`) and instructions operate on those registers. The EVM has **no registers**. Instead, it has a **stack**: a last-in, first-out (LIFO) data structure where every operation pushes to or pops from the top.

Key properties:
- Every item on the stack is a **256-bit (32-byte) word** — this is why `uint256` is the native type
- Maximum stack depth is **1024** — this is where Solidity's "stack too deep" error comes from
- Most opcodes pop their inputs from the stack and push their result back

```
Stack grows upward:

    ┌─────────┐
    │  top    │  ← Most recent value (operations read from here)
    ├─────────┤
    │  ...    │
    ├─────────┤
    │  bottom │  ← First value pushed
    └─────────┘
```

**The core stack operations:**

| Opcode | Gas | Effect | Example |
|--------|-----|--------|---------|
| `PUSH1`-`PUSH32` | 3 | Push 1-32 byte value onto stack | `PUSH1 0x05` → pushes 5 |
| `POP` | 2 | Remove top item | Discards top value |
| `DUP1`-`DUP16` | 3 | Duplicate the Nth item to top | `DUP1` copies top item |
| `SWAP1`-`SWAP16` | 3 | Swap top with Nth item | `SWAP1` swaps top two |

> The DUP/SWAP limit of 16 is a hard EVM constraint. When Solidity needs more than 16 values simultaneously, it spills to memory — or you get "stack too deep." This is why optimizing local variable count matters, and why the `via_ir` compiler pipeline helps (it's smarter about stack management).

💻 **Quick Try:**

Open [Remix](https://remix.ethereum.org/), deploy this contract, call `simpleAdd(3, 5)`, then use the **debugger** (bottom panel → click the transaction → "Debug"):

```solidity
function simpleAdd(uint256 a, uint256 b) external pure returns (uint256) {
    return a + b;
}
```

Step through the opcodes and watch the stack change at each step. You'll see values being pushed, the `ADD` opcode consuming two items and pushing the result.

> **Tip:** In the Remix debugger, the "Stack" panel shows current stack state. The "Step Details" panel shows the current opcode. Step forward with the arrow buttons and watch how each opcode transforms the stack.

---

<a id="tracing-stack"></a>
#### 🔍 Deep Dive: Tracing Stack Execution

**The problem it solves:** Reading assembly requires mentally tracing the stack. Let's build that skill with a concrete example.

**Example: Computing `a + b * c` where a=2, b=3, c=5**

Solidity evaluates multiplication before addition (standard precedence). Here's how the EVM executes it:

```
Step 1: PUSH 2 (value of a)
Stack: [ 2 ]

Step 2: PUSH 3 (value of b)
Stack: [ 2, 3 ]

Step 3: PUSH 5 (value of c)
Stack: [ 2, 3, 5 ]

Step 4: MUL (pops 3 and 5, pushes 15)
Stack: [ 2, 15 ]

Step 5: ADD (pops 2 and 15, pushes 17)
Stack: [ 17 ]
```

**Visual step-by-step:**

```
        PUSH 2    PUSH 3    PUSH 5    MUL       ADD
        ──────    ──────    ──────    ───       ───
    ┌──┐      ┌──┐      ┌──┐      ┌──┐      ┌──┐
    │  │      │  │      │ 5│  top  │  │      │  │
    ├──┤      ├──┤      ├──┤      ├──┤      ├──┤
    │  │      │ 3│      │ 3│      │15│  top  │  │
    ├──┤      ├──┤      ├──┤      ├──┤      ├──┤
    │ 2│ top  │ 2│      │ 2│      │ 2│      │17│  top
    └──┘      └──┘      └──┘      └──┘      └──┘
```

**Key insight:** The compiler must order the PUSH instructions so that operands are in the right position when the operation executes. MUL pops the **top two** items. ADD pops the **next two**. The compiler arranges pushes to make this work.

**What happens when it goes wrong — stack underflow:**

```
Step 1: PUSH 5         Stack: [ 5 ]
Step 2: ADD             Stack: ???  ← Only one item! ADD needs two.
                        → EVM reverts (stack underflow)
```

The EVM doesn't silently use zero for the missing item — it halts execution. This is why the compiler carefully tracks how many items are on the stack at every point. In hand-written assembly, stack underflow is one of the most common bugs.

**A more complex example — why DUP matters:**

What if you need to use a value twice? Say `a * a + b`:

```
Step 1: PUSH a         Stack: [ a ]
Step 2: DUP1           Stack: [ a, a ]       ← Copy a (need it twice)
Step 3: MUL            Stack: [ a*a ]
Step 4: PUSH b         Stack: [ a*a, b ]
Step 5: ADD            Stack: [ a*a + b ]
```

Without DUP, you'd have to push `a` twice from calldata (more expensive). DUP copies a stack item for 3 gas instead of re-reading from calldata (3 + offset cost).

**Why this matters for DeFi:** When you read assembly in production code (Solady's `mulDiv`, Uniswap's `FullMath`), you'll see long sequences of DUP and SWAP. They're not random — they're the compiler (or developer) managing values on the stack to minimize memory usage and gas cost.

#### 🔗 DeFi Pattern Connection

**Where stack mechanics show up:**

1. **"Stack too deep" in complex DeFi functions** — Functions with many local variables (common in lending pool liquidation logic, multi-token vault math) hit the 16-variable stack limit. Solutions: restructure into helper functions, use structs, or enable `via_ir` compilation
2. **Solady assembly libraries** — Hand-written assembly avoids Solidity's stack management overhead, using DUP/SWAP explicitly for optimal layout
3. **Proxy forwarding** — The `delegatecall` forwarding in proxies is written in assembly because the stack-based copy of calldata/returndata is more efficient than Solidity's ABI encoding

---

<a id="opcode-categories"></a>
### 💡 Concept: Opcode Categories

**Why this matters:** The EVM has ~140 opcodes. You don't need to memorize them all. You need to understand the **categories** so you can look up specifics when reading real code. Think of this as your map — you'll fill in the details as you encounter them.

> **Reference:** [evm.codes](https://www.evm.codes/) is the definitive interactive reference. Every opcode, gas cost, stack effect, and playground examples. Bookmark it — you'll use it constantly in Part 4.

**The categories:**

| Category | Key Opcodes | Gas Range | You'll Use These For |
|----------|-------------|-----------|---------------------|
| **Arithmetic** | ADD, MUL, SUB, DIV, SDIV, MOD, SMOD, EXP, ADDMOD, MULMOD | 3-50+ | Math in assembly |
| **Comparison** | LT, GT, SLT, SGT, EQ, ISZERO | 3 | Conditionals |
| **Bitwise** | AND, OR, XOR, NOT, SHL, SHR, SAR, BYTE | 3-5 | Packing, masking, shifts |
| **Environment** | ADDRESS, CALLER, CALLVALUE, CALLDATALOAD, CALLDATASIZE, CALLDATACOPY, CODESIZE, GASPRICE, RETURNDATASIZE, RETURNDATACOPY | 2-3 | Reading execution context |
| **Block** | BLOCKHASH, COINBASE, TIMESTAMP, NUMBER, PREVRANDAO, GASLIMIT, CHAINID, BASEFEE, BLOBBASEFEE | 2-20 | Time/block info |
| **Memory** | MLOAD, MSTORE, MSTORE8, MSIZE | 3* | Temporary data, ABI encoding |
| **Storage** | SLOAD, SSTORE | 100-20000 | Persistent state |
| **Transient** | TLOAD, TSTORE | 100 | Same-tx temporary state |
| **Flow** | JUMP, JUMPI, JUMPDEST, PC, STOP, RETURN, REVERT, INVALID | 1-8 | Control flow, function returns |
| **System** | CALL, STATICCALL, DELEGATECALL, CREATE, CREATE2, SELFDESTRUCT | 100-32000+ | External interaction |
| **Stack** | POP, PUSH1-32, DUP1-16, SWAP1-16 | 2-3 | Stack manipulation |
| **Logging** | LOG0, LOG1, LOG2, LOG3, LOG4 | 375+ | Events |
| **Hashing** | KECCAK256 | 30+6/word | Mapping keys, signatures |

*Memory opcodes have a base cost of 3 plus memory expansion cost (covered in the gas model section).

**PUSH0 — The newest stack opcode:**

> Introduced in [EIP-3855](https://eips.ethereum.org/EIPS/eip-3855) (Shanghai fork, April 2023)

Every modern contract uses `PUSH0` — it pushes zero onto the stack for **2 gas**, replacing the old `PUSH1 0x00` which cost 3 gas. Tiny saving per use, but zero is pushed constantly (initializing variables, memory offsets, return values), so it adds up across an entire contract.

Before Shanghai, a common gas trick was using `RETURNDATASIZE` to push zero for free (2 gas) — it returns 0 before any external call has been made. You'll still see `RETURNDATASIZE` used this way in older Solady code. Post-Shanghai, `PUSH0` is the clean way.

```
Pre-Shanghai:   PUSH1 0x00     →  3 gas, 2 bytes of bytecode
Pre-Shanghai:   RETURNDATASIZE →  2 gas, 1 byte (hack: returns 0 before any call)
Post-Shanghai:  PUSH0          →  2 gas, 1 byte (clean, intentional)
```

**Signed vs unsigned:** Notice SDIV, SMOD, SLT, SGT, SAR — the "S" prefix means **signed**. The EVM treats all stack values as unsigned 256-bit integers by default. Signed operations interpret the same bits using two's complement. In DeFi, you'll encounter signed math in Uniswap V3's tick calculations and Balancer's fixed-point `int256` math.

**Opcodes you'll encounter most in DeFi assembly:**

```
Reading/writing:     MLOAD, MSTORE, SLOAD, SSTORE, TLOAD, TSTORE, CALLDATALOAD
Math:               ADD, MUL, SUB, DIV, MOD, ADDMOD, MULMOD, EXP
Bit manipulation:   AND, OR, SHL, SHR, NOT
Comparison:         LT, GT, EQ, ISZERO
External calls:     CALL, STATICCALL, DELEGATECALL
Control:            RETURN, REVERT
Context:            CALLER, CALLVALUE
Hashing:            KECCAK256
```

**What you can safely skip for now:** `BLOCKHASH` (rarely used in DeFi), `COINBASE`/`PREVRANDAO` (validator-related), `BLOBBASEFEE` (L2-specific), `PC` (deprecated pattern). You'll encounter these if you need them, but they're not in the critical path.

> **SELFDESTRUCT is deprecated.** [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780) (Dencun fork, March 2024) neutered `SELFDESTRUCT` — it only works within the same transaction as contract creation. It no longer deletes contract code or transfers remaining balance. Don't use it in new code.

**Precompiled contracts:**

The EVM has special contracts at addresses `0x01` through `0x0a` that implement expensive operations in native code (not EVM bytecode). You call them with `STATICCALL` like any other contract, but they execute much faster.

| Address | Precompile | Gas | DeFi Relevance |
|---------|-----------|-----|----------------|
| `0x01` | ecrecover | 3000 | **High** — Every `permit()`, `ecrecover()` call, and EIP-712 signature verification |
| `0x02` | SHA-256 | 60+12/word | Low — Bitcoin bridging |
| `0x03` | RIPEMD-160 | 600+120/word | Low — Bitcoin addresses |
| `0x04` | identity (datacopy) | 15+3/word | Medium — Cheap memory copy |
| `0x05` | modexp | variable | Medium — RSA verification |
| `0x06`-`0x08` | BN256 curve ops | 150-45000 | High — ZK proof verification (Tornado Cash, rollups) |
| `0x09` | Blake2 | 0+f(rounds) | Low — Zcash/Filecoin |
| `0x0a` | KZG point evaluation | 50000 | High — Blob verification (EIP-4844) |

The key one for DeFi: **ecrecover** (`0x01`). Every time you call `ECDSA.recover()` or use `permit()`, Solidity compiles it to a `STATICCALL` to address `0x01`. At 3,000 gas per call, signature verification is relatively expensive — this is why batching permit signatures matters in gas-sensitive paths.

💻 **Quick Try:** ([evm.codes playground](https://www.evm.codes/playground))

Go to [evm.codes](https://www.evm.codes/) and look up the `ADD` opcode. Notice:
- **Stack input:** `a | b` (takes two values)
- **Stack output:** `a + b` (pushes one value)
- **Gas:** 3
- It wraps on overflow (no revert!) — this is why Solidity 0.8+ adds overflow checks

Now look up `SSTORE`. Compare the gas cost (20,000 for a fresh write!) to `ADD` (3). This ratio — storage is ~6,600x more expensive than arithmetic — drives almost every gas optimization pattern in DeFi.

---

## Cost & Context

<a id="gas-model"></a>
### 💡 Concept: Gas Model — Why Things Cost What They Cost

**Why this matters:** You've optimized gas in Solidity using patterns (storage packing, unchecked blocks, custom errors). Now you'll understand *why* those patterns work at the opcode level. Gas costs aren't arbitrary — they reflect the computational and state burden each operation places on Ethereum nodes.

**The gas schedule in tiers:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        EVM Gas Tiers                            │
├──────────────┬───────────┬──────────────────────────────────────┤
│ Tier         │ Gas Cost  │ Opcodes                              │
├──────────────┼───────────┼──────────────────────────────────────┤
│ Zero         │ 0         │ STOP, RETURN, REVERT                 │
│ Base         │ 2         │ ADDRESS, CALLER, CALLVALUE,          │
│              │           │ CALLDATASIZE, TIMESTAMP, CHAINID     │
│ Very Low     │ 3         │ ADD, SUB, NOT, LT, GT, EQ,          │
│              │           │ PUSH, DUP, SWAP, MLOAD, MSTORE      │
│ Low          │ 5         │ MUL, DIV, MOD, SHL, SHR, SAR        │
│ Mid          │ 8         │ JUMP, ADDMOD, MULMOD                 │
│ High         │ 10        │ JUMPI, EXP (base)                    │
│ Transient    │ 100       │ TLOAD, TSTORE                        │
│ Storage Read │ 100-2100  │ SLOAD (warm: 100, cold: 2100)        │
│ Storage Write│ 2900-20000│ SSTORE (update: 2900+, new: 20000)   │
│ Hashing      │ 30+       │ KECCAK256 (30 + 6 per 32-byte word) │
│ External Call│ 100-2600+ │ CALL, STATICCALL, DELEGATECALL       │
│ Logging      │ 375+      │ LOG0 (375 + 8 per byte + topic cost) │
│ Create       │ 32000+    │ CREATE, CREATE2                      │
└──────────────┴───────────┴──────────────────────────────────────┘
```

**The key insight:** There's a ~6,600x cost difference between the cheapest and most expensive common operations (ADD at 3 gas vs SSTORE at 20,000 gas). This single fact explains most gas optimization patterns:

- **Why `unchecked` saves gas:** Checked arithmetic adds comparison opcodes (LT/GT at 3 gas each) and conditional jumps (JUMPI at 10 gas) around every operation. For a simple `++i`, that's ~20 gas overhead per iteration
- **Why custom errors save gas:** `require(condition, "long string")` stores the string in bytecode and copies it to memory on revert. `revert CustomError()` encodes a 4-byte selector — less memory, less bytecode
- **Why storage packing matters:** One SLOAD (100-2100 gas) reads a full 32-byte slot. Packing two `uint128` values into one slot means one read instead of two
- **Why transient storage exists:** TSTORE/TLOAD at 100 gas each vs SSTORE/SLOAD at 2900-20000/100-2100 gas. For same-transaction data (reentrancy guards, flash accounting), transient storage is 29-200x cheaper to write

💻 **Quick Try:**

Deploy this in Remix and call both functions. Compare the gas costs in the transaction receipts:

```solidity
contract GasCompare {
    uint256 public stored;

    function writeStorage(uint256 val) external { stored = val; }
    function writeMemory(uint256 val) external pure returns (uint256) {
        uint256 result;
        assembly { mstore(0x80, val) result := mload(0x80) }
        return result;
    }
}
```

Call `writeStorage(42)` first, then `writeMemory(42)`. The storage write will cost ~22,000+ gas (cold SSTORE) vs ~100 gas for the memory round-trip. That's a ~200x difference you can see directly.

🏗️ **Real usage:**

This is why Uniswap V4 moved to flash accounting with transient storage. In V3, every swap updates `reserve0` and `reserve1` in storage — two SSTOREs at 5,000+ gas each. In V4, deltas are tracked in transient storage (TSTORE at 100 gas each), with a single settlement at the end. The gas savings directly come from the opcode cost difference.

See: [Uniswap V4 PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) — the `_accountDelta` function uses transient storage

---

<a id="warm-cold"></a>
#### 🔍 Deep Dive: EIP-2929 Warm/Cold Access

**The problem:**

Before [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929) (Berlin fork, April 2021), SLOAD cost a flat 800 gas and account access was 700 gas. This was exploitable — an attacker could force many cold storage reads for relatively little gas, slowing down nodes.

**The solution — access lists:**

EIP-2929 introduced **warm** and **cold** access:

```
First access to a storage slot or address = COLD = expensive
  └── SLOAD: 2100 gas
  └── Account access (CALL/BALANCE/etc.): 2600 gas

Subsequent access in same transaction = WARM = cheap
  └── SLOAD: 100 gas
  └── Account access: 100 gas
```

**Visual — accessing the same slot twice in one function:**

```
                          Gas Cost
                          ────────
SLOAD(slot 0)    ──────►  2100  (cold — first time)
SLOAD(slot 0)    ──────►   100  (warm — already accessed)
                          ────
                  Total:  2200

vs. two different slots:

SLOAD(slot 0)    ──────►  2100  (cold)
SLOAD(slot 1)    ──────►  2100  (cold)
                          ────
                  Total:  4200
```

**Why this matters for DeFi:**

Multi-token operations (swaps, multi-collateral lending) access many different storage slots and addresses. The cold/warm distinction means:

1. **Reading the same state twice is cheap** — the second read is only 100 gas. Don't cache a storage read in a local variable just to save 100 gas if it hurts readability
2. **Accessing many different contracts is expensive** — each new address costs 2600 gas for the first interaction. Aggregators routing through 5 DEXes pay ~13,000 gas just in cold access costs
3. **Access lists ([EIP-2930](https://eips.ethereum.org/EIPS/eip-2930))** — You can pre-declare which addresses and slots you'll access, paying a discounted rate upfront. Useful for complex DeFi transactions

> **Practical tip:** When you see `forge snapshot` gas differences between test runs, remember that test setup may warm slots. Use `vm.record()` and `vm.accesses()` in Foundry to see exactly which slots are accessed.

---

<a id="memory-expansion"></a>
#### 🔍 Deep Dive: Memory Expansion Cost

**The problem:** Memory is dynamically sized — it starts at zero bytes and grows as needed. But growing memory gets progressively more expensive.

**The cost formula:**

```
memory_cost = 3 * words + (words² / 512)

where words = ceil(memory_size / 32)
```

The `words²` term means memory cost grows **quadratically**. For small amounts of memory (a few hundred bytes), it's negligible. For large amounts, it becomes dominant:

```
Memory Size    Words    Cost (gas)
───────────    ─────    ──────────
32 bytes       1        3
64 bytes       2        6
256 bytes      8        24
1 KB           32       98
4 KB           128      424
32 KB          1024     5120
1 MB           32768    2,145,386  ← prohibitively expensive
```

**Visualizing the quadratic curve:**

```
Gas cost
  ▲
  │                                              ╱
  │                                           ╱
  │                                        ╱
  │                                     ╱
  │                                  ╱      ← quadratic (words²/512)
  │                              ╱             dominates here
  │                          ╱
  │                      ╱
  │               ··╱···
  │          ···╱··
  │     ···╱··    ← linear (3*words)
  │ ··╱···           dominates here
  │╱··
  └──────────────────────────────────────────► Memory size
  0     256B    1KB     4KB     32KB    1MB
        ↑
        Sweet spot: most DeFi operations
        stay under ~1KB of memory usage
```

The takeaway: keep memory usage bounded. Most DeFi operations (ABI encoding a few arguments, decoding return data) use well under 1KB and pay negligible expansion costs. The danger zone is dynamic arrays or unbounded loops that grow memory.

**Why this matters:**

- **The free memory pointer** (stored at memory position `0x40`): Solidity tracks the next available memory location. Every `new`, `abi.encode`, or dynamic array allocation moves this pointer forward. The quadratic cost means careless memory allocation in a loop can get very expensive
- **ABI encoding in memory:** When calling external functions, Solidity encodes arguments in memory. Complex structs and arrays expand memory significantly
- **returndata copying:** `RETURNDATACOPY` copies return data to memory. Large return values (like arrays from view functions) expand memory

> This is covered in depth in Module 2 (Memory & Calldata). For now, the key takeaway: memory is cheap for small amounts, expensive for large amounts, and the cost is non-linear.

---

<a id="63-64-rule"></a>
#### The 63/64 Rule

**What it is:** When making an external call (CALL, STATICCALL, DELEGATECALL), the EVM only forwards **63/64** of the remaining gas to the called contract. The calling contract retains 1/64 as a reserve.

> Introduced in [EIP-150](https://eips.ethereum.org/EIPS/eip-150) (Tangerine Whistle, 2016) to prevent call-stack depth attacks.

**Why it matters for DeFi:**

Each level of nesting loses ~1.6% of gas. For a chain of 10 nested calls (common in aggregator → router → pool → callback patterns), you lose about 15% of gas:

```
Available gas at each depth:
Depth 0:  1,000,000  (start)
Depth 1:    984,375  (× 63/64)
Depth 2:    969,000
Depth 3:    953,860
...
Depth 10:   854,520  (~15% lost)
```

Practical implications:
- **Flash loan callbacks** that do complex operations (multi-hop swaps, collateral restructuring) must account for gas loss
- **Deeply nested proxy patterns** (proxy → implementation → library → callback) compound the loss
- Gas estimation for complex DeFi transactions must account for 63/64 at each call boundary

#### 🔗 DeFi Pattern Connection: Gas Budgets

**Where gas costs directly shape protocol design:**

1. **AMM swap cost budget** — A Uniswap V3 swap costs ~130,000-180,000 gas. Here's where it goes:

```
Uniswap V3 Swap — Approximate Gas Budget
─────────────────────────────────────────
Cold access (pool contract)      2,600
SLOAD pool state (cold)          2,100   ← slot0: sqrtPriceX96, tick, etc.
SLOAD liquidity (cold)           2,100
Tick crossing (if needed)       ~5,000   ← additional SLOADs
Compute new price (math)        ~1,500   ← mulDiv, shifts, comparisons
SSTORE updated state            ~5,000   ← warm updates to pool state
Transfer token in               ~7,000   ← ERC-20 balanceOf + transfer
Transfer token out              ~7,000   ← ERC-20 balanceOf + transfer
Callback execution             ~10,000   ← swapCallback with msg.sender check
EVM overhead (memory, jumps)    ~3,000
─────────────────────────────────────────
Approximate total:            ~45,000-55,000 (internal call cost only)
+ External call overhead, cold access to router, calldata, etc.
= ~130,000-180,000 total
```

This is why every gas optimization in an AMM matters — a 2,000-gas saving is ~1-1.5% of the entire swap.

2. **Liquidation bots** — Aave V3 liquidations cost ~300,000-500,000 gas. MEV searchers compete on gas efficiency — 5,000 gas less can mean winning the priority fee auction

3. **Batch operations** — Protocols that batch (Permit2, multicall) amortize cold access costs. The first interaction with a contract costs 2,600 gas (cold), but every subsequent call in the same transaction is 100 gas (warm)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Why is SSTORE so expensive?"**
   - Good answer: "It writes to the world state trie, which every node must store permanently. The 20,000 gas for a new slot reflects the storage burden on all nodes"
   - Great answer: Adds EIP-2929 warm/cold distinction, refund mechanics, and why EIP-3529 reduced SSTORE refunds

2. **"When is assembly-level gas optimization worth it?"**
   - Good answer: "Hot paths with high call frequency — DEX swaps, liquidation bots, frequently-called view functions"
   - Great answer: "It depends on the gas savings vs. the audit cost. A 200-gas saving in a function called once per user interaction isn't worth reduced readability. A 2,000-gas saving in a function called by every MEV searcher on every block is worth it"

**Interview red flags:**
- 🚩 Not knowing the order-of-magnitude difference between memory and storage costs
- 🚩 Thinking all assembly is gas-optimal (Solidity's optimizer is often good enough)
- 🚩 Not mentioning warm/cold access when discussing gas costs

**Pro tip:** When asked about gas optimization in interviews, always frame it as a cost-benefit analysis: gas saved vs. audit complexity introduced. Teams value engineers who know *when* to use assembly, not just *how*.

---

<a id="execution-context"></a>
### 💡 Concept: Execution Context at the Opcode Level

**Why this matters:** Every Solidity global variable you've used (`msg.sender`, `msg.value`, `block.timestamp`) maps to a single opcode. Understanding these opcodes directly prepares you for reading and writing assembly.

**The mapping:**

| Solidity | Yul Built-in | Opcode | Gas | Returns |
|----------|-------------|--------|-----|---------|
| `msg.sender` | `caller()` | CALLER | 2 | Address that called this contract |
| `msg.value` | `callvalue()` | CALLVALUE | 2 | Wei sent with the call |
| `msg.data` | `calldataload(offset)` | CALLDATALOAD | 3 | 32 bytes from calldata at offset |
| `msg.sig` | First 4 bytes of calldata | CALLDATALOAD(0) | 3 | Function selector |
| `msg.data.length` | `calldatasize()` | CALLDATASIZE | 2 | Byte length of calldata |
| `block.timestamp` | `timestamp()` | TIMESTAMP | 2 | Current block timestamp |
| `block.number` | `number()` | NUMBER | 2 | Current block number |
| `block.chainid` | `chainid()` | CHAINID | 2 | Chain ID |
| `block.basefee` | `basefee()` | BASEFEE | 2 | Current base fee |
| `block.prevrandao` | `prevrandao()` | PREVRANDAO | 2 | Previous RANDAO value |
| `tx.origin` | `origin()` | ORIGIN | 2 | Transaction originator |
| `tx.gasprice` | `gasprice()` | GASPRICE | 2 | Gas price of transaction |
| `address(this)` | `address()` | ADDRESS | 2 | Current contract address |
| `address(x).balance` | `balance(x)` | BALANCE | 100/2600 | Balance of address x |
| `gasleft()` | `gas()` | GAS | 2 | Remaining gas |
| `this.code.length` | `codesize()` | CODESIZE | 2 | Size of contract code |

**Reading these in Yul:**

```solidity
function getExecutionContext() external view returns (
    address sender,
    uint256 value,
    uint256 ts,
    uint256 blockNum,
    uint256 chain
) {
    assembly {
        sender := caller()
        value := callvalue()
        ts := timestamp()
        blockNum := number()
        chain := chainid()
    }
}
```

Each of these Yul built-ins maps 1:1 to a single opcode. No function call overhead, no ABI encoding — just a 2-gas opcode that pushes a value onto the stack.

> **Connection to Parts 1-3:** You've used `msg.sender` in access control (P1M2), `msg.value` in vault deposits (P1M4), `block.timestamp` in interest accrual (P2M6), and `block.chainid` in permit signatures (P1M3). Now you know what's underneath — a single 2-gas opcode each time.

**Calldata: How input arrives**

When a function is called, the input data arrives as a flat byte array. The first 4 bytes are the **function selector** (keccak256 hash of the function signature, truncated). The remaining bytes are the ABI-encoded arguments.

```
Calldata layout for transfer(address to, uint256 amount):

Offset:  0x00                0x04                0x24                0x44
         ┌───────────────────┬───────────────────┬───────────────────┐
         │ a9059cbb          │ 000...recipient   │ 000...amount      │
         │ (4 bytes)         │ (32 bytes)        │ (32 bytes)        │
         │ selector          │ arg 0 (address)   │ arg 1 (uint256)   │
         └───────────────────┴───────────────────┴───────────────────┘
```

Reading calldata in Yul:

```solidity
assembly {
    let selector := shr(224, calldataload(0))   // First 4 bytes
    let arg0 := calldataload(4)                  // First argument (32 bytes at offset 4)
    let arg1 := calldataload(36)                 // Second argument (32 bytes at offset 36)
}
```

`calldataload(offset)` reads 32 bytes from calldata starting at `offset`. To get just the 4-byte selector, we load 32 bytes from offset 0 and shift right by 224 bits (256 - 32 = 224), discarding the extra 28 bytes.

💻 **Quick Try:**

Add this to a contract in Remix, call it, and verify the selector matches:

```solidity
function readSelector() external pure returns (bytes4) {
    bytes4 sel;
    assembly { sel := shr(224, calldataload(0)) }
    return sel;
}
// Should return 0xc2b12a73 — the selector of readSelector() itself
```

> **Note:** This is a brief introduction. Module 2 (Memory & Calldata) and Module 4 (Control Flow & Functions) go deep on calldata handling, ABI encoding, and function selector dispatch.

💻 **Quick Try:**

Deploy this in Remix and call it with some ETH. Compare the return values with what Remix shows you:

```solidity
function whoAmI() external payable returns (
    address sender, uint256 value, uint256 ts
) {
    assembly {
        sender := caller()
        value := callvalue()
        ts := timestamp()
    }
}
```

Notice: the assembly version does exactly what `msg.sender`, `msg.value`, `block.timestamp` do — but now you see the opcodes underneath.

#### 🔗 DeFi Pattern Connection

**Where context opcodes matter in DeFi:**

1. **Proxy contracts** — `delegatecall` preserves the original `caller()` and `callvalue()`. This is why proxy forwarding works — the implementation contract sees the original user, not the proxy. The assembly in OpenZeppelin's proxy reads `calldatasize()` and `calldatacopy()` to forward the entire calldata
2. **Timestamp-dependent logic** — Interest accrual (`block.timestamp`), oracle staleness checks, governance timelocks all use `TIMESTAMP`. In Yul: `timestamp()`
3. **Chain-aware contracts** — Multi-chain deployments use `chainid()` to prevent signature replay attacks across chains. Permit ([EIP-2612](https://eips.ethereum.org/EIPS/eip-2612)) includes chain ID in the domain separator
4. **Gas metering** — MEV bots and gas-optimized contracts use `gas()` to measure remaining gas and make decisions (e.g., "do I have enough gas to complete this liquidation?")

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What's the difference between `msg.sender` and `tx.origin`?"**
   - Good answer: "`msg.sender` is the immediate caller (CALLER opcode), `tx.origin` is the EOA that initiated the transaction (ORIGIN opcode). They differ when contracts call other contracts"
   - Great answer: "Never use `tx.origin` for authorization — it breaks composability with smart contract wallets (Gnosis Safe, ERC-4337 accounts) and is vulnerable to phishing attacks where a malicious contract tricks users into calling it"

2. **"How does `delegatecall` affect `msg.sender`?"**
   - Good answer: "`delegatecall` preserves the original `caller()` and `callvalue()`. The implementation runs in the caller's storage context"
   - Great answer: "This is what makes the proxy pattern work — the user interacts with the proxy, `delegatecall` forwards to the implementation, but `msg.sender` still points to the user. This also means the implementation must never assume `address(this)` is its own address"

**Interview red flags:**
- 🚩 Using `tx.origin` for access control
- 🚩 Not understanding that `delegatecall` runs in the caller's storage context

---

## Writing Assembly

<a id="first-yul"></a>
### 💡 Concept: Your First Yul

**Why this matters:** Yul is the inline assembly language for the EVM. It sits between raw opcodes and Solidity — you get explicit control over the stack (via named variables) without writing raw bytecode. Every `assembly { }` block you've seen in Parts 1-3 is Yul.

**The basics:**

```solidity
function example(uint256 x) external pure returns (uint256 result) {
    assembly {
        // Variables: let name := value
        let doubled := mul(x, 2)

        // Assignment: name := value
        result := add(doubled, 1)
    }
}
```

**Yul syntax reference:**

| Syntax | Meaning | Example |
|--------|---------|---------|
| `let x := val` | Declare variable | `let sum := add(a, b)` |
| `x := val` | Assign to variable | `sum := mul(sum, 2)` |
| `if condition { }` | Conditional (no else!) | `if iszero(x) { revert(0, 0) }` |
| `switch val case X { } case Y { } default { }` | Multi-branch | `switch lt(x, 10) case 1 { ... }` |
| `for { init } cond { post } { body }` | Loop | `for { let i := 0 } lt(i, n) { i := add(i, 1) } { ... }` |
| `function name(args) -> returns { }` | Internal function | `function min(a, b) -> r { r := ... }` |
| `leave` | Exit current function | Similar to `return` in other languages |

**Critical differences from Solidity:**

1. **No overflow checks** — `add(type(uint256).max, 1)` wraps to 0, silently. No revert. You must add your own checks if needed
2. **No type safety** — Everything is a `uint256`. An address, a bool, a byte — all treated as 256-bit words. You must handle type conversions yourself
3. **No `else`** — Yul's `if` has no `else` branch. Use `switch` for multi-branch logic, or negate the condition
4. **`if` treats any nonzero value as true** — `if 1 { }` executes. `if 0 { }` doesn't. No explicit `true`/`false`
5. **Function return values use `-> name` syntax** — `function foo(x) -> result { result := x }`. The variable `result` is implicitly returned

**A quick `for` loop example:**

```solidity
function sumUpTo(uint256 n) external pure returns (uint256 total) {
    assembly {
        // for { init } condition { post-iteration } { body }
        for { let i := 1 } lt(i, add(n, 1)) { i := add(i, 1) } {
            total := add(total, i)
        }
    }
}
// sumUpTo(5) → 15  (1 + 2 + 3 + 4 + 5)
```

Note the C-like structure: `for { let i := 0 } lt(i, n) { i := add(i, 1) } { body }`. No `i++` shorthand — everything is explicit. Module 4 (Control Flow & Functions) covers loops in depth, including gas-efficient loop patterns.

**How Yul variables map to the stack:**

When you write `let x := 5`, the Yul compiler pushes 5 onto the stack and tracks the stack position for `x`. When you later use `x`, it knows which stack position to reference (via DUP). You never manage the stack directly — Yul handles the bookkeeping.

```
Your Yul:                   What the compiler does:
─────────                   ──────────────────────
let a := 5                  PUSH 5
let b := 3                  PUSH 3
let sum := add(a, b)        DUP2, DUP2, ADD
```

This is why Yul is preferred over raw bytecode — you get named variables and the compiler manages DUP/SWAP for you, but you still control exactly which opcodes execute.

**Returning values from assembly:**

Assembly blocks can assign to Solidity return variables by name:

```solidity
function getMax(uint256 a, uint256 b) external pure returns (uint256 result) {
    assembly {
        // Solidity's return variable 'result' is accessible in assembly
        switch gt(a, b)
        case 1 { result := a }
        default { result := b }
    }
}
```

**Reverting from assembly:**

```solidity
assembly {
    // revert(memory_offset, memory_size)
    // With no error data:
    revert(0, 0)

    // With a custom error selector:
    mstore(0, 0x08c379a0)  // Error(string) selector — but this is the Solidity pattern
    // ... encode error data in memory ...
    revert(offset, size)
}
```

> The revert pattern is covered in depth in Module 2 (Memory) since it requires encoding data in memory. For now: `revert(0, 0)` is the minimal revert with no data.

---

<a id="intermediate-yul"></a>
#### 🎓 Intermediate Example: Writing Functions in Assembly

Before the exercises, let's build a small but realistic example — a `require`-like pattern in assembly:

```solidity
contract AssemblyGuard {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function onlyOwnerAction(uint256 value) external view returns (uint256) {
        assembly {
            // Load owner from storage slot 0
            let storedOwner := sload(0)

            // Compare caller with owner — revert if not equal
            if iszero(eq(caller(), storedOwner)) {
                // Store the error selector for Unauthorized()
                // bytes4(keccak256("Unauthorized()")) = 0x82b42900
                mstore(0, 0x82b42900)
                revert(0x1c, 0x04)  // revert with 4-byte selector
            }

            // If we get here, caller is the owner
            // Return value * 2 (simple example)
            mstore(0, mul(value, 2))
            return(0, 0x20)
        }
    }
}
```

**What's happening:**

1. `sload(0)` — reads the first storage slot (where `owner` is stored)
2. `eq(caller(), storedOwner)` — compares addresses (returns 1 if equal, 0 if not)
3. `iszero(...)` — inverts the result (we want to revert when NOT equal)
4. `mstore(0, 0x82b42900)` — writes the error selector to memory
5. `revert(0x1c, 0x04)` — reverts with 4 bytes starting at memory offset 0x1c (where the selector bytes actually sit within the 32-byte word)

> **Why `0x1c` and not `0x00`?** When you `mstore(0, value)`, it writes a full 32-byte word. The 4-byte selector `0x82b42900` is right-aligned in the 32-byte word, meaning it sits at bytes 28-31 (offset 0x1c = 28). `revert(0x1c, 0x04)` reads those 4 bytes. This memory layout is covered in detail in Module 2.

🏗️ **Real usage:**

This is exactly the pattern used in Solady's [Ownable.sol](https://github.com/Vectorized/solady/blob/main/src/auth/Ownable.sol). The entire ownership check is done in assembly for minimal gas. Compare it to [OpenZeppelin's Ownable.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol) — the logic is identical, but the assembly version skips Solidity's overhead (ABI encoding the error, checked comparisons).

#### 🔗 DeFi Pattern Connection

**Where hand-written Yul appears in production DeFi:**

1. **Math libraries** — Solady's `FixedPointMathLib`, Uniswap's `FullMath` and `TickMath` are written in assembly for gas efficiency on hot math paths (every swap, every price calculation)
2. **Proxy forwarding** — OpenZeppelin's `Proxy.sol` uses assembly to `calldatacopy` the entire input, `delegatecall` to the implementation, then `returndatacopy` the result back. No Solidity wrapper can do this without ABI encoding overhead
3. **Permit decoding** — Permit2 and other gas-sensitive signature paths decode calldata in assembly to avoid Solidity's ABI decoder overhead
4. **Custom error encoding** — Assembly `mstore` + `revert` for error selectors avoids Solidity's string encoding, saving ~200 gas per revert path

**The pattern:** Assembly in production DeFi concentrates in two places: (1) math-heavy hot paths called millions of times, and (2) low-level plumbing (proxies, calldata forwarding) where Solidity can't express the pattern at all.

---

<a id="bytecode"></a>
### 💡 Concept: Contract Bytecode — Creation vs Runtime

**Why this matters:** When you deploy a contract, the EVM doesn't just store your code. It first executes **creation code** (which runs once and includes the constructor), which then returns **runtime code** (the actual contract bytecode stored on-chain). Understanding this split is essential for Module 8 (Pure Yul Contracts) where you'll build both from scratch.

**The two phases:**

```
Deployment Transaction
        │
        ▼
┌──────────────────────┐
│   CREATION CODE      │    Runs once during deployment:
│                      │    1. Execute constructor logic
│   constructor()      │    2. Copy runtime code to memory
│   CODECOPY           │    3. RETURN runtime code → EVM stores it
│   RETURN             │
└──────────────────────┘
        │
        ▼
┌──────────────────────┐
│   RUNTIME CODE       │    Stored on-chain at contract address:
│                      │    1. Function selector dispatch
│   receive()          │    2. All function bodies
│   fallback()         │    3. Internal functions, modifiers
│   function foo()     │
│   function bar()     │
└──────────────────────┘
```

**What `forge inspect` shows you:**

```bash
# The full creation code (constructor + deployment logic)
forge inspect MyContract bytecode

# Just the runtime code (what's stored on-chain)
forge inspect MyContract deployedBytecode

# The ABI
forge inspect MyContract abi

# Storage layout (which variables live at which slots)
forge inspect MyContract storageLayout
```

💻 **Quick Try:**

```bash
# From the workspace directory:
forge inspect src/part1/module1/exercise1-share-math/ShareMath.sol:ShareCalculator bytecode | head -c 80
```

You'll see a hex string starting with something like `608060405234...`. This is the creation code bytecode. Every Solidity contract starts with `6080604052` — this is `PUSH1 0x80 PUSH1 0x40 MSTORE`, which initializes the free memory pointer to 0x80. You'll learn why in Module 2.

**Key opcodes in the creation/runtime split:**

| Opcode | Purpose in Deployment |
|--------|-----------------------|
| `CODECOPY(destOffset, offset, size)` | Copy runtime code from creation code into memory |
| `RETURN(offset, size)` | Return memory contents to the EVM — this becomes the deployed code |
| `CODESIZE` | Get length of currently executing code (useful for computing runtime code offset) |

The creation code essentially says: "Copy bytes X through Y of myself into memory, then RETURN that memory region." The EVM stores whatever is returned as the contract's runtime code.

> **Brief for now:** Module 8 (Pure Yul Contracts) goes deep into writing creation code and runtime code by hand using Yul's `object` notation. For now, just know that every contract has two bytecode forms and that `forge inspect` lets you examine them.

<a id="how-to-study"></a>
📖 **How to Study EVM Bytecode:**

When you want to understand how a contract or opcode works:

1. **Start with [evm.codes](https://www.evm.codes/)** — Look up the opcode, read its stack inputs/outputs, try the playground
2. **Use Remix debugger** — Deploy a minimal contract, step through opcodes, watch the stack change
3. **Use `forge inspect`** — Examine bytecode, storage layout, and ABI for any contract in your project
4. **Read Solady's source** — The comments in [Solady](https://github.com/Vectorized/solady) are some of the best EVM documentation available — they explain *why* each assembly pattern works
5. **Use [Dedaub](https://library.dedaub.com/)** — Paste deployed contract addresses to see decompiled code with inferred variable names

#### 🔗 DeFi Pattern Connection

**Where bytecode matters in DeFi:**

1. **CREATE2 deterministic addresses** — Factory contracts (Uniswap V2/V3 pair factories, clones) use `CREATE2` with the creation code hash to compute deterministic addresses. Understanding bytecode is essential for these patterns
2. **Minimal proxies (EIP-1167)** — The clone pattern deploys a tiny runtime bytecode (~45 bytes) that just does `DELEGATECALL`. The creation code is handcrafted to be as small as possible
3. **Bytecode verification** — Etherscan verification, and governance proposals that check "is this the right implementation," compare deployed bytecode against expected bytecode

---

<a id="exercise1"></a>
## 🎯 Build Exercise: YulBasics

**Workspace:** [`src/part4/module1/exercise1-yul-basics/YulBasics.sol`](../workspace/src/part4/module1/exercise1-yul-basics/YulBasics.sol) | [`test/.../YulBasics.t.sol`](../workspace/test/part4/module1/exercise1-yul-basics/YulBasics.t.sol)

Implement basic functions using **only inline assembly**. No Solidity arithmetic, no Solidity `if` statements — everything inside `assembly { }` blocks.

**What you'll implement:**
1. `addNumbers(uint256 a, uint256 b)` — add two numbers using the `add` opcode (wraps on overflow — no checks)
2. `max(uint256 a, uint256 b)` — return the larger value using `gt` and conditional assignment
3. `clamp(uint256 value, uint256 min, uint256 max)` — bound a value to a range
4. `getContext()` — return `(msg.sender, msg.value, block.timestamp, block.chainid)` by reading context opcodes
5. `extractSelector(bytes calldata data)` — extract the first 4 bytes of arbitrary calldata

**🎯 Goal:** Build muscle memory for basic Yul syntax — `let`, `add`, `mul`, `gt`, `lt`, `eq`, `iszero`, `caller()`, `callvalue()`, `timestamp()`, `chainid()`, `calldataload()`, `shr()`.

Run: `forge test --match-contract YulBasicsTest -vvv`

---

<a id="exercise2"></a>
## 🎯 Build Exercise: GasExplorer

**Workspace:** [`src/part4/module1/exercise2-gas-explorer/GasExplorer.sol`](../workspace/src/part4/module1/exercise2-gas-explorer/GasExplorer.sol) | [`test/.../GasExplorer.t.sol`](../workspace/test/part4/module1/exercise2-gas-explorer/GasExplorer.t.sol)

Measure and compare gas costs at the opcode level. Some functions you'll implement in assembly, others combine both Solidity and assembly to observe the difference.

**What you'll implement:**
1. `measureSloadCold()` / `measureSloadWarm()` — use the `gas()` opcode to measure the cost of cold vs warm storage reads
2. `addChecked(uint256, uint256)` vs `addAssembly(uint256, uint256)` — Solidity checked addition vs assembly `add`, tests compare gas
3. `measureMemoryWrite(uint256)` vs `measureStorageWrite(uint256)` — write to memory vs storage, measure and return gas used

**🎯 Goal:** Internalize the gas cost hierarchy through direct measurement. After this exercise, you'll intuitively know *why* certain patterns are expensive.

Run: `forge test --match-contract GasExplorerTest -vvv`

---

<a id="summary"></a>
## 📋 Summary: EVM Fundamentals

**✓ Covered:**
- The EVM is a stack machine — 256-bit words, LIFO, max depth 1024
- Opcodes organized by category — arithmetic, comparison, bitwise, memory, storage, flow, system
- Gas model — tiers from 2 gas (context opcodes) to 20,000 gas (new storage write), with EIP-2929 warm/cold access and quadratic memory expansion
- The 63/64 rule — external calls retain 1/64 gas at each depth
- Execution context — every Solidity global maps to a 2-3 gas opcode
- Calldata layout — selector (4 bytes) + ABI-encoded arguments
- PUSH0 (EIP-3855) — the newest stack opcode, replaced the RETURNDATASIZE trick
- Precompiled contracts — special native contracts at `0x01`-`0x0a`, ecrecover (`0x01`) powers every permit/signature
- Yul basics — `let`, `if`, `switch`, `for`, named variables mapped to stack by the compiler
- Contract bytecode — creation code (runs once) vs runtime code (stored on-chain)

**Key numbers to remember:**
- ADD/SUB: 3 gas | MUL/DIV: 5 gas | SLOAD cold: 2100 gas | SSTORE new: 20,000 gas
- TLOAD/TSTORE: 100 gas | KECCAK256: 30 + 6/word | CALL warm: 100 gas

**Next:** [Module 2 — Memory & Calldata](2-memory-calldata.md) — deep dive into mload/mstore, the free memory pointer, ABI encoding by hand, and returndata handling.

---

<a id="resources"></a>
## 📚 Resources

### Essential References
- [evm.codes](https://www.evm.codes/) — Interactive opcode reference with gas costs, stack effects, and playground
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) — Formal specification (Appendix H has the opcode table)
- [Yul Documentation](https://docs.soliditylang.org/en/latest/yul.html) — Official Solidity docs on Yul syntax

### EIPs Referenced
- [EIP-150](https://eips.ethereum.org/EIPS/eip-150) — 63/64 gas forwarding rule (Tangerine Whistle)
- [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) — Transient storage: TLOAD/TSTORE at 100 gas (Dencun fork)
- [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929) — Cold/warm access costs (Berlin fork)
- [EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) — Access list transaction type (Berlin fork)
- [EIP-3529](https://eips.ethereum.org/EIPS/eip-3529) — Reduced SSTORE refunds (London fork)
- [EIP-3855](https://eips.ethereum.org/EIPS/eip-3855) — PUSH0 opcode (Shanghai fork)
- [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780) — SELFDESTRUCT deprecation (Dencun fork)

### Production Code to Study
- [Solady](https://github.com/Vectorized/solady) — Gas-optimized Solidity with heavy assembly usage
- [OpenZeppelin Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol) — Assembly-based delegatecall forwarding
- [Uniswap V4 PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) — Transient storage for flash accounting

### Hands-On
- [EVM From Scratch](https://github.com/w1nt3r-eth/evm-from-scratch) — Build your own EVM in your language of choice. Excellent for deepening understanding of opcode execution
- [EVM Puzzles](https://github.com/fvictorio/evm-puzzles) — Solve puzzles using raw EVM bytecode

### Tools
- [Remix Debugger](https://remix.ethereum.org/) — Step through opcodes, watch the stack
- [evm.codes Playground](https://www.evm.codes/playground) — Interactive opcode experimentation
- [forge inspect](https://book.getfoundry.sh/reference/forge/forge-inspect) — Examine bytecode, ABI, storage layout
- [Dedaub Contract Library](https://library.dedaub.com/) — Decompile deployed contracts

---

**Navigation:** [Previous: Part 4 Overview](README.md) | [Next: Module 2 — Memory & Calldata](2-memory-calldata.md)
