# Part 4 — Module 2: Memory & Calldata

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~35 minutes | **Exercises:** ~3-4 hours

---

## 📚 Table of Contents

**Memory**
- [Memory Layout: The Reserved Regions](#memory-layout)
- [The Free Memory Pointer](#free-memory-pointer)

**Calldata**
- [Calldata Layout: Static & Dynamic Types](#calldata-layout)
- [ABI Encoding at the Byte Level](#abi-encoding)

**Return Data & Errors**
- [Return Values & Error Encoding in Assembly](#return-errors)

**Practical Patterns**
- [Scratch Space for Hashing](#scratch-hashing)
- [Proxy Forwarding (Preview)](#proxy-preview)
- [Zero-Copy Calldata](#zero-copy)

**Exercises**
- [Build Exercise: MemoryLab](#exercise1)
- [Build Exercise: CalldataDecoder](#exercise2)

---

## 💡 Memory

In Module 1 you learned the EVM's stack machine — how opcodes push, pop, and transform 256-bit words. But the stack is tiny (1024 slots, no random access). Real programs need **memory**: a byte-addressable, linear scratch pad that exists for the duration of a single transaction.

This section teaches how memory actually works at the opcode level — the layout Solidity assumes, the cost model you need to internalize, and the patterns production code uses to avoid unnecessary expense.

---

<a id="memory-layout"></a>
### 💡 Concept: Memory Layout — The Reserved Regions

**Why this matters:** Every time you write `bytes memory`, `abi.encode`, `new`, or even just call a function that returns data, Solidity is managing memory behind the scenes. Understanding the layout lets you write assembly that cooperates with Solidity — or intentionally bypasses it for gas savings.

EVM memory is a **byte-addressable array** that starts at zero and grows upward. It's initialized to all zeros — this is a deliberate design choice: zero-initialization means `mload` on unwritten memory returns 0 (not garbage), so Solidity can safely use uninitialized memory for zeroing variables. It also means the zero slot at 0x60 doesn't need an explicit write. Memory only exists during the current call frame (not persisted across transactions).

But Solidity doesn't use memory starting from byte 0. It **reserves** the first 128 bytes (0x00–0x7f) for special purposes:

```
EVM Memory Layout (Solidity Convention)
┌────────────┬─────────────────────────────────────────────────────┐
│ 0x00-0x1f  │  Scratch space (word 1)                            │
│ 0x20-0x3f  │  Scratch space (word 2)                            │ ← hashing, temp ops
├────────────┼─────────────────────────────────────────────────────┤
│ 0x40-0x5f  │  Free memory pointer                               │ ← tracks next free byte
├────────────┼─────────────────────────────────────────────────────┤
│ 0x60-0x7f  │  Zero slot (always 0x00)                           │ ← empty dynamic arrays
├────────────┼─────────────────────────────────────────────────────┤
│ 0x80+      │  Allocatable memory                                │
│            │  ↓ grows toward higher addresses ↓                  │
└────────────┴─────────────────────────────────────────────────────┘
```

**The four regions:**

| Region | Offset | Size | Purpose |
|--------|--------|------|---------|
| Scratch space | 0x00–0x3f | 64 bytes | Temporary storage for hashing (keccak256) and inline computations. Solidity may overwrite this at any time, so it's only safe for immediate use. |
| Free memory pointer | 0x40–0x5f | 32 bytes | Stores the address of the next available byte. This is how Solidity tracks memory allocation. |
| Zero slot | 0x60–0x7f | 32 bytes | Guaranteed to be zero. Used as the initial value for empty dynamic memory arrays (`bytes memory`, `uint256[]`). Do not write to this. |
| Allocatable | 0x80+ | Grows | Your data starts here. 0x80 = 128 = 4 × 32, i.e., right after the four reserved 32-byte words. Every allocation bumps the free memory pointer forward. |

> **This is why every Solidity contract starts with `6080604052`.** In Module 1 you saw this init code and we said "Module 2 explains why." Here's the answer:
> - `60 80` → PUSH1 0x80 (the starting address for allocations)
> - `60 40` → PUSH1 0x40 (the address where the free memory pointer lives)
> - `52` → MSTORE (write 0x80 to address 0x40)
>
> Translation: "Set the free memory pointer to 0x80" — telling Solidity that allocations start after the reserved region.

💻 **Quick Try:**

Deploy this in [Remix](https://remix.ethereum.org/) and call `readLayout()`:

```solidity
contract MemoryLayout {
    function readLayout() external pure returns (uint256 scratch, uint256 fmp, uint256 zero) {
        assembly {
            scratch := mload(0x00)   // scratch space — could be anything
            fmp     := mload(0x40)   // free memory pointer — should be 0x80
            zero    := mload(0x60)   // zero slot — should be 0
        }
    }
}
```

You'll see `fmp = 128` (0x80) and `zero = 0`. The scratch space is unpredictable — Solidity may have used it during function dispatch.

---

<a id="memory-operations"></a>
#### 🔍 Deep Dive: Visualizing Memory Operations

The three memory opcodes you'll use most:

| Opcode | Stack input | Stack output | Effect |
|--------|------------|-------------|--------|
| `MSTORE` | `[offset, value]` | — | Write 32 bytes to `memory[offset..offset+31]` |
| `MLOAD` | `[offset]` | `[value]` | Read 32 bytes from `memory[offset..offset+31]` |
| `MSTORE8` | `[offset, value]` | — | Write 1 byte to `memory[offset]` (lowest byte of value) |

**MSIZE** — returns the highest memory offset that has been accessed (rounded up to a multiple of 32). It's a highwater mark, not a "bytes used" counter — it only grows, never shrinks. In Yul: `msize()`. Gas: 2. Primarily useful for computing expansion costs or as a gas-cheap way to get a unique memory offset (since each call to `msize()` reflects all prior memory access).

**MCOPY — efficient memory-to-memory copy:**

> Introduced in [EIP-5656](https://eips.ethereum.org/EIPS/eip-5656) (Cancun fork, March 2024)

`MCOPY(dest, src, size)` copies `size` bytes within memory from `src` to `dest`. Before MCOPY, the only options were:
1. **mload/mstore loop** — Load 32 bytes, store 32 bytes, repeat. Costs 6 gas per word (3+3) plus loop overhead
2. **Identity precompile** — `staticcall` to `0x04` with memory data. Works but has CALL overhead (~100+ gas)

MCOPY does it in a single opcode: 3 gas base + 3 per word copied + any memory expansion cost. It correctly handles overlapping source and destination regions (like C's `memmove`). The Solidity compiler (0.8.24+) automatically emits MCOPY instead of mload/mstore loops when targeting Cancun or later.

**Key insight:** `MLOAD` and `MSTORE` always operate on **32-byte words**, even if you conceptually only need a few bytes. The offset can be any byte position (not just multiples of 32), which means reads and writes can overlap.

> **Big-endian matters here.** The EVM uses **big-endian** byte ordering: the most significant byte is at the lowest address. When you `mstore(0x80, 0xCAFE)`, the value `0xCAFE` is right-aligned (stored in bytes 30-31 of the 32-byte word), with leading zeros filling bytes 0-29. This is the opposite of x86 CPUs (little-endian). Every mstore, mload, calldataload, and sload follows this convention. Understanding big-endian alignment is essential for the `0x1c` offset pattern, address masking, and manual ABI encoding.

**Tracing `mstore(0x80, 0xCAFE)`:**

```
Before:                          After:
Memory at 0x80:                  Memory at 0x80:
00 00 00 00 ... 00 00 00 00     00 00 00 00 ... 00 00 CA FE
├──────── 32 bytes ─────────┤   ├──────── 32 bytes ─────────┤

mstore writes the FULL 256-bit (32-byte) value.
0xCAFE is a small number, so it's right-aligned (big-endian):
bytes 0x80-0x9d are 0x00, bytes 0x9e-0x9f are 0xCA, 0xFE.
```

**Tracing `mload(0x80)` after the store above:**

```
Stack before: [0x80]
Stack after:  [0x000000000000000000000000000000000000000000000000000000000000CAFE]

mload reads 32 bytes starting at offset 0x80 and pushes them as a single 256-bit word.
```

**Unaligned reads — a subtle trap:**

```solidity
assembly {
    mstore(0x80, 0xAABBCCDD)
    let val := mload(0x81)  // reading 1 byte LATER
}
```

`mload(0x81)` reads bytes 0x81 through 0xA0. This overlaps the stored value but is shifted by 1 byte, giving a completely different number. In practice, always use aligned offsets (multiples of 32) unless you're doing intentional byte manipulation.

> **Memory expansion cost (recap from Module 1):** The *total accumulated* memory cost for a call frame is `3 * words + words² / 512`, where `words` is the highest memory offset used divided by 32 (rounded up). When you access a new, higher offset, the EVM charges the *difference* between the new total and the previous total. So the first expansion is cheap (just the linear term), but pushing into kilobytes becomes quadratic. **Why quadratic?** Without it, an attacker could allocate gigabytes of node memory for linear gas cost — a DoS vector against validators. The quadratic penalty makes large allocations prohibitively expensive: 1 MB of memory costs ~2.1 million gas (more than a single block's gas limit), ensuring no transaction can force excessive memory allocation on nodes. This is why production assembly is careful about how much memory it touches.

#### ⚠️ Common Mistakes

- **Writing to the reserved region (0x00-0x3f)** — Scratch space is free to use for hashing, but if you store data there expecting it to persist, the next `keccak256` or ABI encoding will overwrite it silently
- **Forgetting memory is zeroed on entry** — Unlike storage, memory starts as all zeros on every external call. But within a call, memory you wrote earlier persists — don't assume a region is clean just because you haven't written to it *recently*
- **Off-by-one in `mload`/`mstore` offsets** — `mload(0x20)` reads bytes 32-63, not bytes 33-64. Memory is byte-addressed but `mload` always reads 32 bytes starting at the given offset

#### 💼 Job Market Context

**"Describe the EVM memory layout"**
- Good: "Memory is a byte array. The first 64 bytes are scratch space, the free memory pointer is at 0x40, and the zero slot is at 0x60"
- Great: "Memory is a linear byte array that expands as you write to it, with quadratic cost growth. Bytes 0x00-0x3f are scratch space (safe for temporary hashing operations), 0x40-0x5f stores the free memory pointer that Solidity uses for allocation, and 0x60 is the zero slot used as the initial value for dynamic memory arrays. Any assembly that corrupts 0x40 will break all subsequent Solidity memory operations"

🚩 **Red flag:** Not knowing about the free memory pointer, or thinking memory persists across transactions

**Pro tip:** Drawing the memory layout on a whiteboard during an interview — with hex offsets — instantly signals you've worked at the assembly level

---

<a id="free-memory-pointer"></a>
### 💡 Concept: The Free Memory Pointer

**Why this matters:** The free memory pointer (FMP) is the single most important convention in Solidity's memory model. Every `abi.encode`, every `new`, every `bytes memory` allocation reads and bumps this pointer. If your assembly corrupts it, subsequent Solidity code will overwrite your data or crash.

The FMP lives at memory address `0x40` and always contains the byte offset of the **next available** memory location.

**The allocation pattern:**

```solidity
assembly {
    let ptr := mload(0x40)            // 1. Read: where is free memory?
    // ... write your data at ptr ...  // 2. Use: store data there
    mstore(0x40, add(ptr, size))      // 3. Bump: move pointer past your data
}
```

**Visual:**

```
Before allocation (64 bytes):            After allocation:

FMP = 0x80                               FMP = 0xC0
  ┌──────────┐                             ┌──────────┐
  │ 0x40: 80 │  ← free memory pointer      │ 0x40: C0 │  ← updated
  ├──────────┤                             ├──────────┤
  │ 0x80: .. │  ← next free byte           │ 0x80: DATA│  ← your allocation
  │ 0xA0: .. │                             │ 0xA0: DATA│
  │ 0xC0: .. │                             │ 0xC0: .. │  ← new next free byte
  └──────────┘                             └──────────┘
```

**When assembly MUST respect the FMP:**

If your assembly block is **inside** a Solidity function that later allocates memory (calls a function, creates a `bytes memory`, uses `abi.encode`, etc.), you **must** read and bump the FMP. Otherwise Solidity will allocate over your data.

**When assembly can use scratch space instead:**

For short operations that produce a result immediately (a keccak256 hash, a temporary value), you can write to the scratch space (0x00-0x3f) without touching the FMP. This saves gas because you skip the mload + mstore of the pointer.

> **Practical tip:** The scratch space is 64 bytes — exactly two 32-byte words. This is enough for hashing two values with `keccak256(0x00, 0x40)`. Solady uses this pattern extensively.

💻 **Quick Try:**

Watch the FMP move in [Remix](https://remix.ethereum.org/):

```solidity
contract FmpDemo {
    function watchFmp() external pure returns (uint256 before_, uint256 after_) {
        assembly {
            before_ := mload(0x40)            // should be 0x80
            mstore(0x40, add(before_, 0x40))  // allocate 64 bytes
            after_ := mload(0x40)             // should be 0xC0
        }
    }
}
```

Deploy, call `watchFmp()`, see `before_ = 128` (0x80), `after_ = 192` (0xC0).

---

<a id="manual-allocation"></a>
#### 🎓 Intermediate Example: Manual `bytes` Allocation

Before looking at production code, let's build a `bytes memory` value by hand in assembly. This is the same thing Solidity does behind the scenes when you write `bytes memory result = new bytes(32)`.

A `bytes memory` value in Solidity is laid out as:

```
memory[ptr]:     length (32 bytes)
memory[ptr+32]:  raw byte data (length bytes, padded to 32-byte boundary)
```

Here's how to build one manually:

```solidity
function buildBytes32(bytes32 data) external pure returns (bytes memory result) {
    assembly {
        result := mload(0x40)               // 1. Get free memory pointer
        mstore(result, 32)                  // 2. Store length = 32 bytes
        mstore(add(result, 0x20), data)     // 3. Store the data after the length
        mstore(0x40, add(result, 0x40))     // 4. Bump FMP: 32 (length) + 32 (data) = 64 bytes
    }
}
```

**Memory after execution:**

```
result → ┌──────────────────────────────────┐
         │ 0x80: 0000...0020 (length = 32)  │  word 0: length
         ├──────────────────────────────────┤
         │ 0xA0: [your 32-byte data]        │  word 1: actual bytes
         ├──────────────────────────────────┤
FMP →    │ 0xC0: ...                        │  next free byte
         └──────────────────────────────────┘
```

> **Why this matters for DeFi:** Understanding manual `bytes memory` layout is essential for reading production code that builds return data, encodes custom errors, or constructs calldata for low-level calls — all common patterns in DeFi protocols.

#### 🔗 DeFi Pattern Connection

**Where manual memory allocation appears in DeFi:**

1. **Return data construction** — Protocols that return complex data (pool states, position info) sometimes build the response in assembly to save gas
2. **Custom error encoding** — Solady and modern protocols encode errors in scratch space using `mstore` + `revert` (covered later in this module)
3. **Calldata building for low-level calls** — When calling another contract in assembly, you must build the calldata in memory: selector + encoded arguments

**The pattern:** Any time you see `mload(0x40)` followed by several `mstore` calls and then `mstore(0x40, ...)`, you're looking at manual memory allocation.

#### ⚠️ Common Mistakes

- **Not advancing the free memory pointer after allocation** — If you `mload` at `mload(0x40)` to get the free pointer, write data there, but forget to update `mstore(0x40, newPointer)`, the next Solidity operation will overwrite your data
- **Corrupting the free memory pointer in assembly blocks** — Solidity trusts that `0x40` always points to valid free memory. If your assembly writes garbage to `0x40`, all subsequent Solidity memory operations (string concatenation, ABI encoding, event emission) will corrupt
- **Using `memory-safe` annotation incorrectly** — Marking an assembly block as `memory-safe` when it writes outside scratch space or beyond the free memory pointer disables the compiler's memory safety checks and can cause silent memory corruption in optimized builds

---

<a id="memory-safe"></a>
### 💡 Concept: Memory-Safe Assembly

> **Introduced in [Solidity 0.8.13](https://blog.soliditylang.org/2022/03/16/solidity-0.8.13-release-announcement/)**

When you write an `assembly { }` block, the Solidity compiler doesn't know what your assembly does to memory. By default, it assumes the worst — your assembly might have corrupted the free memory pointer. This limits the optimizer's ability to rearrange surrounding code.

The `/// @solidity memory-safe-assembly` annotation (or `assembly ("memory-safe") { }`) tells the compiler:

> "I promise this assembly block only accesses memory in these ways:
> 1. Reading/writing scratch space (0x00–0x3f)
> 2. Reading the free memory pointer (mload(0x40))
> 3. Allocating memory by bumping the FMP properly
> 4. Reading/writing memory that was properly allocated"

```solidity
function safeExample() external pure returns (bytes32) {
    /// @solidity memory-safe-assembly
    assembly {
        mstore(0x00, 0xDEAD)
        mstore(0x20, 0xBEEF)
        mstore(0x00, keccak256(0x00, 0x40))  // hash in scratch space — safe
    }
}
```

**What you must NOT do inside memory-safe assembly:**
- Write to the zero slot (0x60-0x7f)
- Write to memory beyond the FMP without bumping it first
- Decrease the FMP

🏗️ **Real usage:** [Solady's SafeTransferLib](https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol) annotates almost every assembly block as memory-safe because all operations use scratch space for encoding call data.

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"What does memory-safe assembly mean?"**
   - Good answer: It tells the compiler the assembly respects the free memory pointer
   - Great answer: It promises the block only uses scratch space, reads FMP, or properly allocates memory — enabling the Yul optimizer to rearrange surrounding Solidity code for better gas efficiency

2. **"When would you annotate assembly as memory-safe?"**
   - When your assembly only uses scratch space (0x00-0x3f) for temp operations
   - When you properly read and bump the FMP for any allocations
   - When you're not writing to the zero slot or beyond the FMP

**Pro tip:** If you're auditing code that uses `memory-safe` annotations, verify the claim. A false `memory-safe` annotation can cause the optimizer to generate incorrect code — a subtle, critical bug.

---

## 💡 Calldata

Calldata is the **read-only input** to a contract call. Every external function call carries calldata: 4 bytes of function selector followed by ABI-encoded arguments. In Module 1 you learned to extract the selector with `calldataload(0)`. Now let's understand the full layout.

---

<a id="calldata-layout"></a>
### 💡 Concept: Calldata Layout — Static & Dynamic Types

**Why this matters:** Understanding calldata layout is how you read Permit2 signatures, decode flash loan callbacks, and write gas-efficient parameter parsing. It's also how you understand why `bytes calldata` is cheaper than `bytes memory`.

**The three calldata opcodes:**

| Opcode | Stack input | Stack output | Gas | Effect |
|--------|------------|-------------|-----|--------|
| `CALLDATALOAD` | `[offset]` | `[word]` | 3 | Read 32 bytes from calldata at offset |
| `CALLDATASIZE` | — | `[size]` | 2 | Total byte length of calldata |
| `CALLDATACOPY` | `[destOffset, srcOffset, size]` | — | 3 + 3*words + expansion | Copy calldata to memory (bulk copy, cheaper than repeated CALLDATALOAD for large data) |

**Calldata is special:**
- **Read-only** — you can't write to it. There's no "calldatastore" opcode. **Why?** Calldata is part of the transaction payload — it was signed by the sender and verified by the network. Allowing modification would break the cryptographic link between what was signed and what executes. It also simplifies execution: since calldata can't change, the EVM doesn't need to track mutations or handle write conflicts. The read-only guarantee means anyone can verify that a contract executed exactly what the user signed
- **Cheaper than memory** — CALLDATALOAD costs 3 gas flat, no expansion cost, no allocation
- **Immutable** — the same data throughout the entire call

> **Memory isolation between call frames:** Each external call (CALL, STATICCALL, DELEGATECALL) starts with **fresh, zeroed memory**. The called contract cannot see or modify the caller's memory. The only way to pass data between frames is via calldata (input) and returndata (output). This isolation is a security feature — a malicious contract can't corrupt the caller's memory layout or FMP.

**Static type layout — the simple case:**

For a function like `transfer(address to, uint256 amount)`:

```
Offset:  0x00            0x04                         0x24
         ┌──────────────┬────────────────────────────┬────────────────────────────┐
         │  selector    │  to (address, left-padded)  │  amount (uint256)          │
         │  a9059cbb    │  000...dead                 │  000...0064                │
         │  (4 bytes)   │  (32 bytes)                 │  (32 bytes)                │
         └──────────────┴────────────────────────────┴────────────────────────────┘
```

Each static parameter occupies exactly 32 bytes, starting at offset `4 + 32*n`:
- Parameter 0: `calldataload(4)` → `to`
- Parameter 1: `calldataload(36)` → `amount` (36 = 0x24 = 4 + 32)

**How the selector is computed:** The 4-byte function selector is `bytes4(keccak256("transfer(address,uint256)"))`. The canonical signature uses the **full type names** (no parameter names, no spaces, `uint256` not `uint`). In Yul, extracting it from calldata: `shr(224, calldataload(0))` — load 32 bytes at offset 0, shift right by 224 bits (256 - 32 = 224) to isolate the top 4 bytes. Module 4 covers full selector dispatch patterns.

> **Address encoding — a common point of confusion:** Addresses are 20 bytes but occupy a full 32-byte ABI slot. The address sits in the **low 20 bytes** (right-aligned, like all `uintN` types), with 12 zero bytes of **left-padding**. When you read an address from calldata in assembly with `calldataload(4)`, you get a 32-byte word where the address is in the bottom 20 bytes. Mask with `and(calldataload(4), 0xffffffffffffffffffffffffffffffffffffffff)` to extract just the address. The padding direction matches how the EVM stores all integer types — big-endian, right-aligned. Addresses are `uint160` under the hood.

💻 **Quick Try:**

Send a `transfer(address,uint256)` call in [Remix](https://remix.ethereum.org/) and examine the calldata in the debugger. You'll see exactly this layout — 4 bytes of selector, then 32-byte chunks for each argument.

💻 **Quick Try — CALLDATACOPY:**

```solidity
contract CalldataDemo {
    // Copy all calldata to memory and return it as bytes
    function echoCalldata() external pure returns (bytes memory) {
        assembly {
            let ptr := mload(0x40)                    // get FMP
            let size := calldatasize()                // total calldata bytes
            mstore(ptr, size)                         // store length for bytes memory
            calldatacopy(add(ptr, 0x20), 0, size)     // copy ALL calldata after length
            mstore(0x40, add(add(ptr, 0x20), size))   // bump FMP
            return(ptr, add(0x20, size))               // return as bytes
        }
    }
}
```

Deploy, call `echoCalldata()`, and you'll see the raw calldata bytes including the selector. `calldatacopy` is the bulk-copy workhorse — it copies `size` bytes from calldata at `srcOffset` to memory at `destOffset`, paying 3 gas per 32-byte word plus any memory expansion cost.

---

<a id="head-tail"></a>
#### 🔍 Deep Dive: Dynamic Type Encoding (Head/Tail)

Static types are simple — value at a fixed offset. **Dynamic types** (bytes, string, arrays) use a two-part encoding: a **head** section with offset pointers, and a **tail** section with actual data.

**Why offset pointers instead of inline data?** If dynamic data were inlined, you couldn't know where parameter N starts without parsing all parameters before it — because earlier dynamic values have variable length. The offset pointer design gives every parameter a fixed head position (`4 + 32*n`), so any parameter can be accessed in O(1) with a single CALLDATALOAD. The actual data lives in the tail, pointed to by the offset. This is a classic computer science trade-off: an extra indirection (one pointer dereference) in exchange for random access to any parameter.

**Example: `foo(uint256 x, bytes memory data, uint256 y)` called with `foo(42, hex"deadbeef", 7)`**

```
CALLDATA LAYOUT:

Head region (fixed-size: selector + one 32-byte slot per parameter):
Offset  Content                     Meaning
──────  ──────────────────────────  ───────────────────────────────
0x00    [abcdef01]                  Function selector (4 bytes)
0x04    [000...002a]                x = 42 (static: value inline)
0x24    [000...0060]                ← OFFSET pointer: "data" starts at byte 0x60
                                      (relative to start of parameters at 0x04)
0x44    [000...0007]                y = 7 (static: value inline)

Tail region (dynamic data, pointed to by offsets):
0x64    [000...0004]                length of "data" = 4 bytes
0x84    [deadbeef00...00]           actual bytes (right-padded to 32)
```

**How to read it step by step:**

1. **Static params** — read directly at their fixed position: `calldataload(0x04)` for x, `calldataload(0x44)` for y
2. **Dynamic param** — read the offset: `calldataload(0x24)` gives `0x60`. This means the data starts at byte `0x04 + 0x60 = 0x64` (the offset is relative to the start of the parameters, which is right after the selector)
3. **At the data location** — first word is the **length**: `calldataload(0x64)` gives `4`. Then the actual bytes start at `0x84`

**The offset pointer is relative to the start of the parameters** (byte 0x04), not the start of calldata. This is a common source of confusion.

> **Why DeFi cares:** Flash loan callbacks receive `bytes calldata data` containing user-defined payloads. Understanding the head/tail layout is essential for decoding this data in assembly, which protocols like Permit2 do for gas efficiency.

🏗️ **Real usage:** [Permit2's SignatureTransfer.sol](https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol) parses calldata in assembly for gas-efficient signature verification. [Uniswap V4's PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) decodes callback calldata for unlock patterns.

**In Yul with `bytes calldata` parameters:**

When a function takes `bytes calldata data`, Solidity provides convenient Yul accessors:
- `data.offset` — byte position in calldata where the raw bytes start (past the length word)
- `data.length` — number of bytes

These handle the offset indirection for you. But when parsing raw calldata manually (e.g., in a fallback function), you need to follow the pointers yourself.

#### 🎓 Intermediate Example: Decoding Dynamic Calldata in Yul

Before the exercise asks you to do this, let's trace the pattern step by step with a minimal example:

```solidity
// Given: function foo(uint256 x, bytes memory data)
// We want to read the length of `data` in assembly.
function readDynamicLength(uint256, bytes calldata) external pure returns (uint256 len) {
    assembly {
        // Step 1: The offset pointer for `data` is at parameter position 1 (second param)
        //         That's at calldata position 0x04 + 0x20 = 0x24
        let offset := calldataload(0x24)

        // Step 2: This offset is relative to the start of the parameters (0x04)
        let dataStart := add(0x04, offset)

        // Step 3: The first word at the data location is the byte length
        len := calldataload(dataStart)
    }
}
```

Call `readDynamicLength(42, hex"DEADBEEF")` and you get `len = 4`. The offset pointer at position 0x24 contains `0x40` (64 — pointing past both parameter slots), so `dataStart = 0x04 + 0x40 = 0x44`, and `calldataload(0x44)` reads the length word.

#### 📦 Nested Dynamic Types

When dynamic types contain other dynamic types (e.g., `bytes[]`, `uint256[][]`, or structs with dynamic fields), the encoding becomes multi-level. Each level adds another layer of offset pointers.

**Example: `function bar(bytes[] memory items)` called with two byte arrays:**

```
CALLDATA LAYOUT:

Head:
0x04    [000...0020]           offset to items array (0x20 from param start)

Array header at 0x24:
0x24    [000...0002]           items.length = 2

Array offset table at 0x44:
0x44    [000...0040]           offset to items[0] (relative to array start at 0x24)
0x64    [000...0080]           offset to items[1] (relative to array start at 0x24)

items[0] data at 0x24 + 0x40 = 0x64:
0x64    [000...0003]           length of items[0] = 3 bytes
0x84    [aabbcc00...00]        items[0] data

items[1] data at 0x24 + 0x80 = 0xa4:
0xa4    [000...0002]           length of items[1] = 2 bytes
0xc4    [ddee0000...00]        items[1] data
```

**The pattern:** Each nesting level adds its own offset table. To reach `items[1]`, you follow: parameter offset → array offset table → item 1 offset → length → data. That's 4 CALLDATALOAD operations. This is why deeply nested dynamic types are gas-expensive to decode and why protocols like Uniswap flatten their data structures when possible.

> **In practice:** You'll rarely decode nested dynamic types by hand. Solidity handles the indirection automatically. But understanding the layout helps when debugging failed transactions — tools like `cast calldata-decode` show the structure, and knowing how offsets chain lets you verify the raw bytes.

#### 💼 Job Market Context

**"How is function call data structured?"**
- Good: "First 4 bytes are the function selector, followed by ABI-encoded arguments"
- Great: "The first 4 bytes are `keccak256(signature)[:4]` — the function selector. Static arguments follow in 32-byte padded slots. Dynamic types (bytes, string, arrays) use a head/tail pattern: the head contains an offset pointer to where the data actually lives in the tail region. This is why `msg.data.length` can be longer than you'd expect for functions with dynamic parameters"

🚩 **Red flag:** Not knowing what a function selector is or how it's computed

**Pro tip:** Being able to decode raw calldata by hand (even with etherscan's help) is a skill auditors and MEV researchers use daily

---

<a id="abi-encoding"></a>
### 💡 Concept: ABI Encoding at the Byte Level

**Why this matters:** When you call `abi.encode(...)` in Solidity, the compiler generates assembly that allocates memory, writes data in the ABI format, and bumps the free memory pointer. Understanding the byte layout lets you (a) build calldata in assembly for gas savings, (b) decode return data manually, and (c) read production code that does both.

**Encoding static types:**

Every static type is padded to exactly 32 bytes. **Why 32 bytes?** The EVM's word size is 256 bits (32 bytes). MLOAD, MSTORE, and CALLDATALOAD all operate on 32-byte chunks. By padding every value to 32 bytes, the ABI ensures that any parameter can be read with a single CALLDATALOAD or MLOAD — no bit shifting, no partial-word extraction. This trades space efficiency for simplicity and gas efficiency at the opcode level. A `uint8` wastes 31 bytes of padding, but reading it is one opcode (3 gas) instead of a load-shift-mask sequence.

```
abi.encode(uint256(42)):
[000000000000000000000000000000000000000000000000000000000000002a]
 ├──────────────────── 32 bytes ─────────────────────────────────┤

abi.encode(address(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045)):
[000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045]
 ├── 12 bytes padding ──┤├────── 20 bytes address ───────────────┤

abi.encode(bool(true)):
[0000000000000000000000000000000000000000000000000000000000000001]
 ├──────────────────── 32 bytes ─────────────────────────────────┤
```

**Encoding dynamic types (bytes, string, arrays):**

Dynamic types use the offset-length-data pattern:

```
abi.encode(bytes("hello")):

Word 0:  [000...0020]           offset to data = 0x20 (32 bytes from here)
Word 1:  [000...0005]           length = 5 bytes
Word 2:  [68656c6c6f000...00]   "hello" + 27 bytes of zero padding
         ├─ 32 bytes ──────────────────────────────────────────────┤

Total: 96 bytes (3 words × 32 bytes)
```

**Multiple parameters — the head/tail pattern in memory:**

```
abi.encode(uint256(42), bytes("hello"), uint256(7)):

Word 0:  [000...002a]           x = 42 (static, inline)
Word 1:  [000...0060]           offset to "hello" data (from start = 0x60)
Word 2:  [000...0007]           y = 7 (static, inline)
Word 3:  [000...0005]           ← data region: length of "hello"
Word 4:  [68656c6c6f000...00]   ← data region: "hello" + padding

The head (words 0-2) has fixed-size slots.
The tail (words 3-4) has dynamic data.
```

💻 **Quick Try:**

Deploy this in [Remix](https://remix.ethereum.org/) and call `inspect()`:

```solidity
contract AbiInspect {
    function inspect() external pure returns (bytes memory) {
        return abi.encode(uint256(42), bytes("hello"), uint256(7));
    }
}
```

The returned bytes will be 160 bytes (5 words). Trace them against the diagram above: word 0 = 42, word 1 = offset (0x60), word 2 = 7, word 3 = length (5), word 4 = "hello" + padding. Count the words — you should see exactly 5.

---

<a id="encode-vs-packed"></a>
#### 🔍 Deep Dive: abi.encode vs abi.encodePacked

Both encode data as bytes, but with fundamentally different rules:

| | `abi.encode` | `abi.encodePacked` |
|---|---|---|
| **Padding** | Every value padded to 32 bytes | Minimum bytes per type |
| **Dynamic types** | Offset + length + data | Length prefix + raw data |
| **Decodable** | Yes — `abi.decode` works | No — ambiguous without schema |
| **Use case** | External calls, return data | Hashing, compact storage |
| **ABI-compliant** | Yes | No |

**Side-by-side comparison:**

```
abi.encode(uint8(1), uint8(2)):
[0000000000000000000000000000000000000000000000000000000000000001]  ← 32 bytes for uint8(1)
[0000000000000000000000000000000000000000000000000000000000000002]  ← 32 bytes for uint8(2)
Total: 64 bytes

abi.encodePacked(uint8(1), uint8(2)):
[01][02]
Total: 2 bytes
```

**Why packed encoding is dangerous for external calls:**

`abi.encodePacked` strips type information. If you send packed-encoded data to a contract expecting standard ABI encoding, the decoder will misinterpret the bytes. Only use packed encoding for:
- **Hashing** — `keccak256(abi.encodePacked(a, b))` is common and safe
- **Compact data** — storing short data in events or non-standard formats

> **Warning:** `abi.encodePacked` with multiple dynamic types (`bytes`, `string`) can produce ambiguous encodings. `abi.encodePacked(bytes("ab"), bytes("c"))` and `abi.encodePacked(bytes("a"), bytes("bc"))` produce the same output: `0x616263`. This is a known collision vector for hashing.

#### 🔗 DeFi Pattern Connection

**Where ABI encoding matters in DeFi:**

1. **Permit signatures** — EIP-2612 `permit()` encodes the struct hash using `abi.encode` (not packed) because the EIP-712 spec requires standard ABI encoding
2. **Flash loan callbacks** — Aave's `executeOperation` receives `bytes calldata params` which is ABI-encoded user data that the callback must decode
3. **Multicall batching** — Uniswap's `multicall(bytes[] calldata data)` encodes multiple function calls as an array of ABI-encoded calldata
4. **CREATE2 address computation** — Uses `keccak256(abi.encodePacked(0xff, deployer, salt, codeHash))` — packed encoding for compact hashing

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"Why is `bytes calldata` cheaper than `bytes memory`?"**
   - Good answer: Calldata doesn't copy to memory
   - Great answer: `bytes memory` triggers `CALLDATACOPY` to heap memory, expanding it and paying `3 + 3*words + quadratic expansion`. `bytes calldata` reads directly with `CALLDATALOAD` at 3 gas per word, zero expansion. For a 1KB payload, memory costs ~3,000+ extra gas.

2. **"What's the hash collision risk with `abi.encodePacked`?"**
   - Good answer: Dynamic types can produce identical outputs for different inputs
   - Great answer: `abi.encodePacked(bytes("ab"), bytes("c"))` and `abi.encodePacked(bytes("a"), bytes("bc"))` both produce `0x616263`. This makes it unsafe for hashing multiple dynamic values — use `abi.encode` instead to get unambiguous 32-byte-padded encoding.

3. **"How does ABI encoding handle dynamic types?"**
   - Great answer: The head section has a 32-byte offset pointer for each dynamic parameter (relative to the start of parameters). The tail section has length-prefixed data. Static parameters are inlined directly. This lets decoders jump to any parameter in O(1) using the head offsets.

**Interview red flag:** Using `abi.encodePacked` for cross-contract call encoding or confusing it with `abi.encode`. Also: not knowing that addresses are left-padded (12 zero bytes) in ABI encoding.

#### ⚠️ Common Mistakes

- **Confusing `abi.encode` with `abi.encodePacked` for hashing** — `encodePacked` removes padding, which means `abi.encodePacked(uint8(1), uint248(2))` and `abi.encodePacked(uint256(1), uint256(2))` can produce different results. For `keccak256` in mappings, Solidity always uses `abi.encode` (with padding). Using `encodePacked` accidentally will compute wrong slots
- **Forgetting that dynamic types use head/tail encoding** — A `bytes` argument in calldata isn't where you expect it. The head contains an offset pointer, and the actual data is in the tail region. Hardcoding offsets instead of reading the head pointer is a classic calldata parsing bug

---

## 💡 Return Data & Errors

<a id="return-errors"></a>
### 💡 Concept: Return Values & Error Encoding in Assembly

**Why this matters:** When you write `return x;` in Solidity, the compiler encodes `x` into memory using ABI encoding, then executes `RETURN(ptr, size)`. When you write `revert CustomError()`, it does the same with `REVERT`. Understanding this lets you encode return values and errors directly in assembly — saving the overhead of Solidity's encoder.

**The RETURN and REVERT opcodes:**

| Opcode | Stack input | Effect |
|--------|------------|--------|
| `RETURN` | `[offset, size]` | Stop execution, return `memory[offset..offset+size-1]` to caller |
| `REVERT` | `[offset, size]` | Stop execution, revert with `memory[offset..offset+size-1]` as error data |

Both read from **memory**, not the stack. You must encode your data in memory first, then point RETURN/REVERT to it.

**Returning a uint256:**

```solidity
function getFortyTwo() external pure returns (uint256) {
    assembly {
        mstore(0x00, 42)       // write 42 to scratch space
        return(0x00, 0x20)     // return 32 bytes from offset 0x00
    }
}
```

The caller receives 32 bytes: `000...002a` — exactly what `abi.encode(uint256(42))` produces.

**The returndatasize and returndatacopy opcodes:**

After any external call (`CALL`, `STATICCALL`, `DELEGATECALL`), the return data is available in a transient buffer:

| Opcode | Stack input | Stack output | Effect |
|--------|------------|-------------|--------|
| `RETURNDATASIZE` | — | `[size]` | Size of the last call's return data |
| `RETURNDATACOPY` | `[destOffset, srcOffset, size]` | — | Copy return data to memory |

**Important behaviors:**
- Before any external call, `RETURNDATASIZE` returns **0** (this is the PUSH0 trick from Module 1)
- After a successful call, it returns the size of the return data
- After a reverted call, it returns the size of the **revert data** (error bytes)
- `RETURNDATACOPY` with `srcOffset + size > RETURNDATASIZE` causes a revert — you cannot read beyond available data
- The return data buffer is **overwritten** by each subsequent call (including calls within the same function)

> **Note:** Module 5 (External Calls) covers the full pattern of making calls and handling their return data.

---

<a id="offset-explained"></a>
#### 🔍 Deep Dive: The 0x1c Offset Explained

In Module 1 you saw this pattern without explanation:

```solidity
assembly {
    mstore(0x00, 0x82b42900)  // CustomError() selector
    revert(0x1c, 0x04)        // ← Why 0x1c? Why not 0x00?
}
```

Now you know enough to understand why.

**`mstore(0x00, 0x82b42900)` writes 32 bytes to memory starting at offset 0x00:**

`MSTORE` always writes a full 256-bit word. The value `0x82b42900` is a small number — only 4 bytes — so it's **right-aligned** in the 32-byte word:

```
mstore(0x00, 0x82b42900)

Memory at 0x00 after the write:
Byte:  00 01 02 ... 1a 1b │ 1c 1d 1e 1f
Value: 00 00 00 ... 00 00 │ 82 b4 29 00
       ├─── 28 zero bytes ─┤ ├─ 4 bytes ┤
                              selector!
```

The selector `0x82b42900` lands at bytes **28-31** (0x1c-0x1f) because integers are big-endian (right-aligned) in the EVM.

**`revert(0x1c, 0x04)` reads 4 bytes starting at offset 0x1c:**

```
revert(0x1c, 0x04) → reads bytes 0x1c, 0x1d, 0x1e, 0x1f → 82 b4 29 00
```

That's the error selector! The caller receives exactly `0x82b42900` — which is what `CustomError.selector` resolves to.

**Why not `revert(0x00, 0x04)`?** That would read bytes 0x00-0x03, which are all zeros. You'd revert with empty data.

**Error with a parameter — the extended pattern:**

```solidity
error InsufficientBalance(uint256 available);

assembly {
    mstore(0x00, 0xf4d678b8)          // InsufficientBalance(uint256) selector
    mstore(0x20, availableAmount)      // parameter at next word
    revert(0x1c, 0x24)                // 4 bytes selector + 32 bytes parameter = 36 bytes
}
```

**Memory layout:**

```
0x00-0x1f:  [00 00 ... 00  f4 d6 78 b8]     selector right-aligned in word 0
0x20-0x3f:  [00 00 ... 00  XX XX XX XX]     parameter right-aligned in word 1

revert(0x1c, 0x24) reads 36 bytes:
├── 0x1c-0x1f ──┤├───────── 0x20-0x3f ─────────┤
   f4 d6 78 b8    00...00 XX XX XX XX
   (selector)     (uint256 parameter)
```

The result is a properly ABI-encoded error: 4-byte selector followed by a 32-byte uint256.

> **The math:** `0x1c` = 28 in decimal. A selector is 4 bytes. 32 - 4 = 28. So `0x1c` is always the right offset for a selector stored with `mstore(0x00, selector)`.

💻 **Quick Try:**

Deploy in [Remix](https://remix.ethereum.org/) and call `fail()`:

```solidity
contract RevertDemo {
    error Unauthorized();  // selector: 0x82b42900

    function fail() external pure {
        assembly {
            mstore(0x00, 0x82b42900)
            revert(0x1c, 0x04)
        }
    }
}
```

You'll see `Unauthorized()` in the error output. Now change `revert(0x1c, 0x04)` to `revert(0x00, 0x04)` — the call still reverts, but the error is unrecognized (4 zero bytes instead of the selector).

---

<a id="solady-errors"></a>
#### 🔗 DeFi Pattern Connection: Solady Error Encoding

**Why Solady uses this pattern everywhere:**

Solidity's built-in error encoding does this:
1. Allocate memory at the free memory pointer
2. Write the error selector and parameters
3. Bump the free memory pointer
4. Revert with the allocated region

The assembly pattern above does this:
1. Write the selector to scratch space (0x00) — no allocation needed
2. Write parameters to the next word (0x20) — still in scratch space
3. Revert from offset 0x1c

**Gas savings: ~200 gas** per revert, because we skip the FMP read, write, and bump. In a protocol that reverts in many code paths (access control, slippage checks, deadline validation), this adds up.

🏗️ **Real usage:** [Solady's Ownable](https://github.com/vectorized/solady/blob/main/src/auth/Ownable.sol) reverts with custom errors using scratch space encoding throughout. After this module, you can read that code fluently.

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"Why does Solady use `mstore(0, selector) + revert(0x1c, 4)` instead of `revert CustomError()`?"**
   - Good answer: Gas savings
   - Great answer: Solidity's error encoding allocates memory and bumps the FMP — ~200 gas overhead per revert. The assembly pattern writes to scratch space (0x00-0x3f) which doesn't require FMP management. In protocols with many revert paths, this saves meaningful gas.

2. **"What does `0x1c` mean in `revert(0x1c, 0x04)`?"**
   - Great answer: 0x1c is 28 decimal. `mstore(0, selector)` writes a 32-byte word where the 4-byte selector is right-aligned (big-endian). So the selector starts at byte 28. `revert(0x1c, 0x04)` reads exactly those 4 bytes.

**Interview red flag:** Blindly copying the `revert(0x1c, 0x04)` pattern without being able to explain the byte layout. Interviewers test this because it separates "can read Solady" from "understands Solady."

**"How do custom errors work at the EVM level?"**
- Good: "They use a 4-byte selector just like functions, followed by ABI-encoded error data"
- Great: "The EVM has no concept of 'errors' — a revert is just `REVERT(offset, size)` which returns arbitrary bytes. Solidity custom errors encode a 4-byte selector plus ABI-encoded parameters, identical to function calldata. This is why you can decode revert reasons with `abi.decode`. The classic `Error(string)` and `Panic(uint256)` are just two specific selectors — custom errors are more gas-efficient because they skip string encoding"

🚩 **Red flag:** Thinking `require(condition, "message")` and custom errors are fundamentally different mechanisms

**Pro tip:** Know the Solady pattern of encoding errors in assembly with `mstore(0x00, selector)` — it saves ~100 gas per revert by skipping ABI encoding overhead

---

## 💡 Practical Patterns

Now that you understand memory, calldata, and return data as separate regions, these patterns show how production code combines them.

<a id="scratch-hashing"></a>
### 💡 Concept: Scratch Space for Hashing

**Why this matters:** Hashing is one of the most common operations in DeFi — computing mapping slots, verifying signatures, deriving addresses. The scratch space pattern makes it cheaper.

**The pattern:**

```solidity
function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32 result) {
    /// @solidity memory-safe-assembly
    assembly {
        mstore(0x00, a)                    // write a to scratch word 1
        mstore(0x20, b)                    // write b to scratch word 2
        result := keccak256(0x00, 0x40)    // hash 64 bytes
    }
}
```

**Why it's safe:** Scratch space (0x00-0x3f) is specifically reserved for temporary operations. Solidity may overwrite it at any time, but we don't care — we use it and immediately capture the result. The `memory-safe-assembly` annotation is valid because we only touch scratch space.

**Why it's cheaper than Solidity:**

The equivalent `keccak256(abi.encodePacked(a, b))` in Solidity:
1. Reads the FMP (`mload(0x40)`)
2. Writes `a` and `b` to memory at the FMP
3. Bumps the FMP
4. Calls `keccak256` on the allocated region

The assembly version skips steps 1-3 entirely.

🏗️ **Real usage:** This pattern appears in [Solady's MerkleProofLib](https://github.com/vectorized/solady/blob/main/src/utils/MerkleProofLib.sol), [OpenZeppelin's MerkleProof](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/MerkleProof.sol), and virtually every library that computes hash pairs for Merkle trees.

#### 🔗 DeFi Pattern Connection

**Where scratch space hashing appears in DeFi:**

1. **Merkle proofs** — Verifying inclusion in airdrops, allowlists, and governance proposals
2. **CREATE2 addresses** — Computing deployment addresses: `keccak256(abi.encodePacked(0xff, deployer, salt, codeHash))`
3. **Storage slot computation** — `keccak256(abi.encode(key, slot))` for mapping lookups (covered in Module 3)
4. **EIP-712 hashing** — Computing typed data hashes for signatures (permit, order signing)

---

<a id="proxy-preview"></a>
### 💡 Concept: Proxy Forwarding (Preview)

This is a preview of a pattern covered fully in Module 5 (External Calls). It combines everything from this module: `calldatacopy` to read input, memory to buffer data, and `returndatacopy` to forward output.

```solidity
// Minimal proxy forwarding — the core of OpenZeppelin's Proxy.sol
assembly {
    // 1. Copy ALL calldata to memory at position 0
    calldatacopy(0, 0, calldatasize())

    // 2. Forward to implementation via delegatecall
    let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

    // 3. Copy return data to memory at position 0
    returndatacopy(0, 0, returndatasize())

    // 4. Return or revert with the forwarded data
    switch result
    case 0 { revert(0, returndatasize()) }
    default { return(0, returndatasize()) }
}
```

**What this uses from Module 2:**
- `calldatacopy(0, 0, calldatasize())` — copy calldata to memory ([Calldata Layout](#calldata-layout))
- `returndatacopy(0, 0, returndatasize())` — copy return data to memory ([Return Values](#return-errors))
- Memory offset 0 — uses scratch space and beyond, because there's no Solidity code after this (the function either returns or reverts)

> **Note:** This pattern starts writing at offset 0, overwriting scratch space, the FMP at 0x40, and potentially the zero slot at 0x60 if calldata exceeds 96 bytes. This is safe because the function either returns or reverts immediately — no subsequent Solidity code will read the corrupted FMP or zero slot. Module 5 covers when this is safe and when you need to use the FMP.

🏗️ **Real usage:** [OpenZeppelin's Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol) — the production implementation that every upgradeable contract uses.

---

<a id="zero-copy"></a>
### 💡 Concept: Zero-Copy Calldata

**Why this matters:** In Solidity, `bytes calldata` parameters are read directly from calldata without copying to memory. This is why `bytes calldata` is cheaper than `bytes memory` — you avoid memory allocation and expansion costs entirely.

**The gas difference:**

```solidity
// Copies data to memory — costs gas for allocation + expansion + copy
function processMemory(bytes memory data) external { ... }

// Reads directly from calldata — no copy, no memory cost
function processCalldata(bytes calldata data) external { ... }
```

For a 1KB input, the memory version pays: `CALLDATACOPY` base cost (3 + 3*32 = 99 gas), plus memory expansion (1KB = 32 words: 3*32 + 32^2/512 = 96 + 2 = 98 gas total), plus Solidity's ABI decoding overhead (offset validation, length checks). Altogether ~200+ gas just for the data copy, plus ABI overhead that can push it to ~3,000+. The calldata version costs nothing extra — the data is already in calldata from the transaction.

**In assembly:**

```solidity
function readFirstWord(bytes calldata data) external pure returns (uint256) {
    assembly {
        // data.offset points to the byte position in calldata — no copy needed
        let word := calldataload(data.offset)
        mstore(0x00, word)
        return(0x00, 0x20)
    }
}
```

**When you DO need to copy:** If you need to modify the data, hash non-contiguous pieces, or pass it to a `CALL` that expects memory input, you must use `calldatacopy` to bring it into memory first.

---

<a id="how-to-study"></a>
#### 📖 How to Study Memory-Heavy Assembly

When you encounter assembly that manipulates memory extensively (common in Solady, Uniswap V4, and custom routers):

1. **Draw the memory layout** — Map out which offsets hold which data. Use a table with columns: offset, content, meaning
2. **Track the FMP** — Note every `mload(0x40)` and `mstore(0x40, ...)`. Does it start at 0x80? Where does it end?
3. **Identify scratch space usage** — Any writes to 0x00-0x3f are temporary. The data there is only valid until the next Solidity operation
4. **Follow the calldata flow** — Trace `calldataload` and `calldatacopy` calls. What's being read? From which offset?
5. **Check the RETURN/REVERT** — What memory region is being returned? Does it match the expected ABI encoding?

**Don't get stuck on:** Exact gas counts. Focus on understanding the data layout first — gas optimization comes in Module 6.

---

<a id="exercise1"></a>
## 🎯 Build Exercise: MemoryLab

**Workspace:** [`src/part4/module2/exercise1-memory-lab/MemoryLab.sol`](../workspace/src/part4/module2/exercise1-memory-lab/MemoryLab.sol) | [`test/.../MemoryLab.t.sol`](../workspace/test/part4/module2/exercise1-memory-lab/MemoryLab.t.sol)

Work with memory layout, the free memory pointer, and scratch space. All functions are implemented in `assembly { }` blocks.

**What you'll implement:**
1. `readFreeMemPtr()` — Read and return the free memory pointer
2. `allocate(uint256 size)` — Allocate `size` bytes: read FMP, bump it, return the old value
3. `writeAndRead(uint256 value)` — Write a value to memory at 0x80, read it back
4. `buildUint256Bytes(uint256 val)` — Build a `bytes memory` containing a uint256: store length (32), store data, bump FMP
5. `readZeroSlot()` — Read the zero slot (0x60) and verify it's zero
6. `hashPair(bytes32 a, bytes32 b)` — Hash two values using scratch space (0x00-0x3f) with keccak256

**🎯 Goal:** Internalize the memory layout and FMP management pattern. After this exercise, `mload(0x40)` and `mstore(0x40, ...)` will feel natural.

Run: `FOUNDRY_PROFILE=part4 forge test --match-contract MemoryLabTest -vvv`

---

<a id="exercise2"></a>
## 🎯 Build Exercise: CalldataDecoder

**Workspace:** [`src/part4/module2/exercise2-calldata-decoder/CalldataDecoder.sol`](../workspace/src/part4/module2/exercise2-calldata-decoder/CalldataDecoder.sol) | [`test/.../CalldataDecoder.t.sol`](../workspace/test/part4/module2/exercise2-calldata-decoder/CalldataDecoder.t.sol)

Parse calldata and encode errors in assembly. Mix of calldata reading and memory writing.

**What you'll implement:**
1. `extractUint(bytes calldata data, uint256 index)` — Read the uint256 at position `index` (the Nth 32-byte word)
2. `extractAddress(bytes calldata data)` — Read an address from the first parameter (mask to 20 bytes)
3. `extractDynamicBytes(bytes calldata data)` — Follow an ABI offset pointer to decode a dynamic `bytes` value
4. `encodeRevert(uint256 code)` — Encode `CustomError(uint256)` in memory and revert
5. `forwardCalldata()` — Copy all calldata to memory and return it as `bytes`

**🎯 Goal:** Be able to parse calldata by hand and encode errors the way production code does. After this exercise, you can read Permit2's calldata parsing and Solady's error encoding.

Run: `FOUNDRY_PROFILE=part4 forge test --match-contract CalldataDecoderTest -vvv`

---

<a id="summary"></a>
## 📋 Key Takeaways: Memory & Calldata

**✓ Memory:**
- EVM memory is a byte-addressable linear array, initialized to zero
- Reserved regions: scratch space (0x00-0x3f), FMP (0x40-0x5f), zero slot (0x60-0x7f)
- Allocatable memory starts at 0x80 (that's what `6080604052` sets up)
- The free memory pointer at 0x40 must be read and bumped for proper allocations
- `mload`/`mstore` always operate on 32-byte words (big-endian, right-aligned values)
- `KECCAK256(offset, size)` reads from memory — you must store data in memory before hashing
- `LOG` topics are stack values, but log **data** is read from memory (`LOG1(offset, size, topic)`)
- Scratch space is safe for temporary operations (hashing, error encoding)
- `memory-safe-assembly` tells the compiler your assembly respects the FMP

**✓ Calldata:**
- Read-only, cheaper than memory (3 gas per `CALLDATALOAD`, no expansion)
- Layout: 4-byte selector + 32-byte slots for each parameter
- Static types: value inline at `4 + 32*n`
- Dynamic types: offset pointer in head → length + data in tail
- `bytes calldata` gives Yul accessors `.offset` and `.length`

**✓ ABI Encoding:**
- `abi.encode`: every value padded to 32 bytes, dynamic types use offset+length+data
- `abi.encodePacked`: minimum bytes per type, no padding, NOT ABI-compliant
- Packed encoding is for hashing, not for external calls

**✓ Return Data & Errors:**
- `RETURN(offset, size)` / `REVERT(offset, size)` read from memory
- Error selector encoding: `mstore(0x00, selector)` places selector at byte 0x1c (28 = 32 - 4)
- `revert(0x1c, 0x04)` for zero-arg errors, `revert(0x1c, 0x24)` for one-arg errors
- Assembly error encoding saves ~200 gas by using scratch space instead of allocating memory

**Key numbers to remember:**
- `0x00-0x3f` — scratch space (64 bytes, 2 words)
- `0x40` — free memory pointer location
- `0x60` — zero slot
- `0x80` — first allocatable byte
- `0x1c` (28) — offset for reading a selector from `mstore(0x00, selector)`
- `0x20` (32) — word size (one `mstore`/`mload` unit)

**Next:** [Module 3 — Storage Deep Dive](3-storage.md) explores the persistent data layer: slot computation, mapping and array layouts, and storage packing patterns.

---

<a id="resources"></a>
## 📚 Resources

**Essential References:**
- [Solidity Docs — Memory Layout](https://docs.soliditylang.org/en/latest/internals/layout_in_memory.html) — Official documentation on the reserved regions
- [Solidity Docs — ABI Specification](https://docs.soliditylang.org/en/latest/abi-spec.html) — Complete encoding rules for all types
- [Solidity Docs — Inline Assembly](https://docs.soliditylang.org/en/latest/assembly.html) — Memory-safe annotation and Yul memory opcodes

**Formal Specification:**
- [Ethereum Yellow Paper — Appendix H](https://ethereum.github.io/yellowpaper/paper.pdf) — Formal definitions of MLOAD, MSTORE, MSIZE, CALLDATALOAD, CALLDATACOPY, RETURN, REVERT. The memory expansion cost formula appears in equation (326)

**EIPs:**
- [EIP-5656](https://eips.ethereum.org/EIPS/eip-5656) — MCOPY opcode (Cancun fork)
- [EIP-712: Typed Structured Data Hashing](https://eips.ethereum.org/EIPS/eip-712) — Uses ABI encoding for structured hashing in signatures

**Production Code:**
- [Solady SafeTransferLib](https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol) — Memory-safe assembly for token transfers
- [Solady Ownable](https://github.com/vectorized/solady/blob/main/src/auth/Ownable.sol) — Scratch space error encoding throughout
- [Solady MerkleProofLib](https://github.com/vectorized/solady/blob/main/src/utils/MerkleProofLib.sol) — Scratch space hashing for Merkle proofs
- [OpenZeppelin Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol) — Production proxy forwarding with calldatacopy + returndatacopy
- [Permit2 SignatureTransfer.sol](https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol) — Calldata parsing in assembly for gas efficiency
- [Uniswap V4 PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) — Callback calldata decoding patterns

**Deep Dives:**
- [Ethereum In Depth Part 2 — OpenZeppelin](https://blog.openzeppelin.com/ethereum-in-depth-part-2-6339cf6bddb9) — Excellent deep dive on data locations
- [ABI Encoding Deep Dive — Andrey Obruchkov](https://andreyobruchkov1996.substack.com/p/abi-encoding-deep-dive-how-solidity) — Visual walkthrough of encoding

**Hands-On:**
- [evm.codes](https://www.evm.codes/) — Interactive opcode reference with memory visualization
- [Remix IDE](https://remix.ethereum.org/) — Deploy Quick Try examples and step through with the debugger

---

**Navigation:** [Previous: Module 1 — EVM Fundamentals](1-evm-fundamentals.md) | [Next: Module 3 — Storage Deep Dive](3-storage.md)
