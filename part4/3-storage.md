# Part 4 — Module 3: Storage Deep Dive

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~40 minutes | **Exercises:** ~4-5 hours

---

## 📚 Table of Contents

**The Storage Model**
- [The 2^256 Key-Value Store](#kv-store)
- [Verkle Trees: What's Changing](#verkle)

**SLOAD & SSTORE — The Full Picture**
- [SLOAD & SSTORE in Yul](#sload-sstore-yul)

**Slot Computation — From Variables to Tries**
- [State Variables: Sequential Assignment](#sequential-slots)
- [Why keccak256: Collision Resistance in 2^256 Space](#why-keccak)
- [Mapping Slot Computation](#mapping-slots)
- [Dynamic Array Slot Computation](#array-slots)
- [Nested Structures: Mappings of Mappings, Mappings of Structs](#nested-slots)
- [The -1 Trick: Preimage Attack Prevention](#minus-one)

**Storage Packing in Assembly**
- [Manual Pack/Unpack with Bit Operations](#manual-packing)
- [Aave V3 ReserveConfiguration Case Study](#aave-case-study)

**Transient Storage in Assembly**
- [TLOAD & TSTORE Yul Patterns](#tload-tstore)

**Production Storage Patterns**
- [ERC-1967 Proxy Slots in Assembly](#erc-1967-assembly)
- [ERC-7201 Namespaced Storage](#erc-7201)
- [SSTORE2: Bytecode as Immutable Storage](#sstore2)
- [Storage Proofs and Reading Any Contract's Storage](#storage-proofs)

**Exercises**
- [Build Exercise: SlotExplorer](#exercise1)
- [Build Exercise: StoragePacker](#exercise2)

---

## 💡 The Storage Model

In Module 2 you learned memory — a scratch pad that vanishes when the call ends. Now the permanent layer: **storage**. Every state variable you've ever written in Solidity lives here. Every token balance, every approval, every governance vote — it's all storage slots.

This section teaches what storage actually is at the EVM level, how it's organized under the hood, and why it costs what it costs.

---

<a id="kv-store"></a>
### 💡 Concept: The 2^256 Key-Value Store

**Why this matters:** Understanding the storage model is the foundation for everything else in this module — slot computation, packing, and gas optimization all depend on knowing what you're working with.

Each contract has its own **key-value store** with 2^256 possible keys (called **slots**). Both keys and values are 32 bytes (256 bits). Every slot defaults to zero — this is why Solidity initializes state variables to zero for free (reading an unwritten slot returns `0x00...00`).

This is NOT an array or contiguous memory. It's a **sparse map**. A contract with 3 state variables uses 3 slots out of 2^256. The storage trie only tracks non-zero slots, so unused slots cost nothing to maintain.

```
Contract Storage (conceptual model)
┌─────────────────────────────────────────────────┐
│  Slot 0  → 0x0000...002a  (simpleValue = 42)   │
│  Slot 1  → 0x0000...0000  (mapping base slot)  │
│  Slot 2  → 0x0000...0003  (array length = 3)   │
│  Slot 3  → 0x0000...0000  (nested mapping)     │
│  ...                                            │
│  Slot 2^256 - 1 → 0x0000...0000                │
│                                                 │
│  99.999...% of slots are zero (never written)   │
└─────────────────────────────────────────────────┘
```

💻 **Quick Try:**

Read any deployed contract's storage with `cast`:

```bash
# Read WETH's slot 0 (name string pointer) on mainnet
cast storage 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0 --rpc-url https://eth.llamarpc.com
```

> Any slot you read will return a 32-byte hex value. Unwritten slots return `0x0000...0000`.

---

<a id="mpt-diagram"></a>
#### 🔍 Deep Dive: From Slot to World State (Merkle Patricia Trie)

Where do storage slots actually live? In Ethereum's **world state** — a tree structure that organizes all account data.

```
World State (Modified Merkle Patricia Trie)
│
├── Account 0xAbC...  ──┐
│                        ├── nonce
│                        ├── balance
│                        ├── codeHash
│                        └── storageRoot ──→ Storage Trie
│                                           │
│                                           ├── keccak256(slot 0) → value
│                                           ├── keccak256(slot 1) → value
│                                           └── keccak256(slot N) → value
│
├── Account 0xDeF...  ──┐
│                        └── storageRoot ──→ (its own Storage Trie)
│
└── ... (millions of accounts)
```

**How it works:**

1. Each account in the world state has a `storageRoot` — the root hash of its **storage trie**.
2. The storage trie is a **Modified Merkle Patricia Trie (MPT)** where:
   - **Path** = `keccak256(slot_number)` (hashed to distribute keys evenly)
   - **Leaf** = RLP-encoded slot value
3. Reading a slot means traversing the trie from root to leaf, following the path derived from the slot number.
4. Each internal node is a 32-byte hash that points to the next level. A full traversal from root to leaf typically touches **7-8 nodes**.

**Why this matters for you:**
- The trie structure explains why storage is expensive — it's a database lookup, not a RAM read.
- It explains Merkle proofs: you can prove a slot's value by providing the path from root to leaf.
- It explains why `keccak256` is everywhere in storage — the trie itself uses hashed paths for even distribution.

---

<a id="why-cold-costs"></a>
#### 🔍 Deep Dive: Why Cold Access Costs 2100 Gas

[Module 1](1-evm-fundamentals.md#warm-cold) showed you the numbers: SLOAD cold = 2100 gas, warm = 100 gas. Now you know *why*.

**Cold access (2100 gas):**
The slot hasn't been accessed in this transaction. The EVM must traverse the storage trie from scratch, loading 7-8 nodes from the node database (LevelDB, PebbleDB, or similar). Each node requires a database I/O operation — reading from disk or SSD. The 2100 gas charge reflects this I/O cost.

**Warm access (100 gas):**
The slot was already accessed earlier in this transaction. The trie nodes are cached in RAM from the first traversal. Now it's just a hash-table lookup in the access set — essentially free compared to disk I/O.

**SSTORE new slot (20,000 gas):**
Writing to a never-used slot means creating new trie nodes, computing new hashes at every level, and eventually writing everything to disk. This is the most expensive single operation in the EVM.

**The key insight:** Gas costs map to **real computational work** — disk reads, hash computations, and database writes. They aren't arbitrary numbers.

> **Recap:** See [Module 1 — EIP-2929 Deep Dive](1-evm-fundamentals.md#warm-cold) for access lists (EIP-2930) and the full warm/cold model.

#### 💼 Job Market Context

**"How does EVM storage work?"**
- Good: "It's a key-value store mapping 256-bit keys to 256-bit values, persisted in the state trie"
- Great: "Each contract has a 2^256 key-value store backed by a Merkle Patricia Trie in the world state. Cold access costs 2,100 gas because it requires loading trie nodes from disk. Warm access costs 100 gas because the node is cached. This is why Uniswap V2's reentrancy guard uses 1→2 instead of 0→1→0 — the SSTORE from non-zero to non-zero avoids the 20,000 gas creation cost"

🚩 **Red flag:** Not knowing the cold/warm distinction, or thinking storage is like a regular database

**Pro tip:** Being able to explain *why* storage costs what it does (trie traversal, disk I/O) signals deep EVM understanding that sets you apart from "I memorize gas tables" candidates

---

<a id="verkle"></a>
### 💡 Concept: Verkle Trees — What's Changing

Ethereum plans to migrate from Merkle Patricia Tries to **Verkle Trees** ([EIP-6800](https://eips.ethereum.org/EIPS/eip-6800)).

**What changes:**
- **Proofs shrink dramatically** — from ~1KB (Merkle) to ~150 bytes (Verkle). This uses polynomial commitments instead of hash-based proofs.
- **Stateless clients become viable** — a node can verify a block without storing the full state, just by checking the proof included with the block.
- **Gas costs may be restructured** — cold access might become cheaper because proof verification is more efficient.

**What stays the same:**
- The slot computation model (sequential assignment, keccak256 for mappings/arrays) is unchanged.
- Your Solidity and assembly code doesn't change.
- `sload`/`sstore` opcodes work identically.

**Bottom line:** Verkle trees change the infrastructure under your contract, not the contract itself. But understanding that the trie exists — and that it's being actively redesigned — is part of having complete EVM knowledge.

---

## 💡 SLOAD & SSTORE — The Full Picture

Module 1 showed you `sload(0)` to read the owner variable. Now we go deeper — the full cost model, the refund mechanics, and the write ordering patterns that production code uses.

---

<a id="sload-sstore-yul"></a>
### 💡 Concept: SLOAD & SSTORE in Yul

**The opcodes:**

```solidity
assembly {
    // Read: load 32 bytes from slot number `slot`
    let value := sload(slot)

    // Write: store 32 bytes at slot number `slot`
    sstore(slot, newValue)
}
```

Both operate on **raw 256-bit slot numbers**. No type safety, no bounds checking, no Solidity-level protections. You can read or write ANY slot — including slots that "belong" to other state variables.

💻 **Quick Try:**

```solidity
contract StorageBasic {
    uint256 public counter; // slot 0

    function increment() external {
        assembly {
            let current := sload(0)        // read slot 0
            sstore(0, add(current, 1))     // write slot 0
        }
    }
}
```

Deploy, call `increment()`, then check `counter()`. This is exactly what `counter++` compiles to — an SLOAD, ADD, SSTORE sequence.

> **Verify with forge inspect:**
> ```bash
> forge inspect StorageBasic storageLayout
> ```
> This shows the compiler's slot assignments. Use it to confirm your assumptions.

---

<a id="sstore-state-machine"></a>
#### 🔍 Deep Dive: The SSTORE Cost State Machine (EIP-2200 + EIP-3529)

SSTORE is not one gas cost — it's a **state machine** that depends on three values:

1. **Original value** — what the slot held at the start of the transaction
2. **Current value** — what the slot holds right now (may differ if already written in this tx)
3. **New value** — what you're writing

```
SSTORE Cost State Machine (post-London, EIP-3529)
═══════════════════════════════════════════════════

Is the slot warm?
├── No (cold) → Add 2,100 gas surcharge, then proceed as warm
└── Yes (warm) →
    │
    Is current == new? (no-op)
    ├── Yes → 100 gas (warm read cost only)
    └── No →
        │
        Is current == original? (first write in tx)
        ├── Yes →
        │   ├── original == 0? → 20,000 gas (CREATE: zero to nonzero)
        │   └── original != 0? →  2,900 gas (UPDATE: nonzero to nonzero)
        │
        └── No → 100 gas (already dirty — just update the journal)

Refund cases (credited at end of transaction):
─────────────────────────────────────────────────
• current != 0 AND new == 0      → +4,800 gas refund
• current != original AND new == original → restore refund:
    └── original == 0 → revoke the 4,800 refund
    └── original != 0 → +2,100 gas refund

Refund cap (EIP-3529): max refund = gas_used / 5
```

**The four cases you need to internalize:**

| Case | Example | Gas (warm) | Why |
|------|---------|-----------|-----|
| **CREATE** | 0 → 42 | 20,000 | New trie node created |
| **UPDATE** | 42 → 99 | 2,900 | Existing node modified |
| **DELETE** | 42 → 0 | 2,900 + 4,800 refund | Node removed from trie |
| **NO-OP** | 42 → 42 | 100 | Nothing changes |

#### 🔗 DeFi Pattern Connection

**The Uniswap V2 reentrancy guard optimization:**

OpenZeppelin's original pattern: `_status = _ENTERED` (0→1) at start, `_status = _NOT_ENTERED` (1→0) at end. This means:
- Entry: 20,000 gas (zero → nonzero CREATE)
- Exit: 2,900 gas + 4,800 refund (nonzero → zero DELETE)
- Net: ~18,100 gas

Uniswap V2 changed to: `unlocked = 2` (1→2) at start, `unlocked = 1` (2→1) at end:
- Entry: 2,900 gas (nonzero → nonzero UPDATE)
- Exit: 2,900 gas (nonzero → nonzero UPDATE)
- Net: 5,800 gas

**Savings: ~12,300 gas per call.** This works because the slot is never zero after deployment.

**EIP-3529 refund cap (post-London):**

Before London, the max refund was 1/2 of gas used. Gas token schemes (CHI, GST2) exploited this: write to storage when gas is cheap, clear it when gas is expensive to reclaim refunds. EIP-3529 reduced the cap to 1/5, killing the economic viability of gas tokens.

---

<a id="write-ordering"></a>
#### 🎓 Intermediate Example: Write Ordering Strategy

When a function reads and writes multiple slots, order matters for clarity and potential optimization:

```solidity
// Pattern: batch reads, then writes
function liquidate(address user) external {
    assembly {
        // ── READS (all sloads first) ──────────────
        let collateral := sload(collateralSlot)
        let debt := sload(debtSlot)
        let price := sload(priceSlot)
        let factor := sload(factorSlot)

        // ── COMPUTE ──────────────────────────────
        let health := div(mul(collateral, price), mul(debt, factor))

        // ── WRITES (all sstores last) ─────────────
        sstore(collateralSlot, sub(collateral, seized))
        sstore(debtSlot, sub(debt, repaid))
    }
}
```

**Why this pattern:**
- **Clarity:** All state reads are grouped, making it easy to audit what state the function depends on.
- **Gas:** Once a slot is warm (first SLOAD at 2,100 gas), subsequent reads are 100 gas. Grouping reads doesn't change gas, but grouping writes after computation prevents accidentally reading stale values from a slot you just wrote.
- **DeFi standard:** Lending protocols (Aave, Compound) and AMMs (Uniswap) follow this read-compute-write pattern universally.

#### 💼 Job Market Context

**"Why does the SSTORE cost depend on the original value?"**
- Good: "Gas reflects the work the trie must do — creating a node costs more than updating one."
- Great: "It's a three-state model: original, current, and new. The EVM tracks the original value per-transaction because restoring it (dirty → original) is cheaper than a fresh write. EIP-3529 capped refunds at 1/5 of gas used to kill gas token farming."

**"What happened with gas tokens?"**
- Good: "They exploited SSTORE refunds to bank gas when cheap and reclaim when expensive."
- Great: "CHI and GST2 wrote to storage (20,000 gas each) during low-gas periods, then cleared those slots during high-gas periods to claim refunds. Pre-London, the 50% refund cap made this profitable. EIP-3529 reduced it to 20%, making the scheme uneconomical."

#### ⚠️ Common Mistakes

- **Writing to slot 0 when you meant a mapping** — `sstore(0, value)` overwrites slot 0 directly. If slot 0 is the base slot for a mapping, you've just corrupted the length/sentinel. Always compute the derived slot with `keccak256`
- **Not checking the return value of `sload`** — `sload` returns 0 for uninitialized slots AND for slots explicitly set to 0. You can't distinguish "never written" from "set to zero" without additional bookkeeping
- **Forgetting SSTORE gas depends on current value** — Writing the same value that's already stored still costs gas (warm access: 100 gas). But writing a new value to a slot that's already non-zero costs 2,900 (not 20,000). Understanding the state machine saves significant gas

---

## 💡 Slot Computation — From Variables to Tries

This is the section Module 1 teased: how does the EVM know WHERE to store a mapping entry or an array element? The answer is `keccak256` — and understanding the exact formulas unlocks the ability to read any contract's storage from the outside.

---

<a id="sequential-slots"></a>
### 💡 Concept: State Variables — Sequential Assignment

State variables receive slots **sequentially** starting from slot 0, in declaration order:

```solidity
contract Example {
    uint256 public a;        // slot 0
    uint256 public b;        // slot 1
    address public owner;    // slot 2
    bool public paused;      // slot 2 (packed with owner! see below)
    uint256 public total;    // slot 3
}
```

**Packing rules:** Variables smaller than 32 bytes share a slot if they fit. In the example above, `owner` (20 bytes) and `paused` (1 byte) together use 21 bytes, which fits in one 32-byte slot. Variables are **right-aligned** within the slot and packed in declaration order.

```
Slot 2 layout:
Byte 31            12 11           0
┌────────────────────┬──────────────┐
│  unused (11 bytes) │ paused │ owner (20 bytes)  │
│  0x000000000000...  │  0x01  │ 0xAbCd...1234     │
└────────────────────┴──────────────┘
```

> **Note:** `bool` takes 1 byte, `address` takes 20 bytes. Together they fit in one 32-byte slot. A `uint256` after them starts a new slot because 32 + 21 > 32.

💻 **Quick Try:**

```bash
# Inspect any contract's storage layout
forge inspect Example storageLayout
```

This outputs JSON showing each variable's slot number and byte offset within the slot. Use it to verify your assumptions before writing assembly.

---

<a id="why-keccak"></a>
### 💡 Concept: Why keccak256 — Collision Resistance in 2^256 Space

Mappings and dynamic arrays can't use sequential slots — they have an unbounded number of entries. Instead, they use **keccak256** to compute slot numbers.

**The problem:** A `mapping(address => uint256)` could have entries for any of 2^160 addresses. You can't reserve sequential slots for all possible keys.

**The solution:** Hash the key with the mapping's base slot to produce a deterministic but "random" slot number:

```
slot_for_key = keccak256(abi.encode(key, baseSlot))
```

**Why this works:** keccak256 distributes outputs uniformly across 2^256 space. The probability of two different `(key, baseSlot)` pairs producing the same slot is ~2^-128 (birthday bound) — astronomically unlikely. In practice, collisions don't happen.

**Why NOT `key + baseSlot`?** Arithmetic would create predictable, overlapping ranges. Mapping A at slot 1 with key 0 would produce slot 1. Mapping B at slot 0 with key 1 would also produce slot 1. Collision. Hashing eliminates this by "scrambling" the output.

---

<a id="mapping-slots"></a>
### 💡 Concept: Mapping Slot Computation

For `mapping(KeyType => ValueType)` at base slot `p`:

```
slot(key) = keccak256(abi.encode(key, p))
```

Both `key` and `p` are left-padded to 32 bytes and concatenated (64 bytes total), then hashed.

**Step-by-step example:**

```solidity
contract Token {
    mapping(address => uint256) public balances; // slot 0
}
```

To read `balances[0xBEEF]`:

```
key  = 0x000000000000000000000000000000000000BEEF  (address, left-padded to 32 bytes)
slot = 0x0000000000000000000000000000000000000000000000000000000000000000  (base slot 0)

hash input = key ++ slot  (64 bytes)
slot(0xBEEF) = keccak256(hash_input)
```

**In Yul** (using scratch space from [Module 2](2-memory-calldata.md#scratch-hashing)):

```solidity
assembly {
    // Store key at scratch word 1, base slot at scratch word 2
    mstore(0x00, key)          // key in bytes 0x00-0x1f
    mstore(0x20, 0)            // base slot (0) in bytes 0x20-0x3f
    let slot := keccak256(0x00, 0x40)  // hash 64 bytes
    let balance := sload(slot)
}
```

This pattern — store two 32-byte values in scratch space, hash 64 bytes — is the canonical way to compute mapping slots in assembly.

---

<a id="mapping-derivation"></a>
#### 🔍 Deep Dive: Deriving the Mapping Formula

**Why `abi.encode(key, slot)` and not `abi.encodePacked(key, slot)`?**

`abi.encodePacked` for an address produces 20 bytes. For a uint256, 32 bytes. So `encodePacked(address_key, uint256_slot)` is 52 bytes, while `encodePacked(uint256_key, uint256_slot)` is 64 bytes. Different key types produce different-length inputs, which could create subtle collision scenarios.

`abi.encode` always pads to 32 bytes per value, so the hash input is always exactly 64 bytes regardless of key type. This consistency eliminates any ambiguity.

**Why is the base slot the SECOND argument?**

Convention, but it has a useful property: for nested mappings, the result of the first hash becomes the "base slot" for the next level. Putting the slot second means the chaining reads naturally:

```
// mapping(address => mapping(uint256 => bool)) at slot 5
level1 = keccak256(abi.encode(outerKey, 5))        // base slot for inner mapping
level2 = keccak256(abi.encode(innerKey, level1))    // final slot
```

The slot "flows" through the second position at each level.

#### ⚠️ Common Mistakes

- **Wrong argument order in keccak256** — For mappings, it's `keccak256(abi.encode(key, baseSlot))` — key first, slot second. Reversing them computes a completely different (but valid) slot, leading to silent data corruption
- **Using `encodePacked` instead of `encode`** — Solidity uses `abi.encode` (32-byte padded) for slot derivation, not `abi.encodePacked`. If you use packed encoding in assembly, you'll compute wrong slots that don't match Solidity's getters
- **Assuming mapping slots are sequential** — Each mapping entry lives at `keccak256(key, slot)`, scattered across the 2^256 space. There's no way to enumerate all keys without off-chain indexing (events)

#### 💼 Job Market Context

**"How do you compute a mapping's storage slot?"**
- Good: "`keccak256(abi.encode(key, baseSlot))`"
- Great: "The slot is `keccak256(abi.encode(key, mappingSlot))`. The key goes first, the mapping's base slot second, both padded to 32 bytes. This scatters entries uniformly across the 2^256 space, making collisions astronomically unlikely. For nested mappings like `mapping(address => mapping(uint => uint))`, you apply the formula twice: first hash the outer key with the base slot, then hash the inner key with that result. This is how `cast storage` and block explorers read arbitrary mapping values"

🚩 **Red flag:** Not being able to derive the formula or confusing the argument order

**Pro tip:** Show you can use `forge inspect Contract storage-layout` and `cast storage <address> <slot>` to read any on-chain mapping — this is a practical skill auditors use daily

---

<a id="array-slots"></a>
### 💡 Concept: Dynamic Array Slot Computation

For `Type[] storage arr` at base slot `p`:

- **Length** is stored at slot `p` itself: `arr.length = sload(p)`
- **Element `i`** is at slot `keccak256(abi.encode(p)) + i`

```
Dynamic Array Layout
═════════════════════

Slot p:                    array length
                            │
Slot keccak256(p) + 0:     element 0
Slot keccak256(p) + 1:     element 1
Slot keccak256(p) + 2:     element 2
...
Slot keccak256(p) + n-1:   element n-1
```

**Why hash the base slot?** Array elements need **contiguous slots** (for efficient iteration), but those slots must not conflict with other state variables' sequential slots (0, 1, 2...). Hashing the base slot "teleports" the element region to a random location in the 2^256 space, far from the sequential region.

**In Yul:**

```solidity
assembly {
    let length := sload(baseSlot)          // array length

    mstore(0x00, baseSlot)                 // hash input: base slot
    let dataStart := keccak256(0x00, 0x20) // note: only 32 bytes, not 64

    let element_i := sload(add(dataStart, i))
}
```

> **Note:** Array slot computation hashes only 32 bytes (`keccak256(abi.encode(p))`), while mapping slot computation hashes 64 bytes (`keccak256(abi.encode(key, p))`). This is because the array base slot alone is sufficient — the index is added arithmetically.

#### 💼 Job Market Context

**"Where is a dynamic array's data stored?"**
- Good: "The length is at the base slot, elements start at `keccak256(baseSlot)`"
- Great: "The base slot stores the array length. The first element lives at `keccak256(abi.encode(baseSlot))`, and element `i` is at that value plus `i`. This means arrays can overlap with mapping slots in theory, but the probability is negligible because both use keccak256. For `bytes` and `string`, short values (≤31 bytes) are packed into the base slot itself with the length in the lowest byte — this is the 'short string optimization' that saves a full SLOAD for common cases"

🚩 **Red flag:** Not knowing the short string optimization, or thinking arrays are stored sequentially starting at their declaration slot

---

<a id="nested-slots"></a>
### 💡 Concept: Nested Structures — Mappings of Mappings, Mappings of Structs

**Mapping of mappings:**

```solidity
mapping(address => mapping(uint256 => uint256)) public nested; // slot 3
```

To read `nested[0xCAFE][7]`:

```
Step 1: Outer mapping
  level1_slot = keccak256(abi.encode(0xCAFE, 3))

Step 2: Inner mapping (using level1_slot as the base)
  final_slot = keccak256(abi.encode(7, level1_slot))

value = sload(final_slot)
```

In Yul:

```solidity
assembly {
    // Level 1: hash(outerKey, baseSlot)
    mstore(0x00, outerKey)
    mstore(0x20, 3)                        // base slot of outer mapping
    let level1 := keccak256(0x00, 0x40)

    // Level 2: hash(innerKey, level1)
    mstore(0x00, innerKey)
    mstore(0x20, level1)
    let finalSlot := keccak256(0x00, 0x40)

    let value := sload(finalSlot)
}
```

**Mapping of structs:**

```solidity
struct UserData {
    uint256 balance;    // offset 0
    uint256 debt;       // offset 1
    uint256 lastUpdate; // offset 2
}
mapping(address => UserData) public users; // slot 4
```

To read `users[addr].debt`:

```
base = keccak256(abi.encode(addr, 4))   // base slot for this user's struct
debt_slot = base + 1                     // offset 1 within the struct
value = sload(debt_slot)
```

Struct fields occupy **sequential slots from the computed base**. Field 0 at base, field 1 at base+1, field 2 at base+2. The packing rules from [sequential assignment](#sequential-slots) apply within each struct too.

---

<a id="trace-layout"></a>
#### 🎓 Intermediate Example: Trace Aave V3's ReserveData Layout

Aave V3's core data structure is `mapping(address => DataTypes.ReserveData)` in the Pool contract. `ReserveData` is a struct with ~15 fields spanning multiple slots.

Let's trace how to read the `liquidityIndex` for WETH:

```solidity
// From Aave V3 DataTypes.sol (simplified)
struct ReserveData {
    ReserveConfigurationMap configuration;  // offset 0 (1 slot, bitmap)
    uint128 liquidityIndex;                 // offset 1 (packed with next field)
    uint128 currentLiquidityRate;           // offset 1 (packed in same slot)
    uint128 variableBorrowIndex;            // offset 2 (packed with next field)
    uint128 currentVariableBorrowRate;      // offset 2 (packed in same slot)
    // ... more fields at offset 3, 4, ...
}
```

**Step 1:** Find the mapping's base slot. Use `forge inspect` or read Aave's code. Suppose the mapping is at slot 52.

**Step 2:** Compute the struct base for WETH (`0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`):
```
structBase = keccak256(abi.encode(WETH_ADDRESS, 52))
```

**Step 3:** `liquidityIndex` is at offset 1. It's a `uint128` packed in the low 128 bits of that slot:
```
slot = structBase + 1
packed = sload(slot)
liquidityIndex = and(packed, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)  // low 128 bits
```

**Step 4:** Verify with `cast storage`:
```bash
# Compute the slot off-chain, then read it
cast storage <AAVE_POOL_ADDRESS> <computed_slot> --rpc-url https://eth.llamarpc.com
```

This is the power of understanding slot computation: you can read any protocol's internal state directly, without needing an ABI or getter function.

---

<a id="minus-one"></a>
### 💡 Concept: The -1 Trick — Preimage Attack Prevention

[Part 1 Module 6](../part1/6-proxy-patterns.md) introduced ERC-1967 proxy slots:

```
implementation_slot = keccak256("eip1967.proxy.implementation") - 1
// = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
```

**Why subtract 1?**

If the slot were exactly `keccak256("eip1967.proxy.implementation")`, an attacker could observe that the slot has a **known keccak256 preimage** (the string `"eip1967.proxy.implementation"`). While this doesn't directly enable an attack, it creates a theoretical risk:

The Solidity compiler computes mapping slots as `keccak256(abi.encode(key, baseSlot))`. If a carefully crafted implementation contract has a mapping whose `(key, baseSlot)` combination happens to hash to the same value as `keccak256("eip1967.proxy.implementation")`, the mapping entry would collide with the proxy's implementation slot.

**Subtracting 1 eliminates this risk.** The final slot is `keccak256(X) - 1`, which has no known preimage under keccak256. Finding a `Y` such that `keccak256(Y) = keccak256(X) - 1` requires breaking keccak256's preimage resistance.

ERC-7201 uses the same principle (see [below](#erc-7201)) with an additional hashing step.

#### 💼 Job Market Context

**"Why does ERC-7201 subtract 1 before hashing?"**
- Good: "To prevent storage collisions between namespaces and regular variable slots"
- Great: "The -1 trick prevents preimage attacks. If you hash a namespace string directly, someone could craft a contract where a regular variable's sequential slot number happens to equal `keccak256(namespace)`. By subtracting 1 before the final hash, you force the input to be `keccak256(string) - 1`, which has no known preimage — making it impossible to construct a colliding sequential slot. Vyper uses the same principle in its storage layout"

🚩 **Red flag:** Not knowing what a preimage attack is in this context

**Pro tip:** ERC-7201 is increasingly asked about in interviews for upgradeable contract positions — it's the modern replacement for unstructured storage

---

## 💡 Storage Packing in Assembly

You know Solidity auto-packs small variables ([sequential slots](#sequential-slots) above). Now you'll do it by hand in assembly — the same patterns used by Aave V3's bitmap configuration, Uniswap V3's Slot0, and every gas-optimized protocol.

---

<a id="manual-packing"></a>
### 💡 Concept: Manual Pack/Unpack with Bit Operations

**Packing two uint128 values into one 256-bit slot:**

```
Bit 255                128 127                  0
┌────────────────────────┬────────────────────────┐
│      high (uint128)    │      low (uint128)     │
└────────────────────────┴────────────────────────┘
```

**Pack:**
```solidity
assembly {
    let packed := or(shl(128, high), and(low, 0xffffffffffffffffffffffffffffffff))
    sstore(slot, packed)
}
```

**Unpack:**
```solidity
assembly {
    let packed := sload(slot)
    let low  := and(packed, 0xffffffffffffffffffffffffffffffff)  // mask low 128 bits
    let high := shr(128, packed)                                  // shift right 128 bits
}
```

> You saw this concept in Part 1's BalanceDelta (two `int128` values in one `int256`). Now you're implementing the raw assembly version.

**Packing address (20 bytes) + uint96 into one slot:**

```
Bit 255         96 95              0
┌──────────────────┬──────────────────┐
│  address (160b)  │   uint96 (96b)   │
└──────────────────┴──────────────────┘
```

```solidity
assembly {
    // Pack
    let packed := or(shl(96, addr), and(value, 0xffffffffffffffffffffffff))
    sstore(slot, packed)

    // Unpack address (high 160 bits)
    let addr := shr(96, sload(slot))

    // Unpack uint96 (low 96 bits)
    let val := and(sload(slot), 0xffffffffffffffffffffffff)
}
```

The address mask is `0xffffffffffffffffffffffff` (24 hex chars = 96 bits). The address is shifted left by 96 bits to occupy the high 160 bits.

---

<a id="read-modify-write"></a>
#### 🔍 Deep Dive: Read-Modify-Write Pattern

The most important assembly storage pattern: **updating one field without touching the others**.

```
Goal: Update the "low" uint128 field, keep "high" unchanged.

Step 1: SLOAD        → 0xAAAAAAAA_BBBBBBBB  (high=AAAA, low=BBBB)

Step 2: CLEAR field  → 0xAAAAAAAA_00000000  (AND with NOT mask)
    mask for low 128 bits = 0xFFFFFFFF_FFFFFFFF (128 ones)
    inverted mask          = 0xFFFFFFFF_00000000 (128 ones, 128 zeros)
    result = AND(packed, inverted_mask)

Step 3: SHIFT new    → 0x00000000_CCCCCCCC  (new value in position)
    new_low already fits in low 128 bits, no shift needed

Step 4: OR together  → 0xAAAAAAAA_CCCCCCCC  (combined)
    result = OR(cleared, shifted_new)

Step 5: SSTORE       → written back to slot
```

**Full Yul code for updating the low field:**

```solidity
assembly {
    let packed := sload(slot)

    // Clear the low 128 bits: AND with a mask that has 1s in the high 128, 0s in the low 128
    let mask := not(0xffffffffffffffffffffffffffffffff) // = 0xFFFF...0000 (128 high bits set)
    let cleared := and(packed, mask)

    // OR in the new value (already in the low 128 bit position)
    let updated := or(cleared, and(newLow, 0xffffffffffffffffffffffffffffffff))

    sstore(slot, updated)
}
```

> **Common audit finding:** Off-by-one in shift amounts or mask widths. If you clear 127 bits instead of 128, the highest bit of the low field "bleeds" into the high field. Always verify masks with small test values.

#### ⚠️ Common Mistakes

- **Off-by-one in shift amounts** — Packing a `uint96` next to an `address` (160 bits) requires `shl(160, value)`, not `shl(96, value)`. The shift amount is the *position* of the field, not its *width*. Draw the bit layout before writing the code
- **Forgetting to clear before OR-ing** — The read-modify-write pattern requires clearing the target bits first with `and(slot, not(mask))`. If you skip the clear step and just OR the new value, you'll get corrupted data whenever the new value has fewer set bits than the old one
- **Inverted masks** — `not(shl(160, 0xffffffffffffffffffffffff))` clears bits 160-255. Getting the mask width or position wrong silently corrupts adjacent fields. Always verify with small test values

---

<a id="aave-case-study"></a>
### 💡 Concept: Aave V3 ReserveConfiguration Case Study

Aave V3 packs an entire reserve's configuration into a **single uint256 bitmap**:

```
Aave V3 ReserveConfigurationMap (first 64 bits shown)
Bit 63                48 47                32 31                16 15                 0
┌─────────────────────┬─────────────────────┬─────────────────────┬─────────────────────┐
│  liq. bonus (16b)   │  liq. threshold(16b)│   decimals + flags  │      LTV (16b)      │
└─────────────────────┴─────────────────────┴─────────────────────┴─────────────────────┘
```

The full 256-bit word contains: LTV, liquidation threshold, liquidation bonus, decimals, active flag, frozen flag, borrowable flag, stable rate flag, reserve factor, borrowing cap, supply cap, and more — all in one slot.

> [Part 2 Module 4](../part2/4-lending-advanced.md) showed the Solidity-level configuration. Here's how to access it in assembly.

**Reading LTV (bits 0-15):**
```solidity
assembly {
    let config := sload(configSlot)
    let ltv := and(config, 0xFFFF)  // mask low 16 bits
}
```

**Reading liquidation threshold (bits 16-31):**
```solidity
assembly {
    let config := sload(configSlot)
    let liqThreshold := and(shr(16, config), 0xFFFF)  // shift right 16, mask 16 bits
}
```

**Setting LTV (read-modify-write):**
```solidity
assembly {
    let config := sload(configSlot)
    let cleared := and(config, not(0xFFFF))   // clear bits 0-15
    let updated := or(cleared, and(newLTV, 0xFFFF))  // set new LTV
    sstore(configSlot, updated)
}
```

**One SLOAD to read everything.** That single storage read gives you access to 15+ configuration parameters. Without packing, this would be 15 separate SLOADs — up to 31,500 gas cold vs 2,100 gas for the packed read.

> **Production code:** [Aave V3 ReserveConfiguration.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol)

---

<a id="gas-packed-vs-unpacked"></a>
#### 🔍 Deep Dive: Gas Analysis — Packed vs Unpacked

| Scenario | Unpacked (5 separate slots) | Packed (1 slot + bit math) |
|----------|----------------------------|---------------------------|
| Cold read all 5 | 5 x 2,100 = **10,500 gas** | 1 x 2,100 + ~50 shifts = **~2,150 gas** |
| Warm read all 5 | 5 x 100 = **500 gas** | 1 x 100 + ~50 shifts = **~150 gas** |
| Update 1 field | 1 x 2,900 = **2,900 gas** | 1 x 2,100 (read) + 2,900 (write) + ~50 = **~5,050 gas** |

**The tradeoff is clear:**
- **Packing wins big for read-heavy data** (configuration, parameters, metadata). Aave V3 reads reserve configuration on every borrow, repay, and liquidation — the savings compound.
- **Packing costs more for write-heavy data** where you update individual fields frequently, because every update requires read-modify-write (an extra SLOAD).

**Rule of thumb:** Pack data that's **written rarely and read often** (protocol configuration, token metadata, access control flags). Keep data that's **written frequently** in separate slots (balances, counters, timestamps).

#### 💼 Job Market Context

**"Walk me through how you'd pack configuration data in a protocol."**
- Good: Describe the mask/shift pattern for packing multiple fields into one uint256.
- Great: Discuss when packing is worth it (read-heavy config) vs when it's not (frequently-updated individual fields). Reference Aave V3 as the canonical example. Mention that packing also reduces cold access overhead for functions that need multiple config values.

**Interview red flag:** Packing everything blindly without considering write frequency.

---

## 💡 Transient Storage in Assembly

You learned TLOAD/TSTORE conceptually in [Part 1](../part1/1-solidity-modern.md) and used the `transient` keyword. Now the assembly patterns — and why the flat 100 gas cost changes everything.

---

<a id="tload-tstore"></a>
### 💡 Concept: TLOAD & TSTORE Yul Patterns

**Syntax:**

```solidity
assembly {
    tstore(slot, value)        // write to transient slot
    let val := tload(slot)     // read from transient slot
}
```

**Key differences from SLOAD/SSTORE:**

| Property | SLOAD/SSTORE | TLOAD/TSTORE |
|----------|-------------|--------------|
| Gas cost | 100-20,000 (warm/cold/create) | **Always 100** |
| Cold/warm? | Yes (EIP-2929) | **No** |
| Refunds? | Yes (EIP-3529) | **No** |
| Persists? | Across transactions | **Cleared at end of transaction** |
| In storage trie? | Yes | **No** (separate transient map) |

**Reentrancy guard in assembly:**

```solidity
function protectedFunction() external {
    assembly {
        if tload(0) { revert(0, 0) }  // already entered? revert
        tstore(0, 1)                   // set lock
    }

    // ... function body ...

    assembly {
        tstore(0, 0)                   // clear lock
    }
}
```

**Cost comparison:** 200 gas total (set + clear) vs ~5,800+ gas with SSTORE-based guard. That's a 29x reduction.

> No refund on clearing — unlike SSTORE where 1→0 gives 4,800 gas back. But the flat 100 gas makes the total cost predictable and much cheaper overall.

---

<a id="uniswap-v4-transient"></a>
#### 🔍 Uniswap V4 Assembly Walkthrough

Uniswap V4's PoolManager uses transient storage for **flash accounting** — tracking per-currency balance changes across a multi-step callback:

```solidity
// Simplified from Uniswap V4 PoolManager
function _accountDelta(Currency currency, int256 delta) internal {
    assembly {
        // Compute transient slot for this currency's delta
        mstore(0x00, currency)
        mstore(0x20, CURRENCY_DELTA_SLOT)
        let slot := keccak256(0x00, 0x40)

        // Read current delta, add new delta
        let current := tload(slot)
        let updated := add(current, delta)
        tstore(slot, updated)
    }
}
```

**The pattern:**
1. Compute a transient slot using the same keccak256 formula as mapping slots.
2. Read the current delta with `tload`.
3. Update and write back with `tstore`.
4. At the end of the `unlock()` callback, verify all deltas are zero (settlement).

**Why this only works with transient storage:** A single swap touches multiple currencies. With SSTORE, each delta update would cost 2,900-20,000 gas. With TSTORE at 100 gas, tracking deltas per-currency per-swap is economically viable. This enables Uniswap V4's singleton architecture where all pools share one contract.

#### 🔗 DeFi Pattern Connection

Transient storage use cases in production DeFi:
- **Flash accounting** (Uniswap V4) — track balance deltas across callback sequences
- **Reentrancy locks** — 29x cheaper than SSTORE-based guards
- **Callback context** — pass data between caller and callback without storage writes
- **Temporary approvals** — grant one-time permission within a transaction

#### 💼 Job Market Context

**"What's the difference between transient storage and regular storage?"**
- Good: "Transient storage is cleared at the end of each transaction, so it costs less gas"
- Great: "TLOAD/TSTORE (EIP-1153) provide a key-value store that's transaction-scoped — it persists across internal calls within a transaction but is wiped when the transaction ends. It costs 100 gas for both read and write (no cold/warm distinction, no refund complexity). The primary use case is replacing storage-based reentrancy guards and enabling flash accounting patterns like Uniswap V4's delta tracking, where you need cross-call state without permanent storage costs"

🚩 **Red flag:** Confusing transient storage with memory, or not knowing it persists across internal calls

**Pro tip:** Uniswap V4's flash accounting (TSTORE deltas that must net to zero) is the canonical interview example — be ready to trace the flow

---

## 💡 Production Storage Patterns

Now that you understand slot computation and packing, here are the production patterns that combine these primitives for real-world use.

---

<a id="erc-1967-assembly"></a>
### 💡 Concept: ERC-1967 Proxy Slots in Assembly

[Part 1 Module 6](../part1/6-proxy-patterns.md) covered ERC-1967 conceptually. Here's how proxy contracts actually access these slots:

```solidity
// From OpenZeppelin's Proxy.sol (simplified)
bytes32 constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
// = keccak256("eip1967.proxy.implementation") - 1

function _implementation() internal view returns (address impl) {
    assembly {
        impl := sload(IMPLEMENTATION_SLOT)
    }
}

function _setImplementation(address newImpl) internal {
    assembly {
        sstore(IMPLEMENTATION_SLOT, newImpl)
    }
}
```

The constant is precomputed — no keccak256 at runtime. The `-1` subtraction happened off-chain when the standard was defined. At the EVM level, it's just an SLOAD/SSTORE at a specific slot number.

The proxy's `fallback()` function reads this slot to find the implementation, then uses `delegatecall` to forward the call. Module 5 covers the `delegatecall` pattern in detail.

#### 💼 Job Market Context

**"How do proxy contracts store the implementation address?"**
- Good: "At a specific storage slot defined by ERC-1967"
- Great: "ERC-1967 defines the implementation slot as `bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)`. The -1 prevents preimage attacks (same trick as ERC-7201). In assembly, the proxy reads this with `sload(IMPLEMENTATION_SLOT)` and delegates with `delegatecall`. The slot is constant and known, which is how block explorers detect and display proxy implementations automatically"

🚩 **Red flag:** Not knowing the slot constant or why it uses keccak256-minus-1

**Pro tip:** Write `sload(0x360894...)` from memory in interviews — it shows you've actually worked with proxy assembly, not just used OpenZeppelin's wrapper

---

<a id="erc-7201"></a>
### 💡 Concept: ERC-7201 Namespaced Storage

[Part 1 Module 6](../part1/6-proxy-patterns.md) mentioned ERC-7201 briefly. Here's the full picture — this is the modern replacement for `__gap` patterns.

**The problem with `__gap`:**
```solidity
contract StorageV1 {
    uint256 public value;
    uint256[49] private __gap;  // reserve 49 slots for future upgrades
}
```

Gaps are fragile. If you add 3 variables and forget to reduce the gap by 3, all subsequent slots shift and you get silent storage corruption. This has caused real exploits (Audius governance, ~$6M).

**ERC-7201's solution: namespaced storage**

Instead of sequential slots with gaps, each module gets its own deterministic base slot computed from a namespace string:

```
Formula:
  keccak256(abi.encode(uint256(keccak256("namespace.id")) - 1)) & ~bytes32(uint256(0xff))
```

**Step-by-step derivation:**

```
1. Hash the namespace:          h = keccak256("openzeppelin.storage.ERC20")
2. Subtract 1:                  h' = h - 1     (preimage attack prevention)
3. Encode as uint256:           encoded = abi.encode(uint256(h'))
4. Hash again:                  slot = keccak256(encoded)
5. Clear last byte:             slot = slot & ~0xFF

Why clear the last byte?
  The struct's fields occupy sequential slots: slot, slot+1, slot+2...
  Clearing the last byte (zeroing bits 0-7) means the base slot is aligned
  to a 256-slot boundary. This guarantees that up to 256 fields won't
  overflow into another namespace's region.
```

**OpenZeppelin's pattern:**

```solidity
/// @custom:storage-location erc7201:openzeppelin.storage.ERC20
struct ERC20Storage {
    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;
    uint256 _totalSupply;
}

// Precomputed: keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~0xff
bytes32 private constant ERC20_STORAGE_LOCATION =
    0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

function _getERC20Storage() private pure returns (ERC20Storage storage $) {
    assembly {
        $.slot := ERC20_STORAGE_LOCATION
    }
}
```

**Why this is better than `__gap`:**
- Each module's storage is at a deterministic, non-colliding location.
- Adding fields to a struct doesn't shift other modules' slots.
- No gap math to maintain — no risk of miscalculation.
- The `@custom:storage-location` annotation lets tools verify the layout automatically.

#### 💼 Job Market Context

**"How does ERC-7201 prevent storage collisions in upgradeable contracts?"**
- Good: "It uses a hash-based namespace so different facets don't clash"
- Great: "ERC-7201 computes a base slot as `keccak256(abi.encode(uint256(keccak256(namespace_id)) - 1)) & ~bytes32(uint256(0xff))`. The inner hash maps the namespace string to a unique seed, subtracting 1 prevents preimage attacks, the outer hash creates the actual base slot, and the `& ~0xff` mask aligns to a 256-byte boundary so that sequential struct fields can follow naturally. All struct members are at `base + offset`, making the layout predictable and collision-free across independent storage namespaces"

🚩 **Red flag:** Using string-based storage slots without understanding the collision prevention mechanism

**Pro tip:** OpenZeppelin's upgradeable contracts use ERC-7201 by default since v5 — knowing the formula derivation step-by-step is interview gold for any upgradeable contract role

---

<a id="sstore2"></a>
### 💡 Concept: SSTORE2 — Bytecode as Immutable Storage

Solady introduced an alternative storage pattern: **deploy data as contract bytecode**, then read it with `EXTCODECOPY`.

**The insight:** Contract bytecode is immutable. `EXTCODECOPY` costs 3 gas per 32-byte word (after the base cost). Compare to SLOAD at 2,100 gas cold per 32 bytes.

**Write (one-time):**
```solidity
// Deploy a contract whose bytecode IS the data
// CREATE opcode: deploy code that returns the data as runtime code
address pointer = SSTORE2.write(data);
```

**Read:**
```solidity
// Read the data back from the contract's bytecode
bytes memory data = SSTORE2.read(pointer);
// Under the hood: EXTCODECOPY(pointer, destOffset, dataOffset, size)
```

**Gas comparison for reading 1KB:**
| Method | Cost |
|--------|------|
| 32 separate SLOADs (cold) | 32 x 2,100 = **67,200 gas** |
| EXTCODECOPY 1KB | ~2,600 (base) + 32 x 3 = **~2,700 gas** |

**25x cheaper reads** for large immutable data.

**When to use:**
- Merkle trees for airdrops (large, written once, read many times)
- Lookup tables, configuration blobs, static metadata
- Any data that's immutable after deployment

**When NOT to use:** Data that needs to change. Bytecode is immutable — you can't update it.

> **Production code:** [Solady SSTORE2](https://github.com/vectorized/solady/blob/main/src/utils/SSTORE2.sol)

#### 💼 Job Market Context

**"When would you use SSTORE2 instead of regular storage?"**
- Good: "When you need to store large immutable data cheaply"
- Great: "SSTORE2 deploys data as a contract's bytecode using CREATE, then reads it with EXTCODECOPY. Writing costs contract deployment gas (~200 gas/byte), but reading is only 2,600 base + 3 gas/word via EXTCODECOPY vs. 2,100 per 32-byte SLOAD. For data larger than ~96 bytes that never changes, SSTORE2 is cheaper to read. Solady and SSTORE2 library use this for on-chain metadata, Merkle trees, and any large blob storage. The trade-off: data is immutable once deployed"

🚩 **Red flag:** Not knowing that SSTORE2 data is immutable (it's bytecode, not storage)

**Pro tip:** SSTORE2 is a favorite interview topic because it tests understanding of CREATE opcode, bytecode structure, and gas economics simultaneously

---

<a id="storage-proofs"></a>
### 💡 Concept: Storage Proofs and Reading Any Contract's Storage

**`eth_getProof`** is a JSON-RPC method that returns a **Merkle proof** for a specific storage slot. Given the proof, anyone can verify the slot's value without trusting the RPC node.

**Why this matters for DeFi:**
- **L2 bridges** verify L1 state by checking storage proofs submitted on-chain.
- **Optimistic rollups** use proofs in fraud challenges.
- **Cross-chain oracles** prove that a value exists in another chain's storage.

**Practical tools for reading storage:**

```bash
# Read any slot from any contract
cast storage <address> <slot> --rpc-url <url>

# Read with a storage proof
cast proof <address> <slot> --rpc-url <url>

# Inspect a contract's slot layout (compiled contract)
forge inspect <Contract> storageLayout
```

**Combining them:** Use `forge inspect` to find the slot number for a variable, then `cast storage` to read the live value from mainnet. This is how auditors and researchers read protocol state without relying on getter functions.

---

<a id="how-to-study"></a>
### 📖 How to Study Storage-Heavy Contracts

1. **Start with `forge inspect storageLayout`** — map out all slots and their byte offsets within slots.
2. **Identify packed slots** — look for multiple variables sharing one slot (variables smaller than 32 bytes).
3. **Trace mapping/array formulas** — for each mapping, note the base slot and compute example entries with `cast keccak`.
4. **Draw the packing diagram** — for packed slots, sketch which bits hold which fields.
5. **Read the assembly getters/setters** — now you understand what every shift, mask, and hash is doing.
6. **Verify with `cast storage`** — spot-check your computed slots against live chain data.

**Don't get stuck on:** Trie internals. Focus on slot computation and packing first — that's what you need for reading and writing assembly. The trie exists to give you the mental model for gas costs.

---

<a id="exercise1"></a>
## 🎯 Build Exercise: SlotExplorer

**Workspace:** [`src/part4/module3/exercise1-slot-explorer/SlotExplorer.sol`](../workspace/src/part4/module3/exercise1-slot-explorer/SlotExplorer.sol) | [`test/.../SlotExplorer.t.sol`](../workspace/test/part4/module3/exercise1-slot-explorer/SlotExplorer.t.sol)

Compute and read storage slots for variables, mappings, arrays, and nested mappings using inline assembly. The contract has pre-populated state — your assembly must find and read the correct slots.

**What you'll implement:**
1. `readSimpleSlot()` — read a uint256 state variable at slot 0 via `sload`
2. `readMappingSlot(address)` — compute a mapping slot with `keccak256` in scratch space and `sload`
3. `readArraySlot(uint256)` — compute a dynamic array element slot and `sload`
4. `readNestedMappingSlot(address, uint256)` — chain two `keccak256` computations for a nested mapping
5. `writeToMappingSlot(address, uint256)` — compute a mapping slot and `sstore`, verifiable via the Solidity getter

**🎯 Goal:** Internalize the slot computation formulas so deeply that you can read any contract's storage layout.

Run: `FOUNDRY_PROFILE=part4 forge test --match-contract SlotExplorerTest -vvv`

---

<a id="exercise2"></a>
## 🎯 Build Exercise: StoragePacker

**Workspace:** [`src/part4/module3/exercise2-storage-packer/StoragePacker.sol`](../workspace/src/part4/module3/exercise2-storage-packer/StoragePacker.sol) | [`test/.../StoragePacker.t.sol`](../workspace/test/part4/module3/exercise2-storage-packer/StoragePacker.t.sol)

Pack, unpack, and update fields within packed storage slots using bit operations in assembly. Practice the read-modify-write pattern that production protocols use for gas-efficient configuration storage.

**What you'll implement:**
1. `packTwo(uint128, uint128)` — pack two uint128 values into one slot using `shl`/`or`
2. `readLow()` / `readHigh()` — extract individual fields using `and`/`shr`
3. `updateLow(uint128)` / `updateHigh(uint128)` — update one field without corrupting the other (read-modify-write)
4. `packMixed(address, uint96)` / `readAddr()` / `readUint96()` — address + uint96 packing
5. `initTriple(...)` / `incrementCounter()` — increment a packed uint64 counter without corrupting adjacent fields

**🎯 Goal:** Build the muscle memory for bit-level storage manipulation that Aave V3, Uniswap V3, and every gas-optimized protocol uses.

Run: `FOUNDRY_PROFILE=part4 forge test --match-contract StoragePackerTest -vvv`

---

<a id="summary"></a>
## 📋 Key Takeaways: Storage Deep Dive

**✓ The Storage Model:**
- Each contract has a 2^256 sparse key-value store backed by a Merkle Patricia Trie
- Cold access (2100 gas) = trie traversal from disk; warm access (100 gas) = cached in RAM
- Verkle trees will change the trie structure but not slot computation

**✓ SLOAD & SSTORE:**
- `sload(slot)` reads, `sstore(slot, value)` writes — raw 256-bit operations
- SSTORE cost depends on original/current/new value state machine (EIP-2200)
- Refund cap: max 1/5 of gas used (EIP-3529)
- Batch reads before writes for clarity and gas efficiency

**✓ Slot Computation:**
- State variables: sequential from slot 0 (with packing for sub-32-byte types)
- Mappings: `keccak256(abi.encode(key, baseSlot))` — 64 bytes hashed
- Dynamic arrays: length at `baseSlot`, elements at `keccak256(abi.encode(baseSlot)) + index`
- Nested: chain the hash formulas; structs use sequential offsets from the computed base
- The `-1` trick prevents preimage attacks on proxy storage slots

**✓ Storage Packing:**
- Pack: `shl` + `or` to combine fields into one slot
- Unpack: `shr` + `and` to extract individual fields
- Read-modify-write: load -> clear with inverted mask -> shift new value -> or -> store
- Pack read-heavy data (config, parameters); keep write-heavy data in separate slots

**✓ Transient Storage:**
- `tload`/`tstore`: always 100 gas, no warm/cold, no refunds, cleared per transaction
- 29x cheaper reentrancy guards; enables flash accounting patterns

**✓ Production Patterns:**
- ERC-1967: constant proxy slots accessed via `sload`/`sstore`
- ERC-7201: namespaced storage eliminates `__gap` fragility
- SSTORE2: immutable data stored as bytecode — 25x cheaper reads for large data
- Storage proofs: `eth_getProof` enables trustless cross-chain state verification

**Key formulas to remember:**
- Mapping: `keccak256(abi.encode(key, baseSlot))`
- Array element: `keccak256(abi.encode(baseSlot)) + index`
- ERC-7201: `keccak256(abi.encode(uint256(keccak256("ns")) - 1)) & ~bytes32(uint256(0xff))`

**Next:** [Module 4 — Control Flow & Functions](4-control-flow.md) — if/switch/for in Yul, function dispatch, and Yul functions.

---

<a id="resources"></a>
## 📚 Resources

### Essential References
- [Solidity Docs — Storage Layout](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html) — Official specification for slot assignment, packing, and mapping/array formulas
- [Solidity Docs — Layout of Mappings and Arrays](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#mappings-and-dynamic-arrays) — Detailed formulas with examples
- [evm.codes — SLOAD](https://www.evm.codes/#54) | [SSTORE](https://www.evm.codes/#55) | [TLOAD](https://www.evm.codes/#5c) | [TSTORE](https://www.evm.codes/#5d) — Interactive opcode reference

### EIPs Referenced
- [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) — Standard proxy storage slots
- [EIP-2200](https://eips.ethereum.org/EIPS/eip-2200) — SSTORE gas cost state machine (Istanbul)
- [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929) — Cold/warm access costs (Berlin)
- [EIP-3529](https://eips.ethereum.org/EIPS/eip-3529) — Reduced SSTORE refunds (London)
- [EIP-7201](https://eips.ethereum.org/EIPS/eip-7201) — Namespaced storage layout
- [EIP-6800](https://eips.ethereum.org/EIPS/eip-6800) — Verkle trees (proposed)

### Production Code
- [Aave V3 ReserveConfiguration.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol) — Production bitmap packing
- [Solady SSTORE2](https://github.com/vectorized/solady/blob/main/src/utils/SSTORE2.sol) — Bytecode as immutable storage
- [OpenZeppelin StorageSlot.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/StorageSlot.sol) — Typed storage slot access
- [Uniswap V4 PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) — Transient storage flash accounting

### Deep Dives
- [EVM Deep Dives: Storage — Noxx](https://noxx.substack.com/p/evm-deep-dives-the-path-to-shadowy-5) — Excellent visual walkthrough of slot computation
- [EVM Storage Layout — RareSkills](https://www.rareskills.io/post/evm-solidity-storage-layout) — Detailed guide with examples

### Tools
- [`cast storage`](https://book.getfoundry.sh/reference/cast/cast-storage) — Read any slot from any contract
- [`forge inspect`](https://book.getfoundry.sh/reference/forge/forge-inspect) — Examine compiled storage layout
- [`cast proof`](https://book.getfoundry.sh/reference/cast/cast-proof) — Get a Merkle storage proof

---

**Navigation:** [Previous: Module 2 — Memory & Calldata](2-memory-calldata.md) | [Next: Module 4 — Control Flow & Functions](4-control-flow.md)
