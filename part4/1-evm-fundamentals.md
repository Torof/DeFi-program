# Part 4 — Module 1: EVM Fundamentals

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~50 minutes | **Exercises:** ~3-4 hours

---

## 📚 Table of Contents

**What the EVM Actually Is**
- [The State Transition Function](#state-transition)
- [Accounts: The Data Model](#accounts)
- [Transactions and Gas Pricing](#transactions)

**The Machine**
- [The Stack Machine](#stack-machine)
- [Opcode Categories](#opcode-categories)

**Cost & Context**
- [Gas Model — Why Things Cost What They Cost](#gas-model)
- [Execution Context at the Opcode Level](#execution-context)

**Writing Assembly**
- [Your First Yul](#first-yul)
- [Contract Bytecode: Creation vs Runtime](#bytecode)
- [Build Exercise: YulBasics](#exercise1)
- [Build Exercise: GasExplorer](#exercise2)

---

## What the EVM Actually Is

Before diving into opcodes and gas costs, you need the mental model that ties everything together. The EVM isn't just "a thing that runs Solidity." It's a precisely defined state machine — and understanding that framing makes every other concept in Part 4 click.

<a id="state-transition"></a>
### 💡 Concept: The State Transition Function

**Why this matters:** Every EVM concept you'll learn — opcodes, gas, storage, memory — is a piece of one unified system. That system is formally a **state transition function**:

```
σ' = Υ(σ, T)

Where:
  σ  = current world state (all accounts, all storage, all code)
  T  = a transaction (from, to, value, data, gas limit, ...)
  Υ  = the EVM state transition function
  σ' = the new world state after executing T
```

That's it. The entire Ethereum execution layer is this one function. A block is just a sequence of transactions applied one after another: `σ₀ → T₁ → σ₁ → T₂ → σ₂ → ... → σₙ`. Every node runs the same function on the same inputs and must arrive at the same output — this is what "deterministic execution" means, and why the EVM has no floating point, no randomness, no I/O, and no threads.

**What "world state" contains:**

```
World State (σ)
├── Account 0x1234...
│   ├── nonce: 5
│   ├── balance: 1.5 ETH
│   ├── storageRoot: 0xabc...  (root hash of this account's storage trie)
│   └── codeHash: 0xdef...     (hash of this account's bytecode)
├── Account 0x5678...
│   ├── ...
└── ... (every account that has ever been touched)
```

Every opcode you'll learn modifies some part of this state. `SSTORE` modifies an account's storage trie. `CALL` with value modifies balances. `CREATE` adds a new account. `LOG` appends to the transaction receipt (not part of world state, but part of the block). Understanding the state transition model makes it clear *why* SSTORE costs 20,000 gas (it modifies the world state that every node must persist) while ADD costs 3 gas (it only affects the ephemeral stack, which disappears after execution).

---

<a id="accounts"></a>
### 💡 Concept: Accounts — The Data Model

**Why this matters:** Every address on Ethereum is an account with four fields. When you read or write storage, check balances, deploy contracts, or send ETH — you're operating on these fields. Understanding the account model tells you exactly what each opcode touches.

**The two account types:**

| | EOA (Externally Owned Account) | Contract Account |
|---|---|---|
| **Controlled by** | Private key | Code (bytecode) |
| **Has code?** | No (`codeHash` = hash of empty) | Yes |
| **Has storage?** | No (`storageRoot` = empty trie) | Yes |
| **Can initiate tx?** | Yes | No (only responds to calls) |
| **Created by** | Generating a key pair | CREATE or CREATE2 opcode |

**The four fields every account has:**

```
Account State
┌──────────────┬────────────────────────────────────────────────────┐
│ nonce        │ For EOAs: number of transactions sent             │
│              │ For contracts: number of contracts created         │
│              │ Starts at 0. Incremented by each tx / CREATE       │
│              │ This is why CREATE addresses depend on nonce       │
├──────────────┼────────────────────────────────────────────────────┤
│ balance      │ Wei held by this account                          │
│              │ Modified by: value transfers, SELFDESTRUCT,       │
│              │ gas payments, coinbase rewards                    │
│              │ Opcodes: BALANCE, SELFBALANCE, CALL with value    │
├──────────────┼────────────────────────────────────────────────────┤
│ storageRoot  │ Root hash of the account's storage trie           │
│              │ A Merkle Patricia Trie mapping uint256 → uint256  │
│              │ This is what SLOAD/SSTORE read/write              │
│              │ Empty for EOAs. Module 3 covers the trie in depth │
├──────────────┼────────────────────────────────────────────────────┤
│ codeHash     │ keccak256 hash of the account's EVM bytecode      │
│              │ Set once during CREATE. Immutable after deployment │
│              │ EOAs have keccak256("") = 0xc5d2...               │
│              │ Opcodes: EXTCODEHASH, EXTCODESIZE, EXTCODECOPY    │
└──────────────┴────────────────────────────────────────────────────┘
```

**How this connects to opcodes you'll learn:**

| Account field | Reading opcodes | Writing operations |
|--------------|----------------|-------------------|
| nonce | (no direct opcode) | Incremented by tx execution or CREATE |
| balance | `BALANCE(addr)`, `SELFBALANCE` | `CALL` with value, block rewards |
| storageRoot | `SLOAD(slot)` | `SSTORE(slot, value)` |
| codeHash | `EXTCODEHASH(addr)` | Set once by CREATE/CREATE2 |

> **Why EXTCODESIZE(addr) == 0 doesn't always mean EOA:** During a constructor, the contract's code hasn't been stored yet (it's returned at the end). So `EXTCODESIZE` returns 0 for a contract mid-construction. This is a classic security footgun — don't use code size checks for access control.

---

<a id="transactions"></a>
### 💡 Concept: Transactions and Gas Pricing

**Why this matters:** Gas costs are meaningless without understanding how gas is paid for. The transaction type determines how gas pricing works, and the block gas limit constrains what's possible in a single block.

**Transaction types on Ethereum today:**

| Type | EIP | Gas pricing | Key feature |
|------|-----|------------|-------------|
| Type 0 (legacy) | Pre-EIP-2718 | Single `gasPrice` | Simple: you pay `gasPrice × gasUsed` |
| Type 1 | [EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) | Single `gasPrice` + access list | Pre-declare accessed addresses/slots for a discount |
| Type 2 | [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) | `maxFeePerGas` + `maxPriorityFeePerGas` | Base fee burned, priority fee to validator |
| Type 3 | [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) | Type 2 + `maxFeePerBlobGas` | Blob data for L2 rollups |

**EIP-1559 gas pricing (the standard today):**

```
Transaction specifies:
  gasLimit              — max gas units you're willing to use
  maxFeePerGas          — max wei per gas you'll pay
  maxPriorityFeePerGas  — tip to the validator per gas unit

Block has:
  baseFee               — protocol-set minimum price, burned (not paid to validator)
                           Adjusts up/down based on block utilization

Actual cost per gas unit:
  effectiveGasPrice = baseFee + min(maxPriorityFeePerGas, maxFeePerGas - baseFee)

Total cost:
  gasUsed × effectiveGasPrice
  └── baseFee portion is burned (removed from supply)
  └── priority fee portion goes to the block validator
```

**How this relates to opcodes:**
- `GASPRICE` returns the `effectiveGasPrice` — what you're actually paying per gas unit
- `BASEFEE` returns the current block's base fee — useful for MEV bots calculating profitability
- `GAS` returns remaining gas — the gas limit minus gas consumed so far

**The block gas limit:**

Each block has a **gas limit** (~30 million gas as of 2025, adjustable by validators). This is the hard ceiling on total computation per block. It means:
- A single transaction can use at most ~30M gas (the full block)
- In practice, blocks contain many transactions sharing this budget
- Complex DeFi operations (500K+ gas) consume ~1.5-2% of a block
- This is why gas optimization matters: cheaper operations → more transactions per block → lower fees for everyone

> **Connection to everything else:** When you see that SSTORE costs 20,000 gas and a block fits ~30M gas, you can calculate: a block can do at most ~1,500 fresh storage writes. That's the physical constraint that drives every storage optimization pattern in DeFi.

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

> **Why 256-bit words?** This wasn't arbitrary. Ethereum's core cryptographic operations — keccak-256 (hashing), secp256k1 (signatures), and 256-bit addresses — all produce or operate on 256-bit values. Making the word size match the crypto output means no awkward multi-word assembly is needed for the most common operations: a hash result fits in one stack item, a public key coordinate fits in one stack item, and arithmetic over these values is a single opcode. Smaller word sizes (64-bit, 128-bit) would require multiple stack items per hash or key, complicating every EVM operation. Larger sizes (512-bit) would waste space and gas. 256 bits is the natural fit for a blockchain VM.

> **Why a 1024 stack limit?** Each stack item is 32 bytes, so a full stack consumes 32 KB of memory. Capping at 1024 keeps the per-call memory footprint bounded and predictable, which matters when every node must execute every transaction. It also simplifies implementation — validators can pre-allocate a fixed-size array for the stack. In practice, most contract calls use well under 100 stack items. The limit mainly prevents pathological contracts from consuming excessive memory during execution. The "stack too deep" error you see at compile time is actually Solidity's 16-item working limit (due to DUP/SWAP range), not the 1024 hard cap.

**Byte ordering: Big-Endian**

The EVM uses **big-endian** byte ordering — the most significant byte is stored at the lowest address. This is the opposite of x86/ARM CPUs (little-endian) and is critical to understand before writing any assembly:

```
The number 0xCAFE stored as a 256-bit word (32 bytes):

Byte index:  0  1  2  ... 28 29 30 31
Value:       00 00 00 ... 00 00 CA FE
             ↑ most significant          ↑ least significant
             (high byte)                 (low byte)
```

Small values are **right-aligned** (padded with leading zeros). This matters everywhere:
- `mstore(0x00, 0xCAFE)` puts `CA` at byte 30 and `FE` at byte 31 — not at byte 0
- Addresses (20 bytes) sit in bytes 12-31 of a 32-byte word, with bytes 0-11 being zeros
- Error selectors (4 bytes) sit in bytes 28-31, which is why `revert(0x1c, 0x04)` works (0x1c = 28)
- `shr(224, calldataload(0))` extracts a 4-byte selector by shifting right to discard the lower 224 bits

This right-alignment is consistent across all data locations: stack, memory, calldata, storage, and return data. Once you internalize it, every byte-level pattern in assembly makes sense.

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

> **Why exactly 16?** The DUP and SWAP opcodes are encoded as single-byte ranges: `DUP1`=`0x80` through `DUP16`=`0x8F`, and `SWAP1`=`0x90` through `SWAP16`=`0x9F`. Each range spans exactly 16 values (one hex digit: 0-F). Extending to DUP32/SWAP32 would require a two-byte encoding or consuming another opcode range, increasing bytecode size and breaking the clean single-byte opcode design. The limit of 16 is a direct consequence of fitting within one byte of opcode space.
>
> When Solidity needs more than 16 values simultaneously, it spills to memory — or you get "stack too deep." This is why optimizing local variable count matters, and why the `via_ir` compiler pipeline helps (it's smarter about stack management, using memory spills efficiently).

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

#### ⚠️ Common Mistakes

- **Wrong operand order** — `SUB(a, b)` computes `b - a` in Yul (stack order: b is pushed first, a second, SUB pops a then b). This catches everyone at least once
- **Assuming stack depth is unlimited** — The EVM stack is capped at 1024 items. Deep call chains (especially recursive patterns) can hit this limit
- **Confusing stack positions** — `dup1` copies the top, `dup2` copies the second item. Off-by-one errors in manual stack manipulation are the #1 assembly debugging time sink

#### 💼 Job Market Context

**"Explain how the EVM executes a simple addition"**
- Good: "It pushes two values onto the stack, then ADD pops both and pushes the result"
- Great: "The EVM is a stack machine — no registers. ADD pops the top two stack items, computes their sum mod 2^256, and pushes the result. The program counter advances by 1 byte. If the stack has fewer than 2 items, it's a stack underflow and the transaction reverts"

🚩 **Red flag:** Not knowing the stack is 256-bit wide, or confusing the EVM with register-based architectures

**Pro tip:** Being able to trace opcodes by hand (even a short sequence) signals deep understanding. Practice with [evm.codes playground](https://www.evm.codes/playground)

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
| **Environment** | ADDRESS, CALLER, CALLVALUE, CALLDATALOAD, CALLDATASIZE, CALLDATACOPY, CODESIZE, GASPRICE, RETURNDATASIZE, RETURNDATACOPY, EXTCODESIZE, EXTCODECOPY, EXTCODEHASH | 2-2600 | Reading execution context and external code |
| **Block** | BLOCKHASH, COINBASE, TIMESTAMP, NUMBER, PREVRANDAO, GASLIMIT, CHAINID, BASEFEE, BLOBBASEFEE | 2-20 | Time/block info |
| **Memory** | MLOAD, MSTORE, MSTORE8, MSIZE, MCOPY | 3* | Temporary data, ABI encoding |
| **Storage** | SLOAD, SSTORE | 100-20000 | Persistent state |
| **Transient** | TLOAD, TSTORE | 100 | Same-tx temporary state |
| **Flow** | JUMP, JUMPI, JUMPDEST, PC, STOP, RETURN, REVERT, INVALID | 1-8 | Control flow, function returns |
| **System** | CALL, STATICCALL, DELEGATECALL, CALLCODE, CREATE, CREATE2, SELFDESTRUCT | 100-32000+ | External interaction |
| **Stack** | POP, PUSH1-32, DUP1-16, SWAP1-16 | 2-3 | Stack manipulation |
| **Logging** | LOG0-LOG4 | 375 + 375/topic + 8/byte | Events (375 base for receipt entry, each topic costs 375 for Bloom filter indexing, data costs 8/byte) |
| **Hashing** | KECCAK256 | 30+6/word | Mapping keys, signatures |

*Memory opcodes have a base cost of 3 plus memory expansion cost (covered in the gas model section).

**Control flow: JUMP, JUMPI, JUMPDEST, and the Program Counter**

The EVM executes bytecode sequentially, one opcode at a time. A **program counter (PC)** tracks the current position in the bytecode. Most opcodes advance the PC by 1 (or more for PUSH instructions that have immediate data). Control flow opcodes alter the PC directly:

| Opcode | Gas | What it does |
|--------|-----|-------------|
| `JUMP` | 8 | Pop destination from stack, set PC to that value. The destination **must** be a JUMPDEST |
| `JUMPI` | 10 | Pop destination and condition. If condition ≠ 0, jump. Otherwise continue sequentially |
| `JUMPDEST` | 1 | Marks a valid jump destination. No-op at runtime, but without it JUMP/JUMPI revert |
| `PC` | 2 | Push the current program counter value. Deprecated — rarely used in practice |

```
Bytecode:   PUSH1 0x05  PUSH1 0x0A  JUMPI  PUSH1 0xFF  JUMPDEST  STOP
PC:         0           2           4      5           7          8
                                    │                  ▲
                                    └──────────────────┘
                                    If top of stack ≠ 0,
                                    jump to PC=7 (JUMPDEST)
```

**Why JUMPDEST exists:** Without it, an attacker could JUMP into the middle of a PUSH instruction's data, where the data bytes happen to look like valid opcodes. JUMPDEST forces explicit marking of valid targets, preventing this class of bytecode injection. Every `if`, `for`, `while`, `switch`, and function call in Solidity compiles down to JUMP/JUMPI/JUMPDEST sequences.

> **In Yul**, you never write JUMP directly. `if`, `switch`, and `for` compile to JUMP/JUMPI under the hood. But understanding this is essential when you read raw bytecode (e.g., using `cast disassemble`) or debug at the opcode level. Module 4 covers how the compiler generates these patterns for selector dispatch and function calls.

**CREATE and CREATE2 — Contract deployment opcodes:**

| Opcode | Gas | Stack args | Address computation |
|--------|-----|-----------|-------------------|
| `CREATE` | 32000 + code deposit | value, offset, size | `keccak256(rlp(sender, nonce))` — nonce-dependent, non-deterministic |
| `CREATE2` | 32000 + code deposit + keccak256 cost | value, offset, size, salt | `keccak256(0xff ++ sender ++ salt ++ keccak256(initCode))` — deterministic |

Both read creation code from memory (at `offset`, `size` bytes), execute it, and store whatever RETURN outputs as the new contract's runtime code. They push the new contract's address on success, or 0 on failure.

```
CREATE:   address = keccak256(rlp(sender, nonce))[12:]
          ↑ Changes every time — depends on sender's nonce

CREATE2:  address = keccak256(0xFF, sender, salt, keccak256(initCode))[12:]
          ↑ Same inputs → same address, even before deployment
```

**Why CREATE2 matters for DeFi:**
- **Uniswap V2/V3 pair factories** use CREATE2 with the token pair as salt → deterministic pool addresses. Anyone can compute the pool address off-chain without querying the factory
- **EIP-1167 minimal proxy factories** deploy clones at deterministic addresses using CREATE2
- **Counterfactual deployment** — you can compute a contract's address before deploying it, enabling patterns like pre-funding a contract or governance voting on a deployment before it happens

> **Code deposit cost:** After the creation code runs and RETURNs runtime bytecode, the EVM charges an additional 200 gas per byte of runtime code stored. A 10 KB contract costs an extra 2,000,000 gas just for storage. This is why contract size matters — the 24,576-byte limit ([EIP-170](https://eips.ethereum.org/EIPS/eip-170)) caps deployment cost and state growth.

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

**Other opcodes worth knowing:**

- `SIGNEXTEND(b, x)` — Extends the sign bit of a `b+1`-byte value to fill 32 bytes. Used when working with signed integers smaller than `int256`. Uniswap V3's `int24` tick values use this for sign-correct comparisons
- `SELFBALANCE` — Returns `address(this).balance` for 5 gas, vs `BALANCE(ADDRESS)` which costs 100-2600 gas. Added in [EIP-1884](https://eips.ethereum.org/EIPS/eip-1884) specifically because checking your own balance is very common
- `BYTE(n, x)` — Extracts the `n`th byte from `x` (big-endian, 0 = most significant). Useful in low-level ABI decoding and byte-level manipulation
- `COINBASE` — Returns the block's fee recipient (validator/builder). Used in MEV contexts and [EIP-4788](https://eips.ethereum.org/EIPS/eip-4788) related patterns (beacon block root accessible from the consensus layer, enabling on-chain Beacon state proofs)
- `PREVRANDAO` — Provides randomness from the Beacon chain (post-merge). Not truly random (validators know it ~1 slot ahead), but usable for non-critical randomness. Don't use for lottery/raffle — use Chainlink VRF instead

**What you can safely skip for now:** `BLOCKHASH` (rarely used in DeFi, returns zero for blocks > 256 ago), `BLOBBASEFEE` (L2-specific), `PC` (deprecated — `PUSH` + label is preferred).

> **EOF (EVM Object Format):** [EIP-7692](https://eips.ethereum.org/EIPS/eip-7692) (proposed for a future fork) restructures EVM bytecode into a validated container format with separated code/data sections, typed function signatures, and removal of dynamic JUMPs. This would eliminate JUMPDEST scanning, enable static analysis, and improve safety. It's the biggest planned EVM change since the Merge. The new opcodes (RJUMP, CALLF, RETF, DATALOAD) would replace JUMP/JUMPI patterns. Not yet live, but worth tracking — it will significantly change how Yul compiles to bytecode.

> **SELFDESTRUCT is deprecated.** [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780) (Dencun fork, March 2024) neutered `SELFDESTRUCT` — it only works within the same transaction as contract creation. It no longer deletes contract code or transfers remaining balance. Don't use it in new code.

**EXTCODESIZE, EXTCODECOPY, EXTCODEHASH — reading other contracts:**

These opcodes inspect another contract's deployed bytecode:

| Opcode | Gas | What it returns |
|--------|-----|----------------|
| `EXTCODESIZE(addr)` | 100 warm / 2600 cold | Byte length of `addr`'s runtime code |
| `EXTCODECOPY(addr, destOffset, codeOffset, size)` | 100/2600 + memory | Copies code from `addr` into memory |
| `EXTCODEHASH(addr)` | 100 warm / 2600 cold | `keccak256` of `addr`'s runtime code |

**DeFi relevance:** `EXTCODESIZE` is how `Address.isContract()` checks work — an EOA has code size 0. But beware: a contract in its constructor also has code size 0 (the runtime code hasn't been deployed yet). `EXTCODEHASH` is useful for verifying a contract's implementation hasn't changed (governance checks, proxy verification). `EXTCODECOPY` enables on-chain bytecode analysis (used by some MEV protection contracts).

**MCOPY — efficient memory-to-memory copy:**

> Introduced in [EIP-5656](https://eips.ethereum.org/EIPS/eip-5656) (Cancun fork, March 2024)

`MCOPY(destOffset, srcOffset, size)` copies `size` bytes from `srcOffset` to `destOffset` in memory. Before MCOPY, the only way to copy memory was byte-by-byte loops or using the `identity` precompile at address `0x04`. MCOPY is a single opcode (3 gas base + 3/word + expansion cost), handles overlapping regions correctly, and is significantly cheaper for large copies. Module 2 covers this in depth.

**CALLCODE — the predecessor to DELEGATECALL:**

`CALLCODE` is an older opcode that's functionally similar to `DELEGATECALL`, but with one critical difference: it does **not** preserve `msg.sender`. In a CALLCODE, the called code sees `msg.sender` as the calling contract, not the original external caller. `DELEGATECALL` (introduced in [EIP-7](https://eips.ethereum.org/EIPS/eip-7)) fixed this. You should never use CALLCODE in new code — it exists only for backward compatibility. If you see it in legacy contracts, treat it as a red flag.

**STATICCALL — read-only external calls:**

`STATICCALL` works exactly like `CALL` but with one restriction: any operation that modifies state will revert. This includes SSTORE, LOG, CREATE, CREATE2, SELFDESTRUCT, TSTORE, and CALL with nonzero value. The EVM enforces this at the opcode level — the restriction propagates through the entire call tree. Any sub-call within a STATICCALL also cannot modify state.

**Why it matters:** Every `view` and `pure` function in Solidity compiles to `STATICCALL` when called externally. This is the EVM-level guarantee that view functions can't modify state. It's also why oracles and price feeds use view functions — the caller has a cryptographic guarantee that the call didn't change anything.

**RETURNDATASIZE and RETURNDATACOPY — reading call results:**

After any external call (CALL, STATICCALL, DELEGATECALL), the called contract's return data is available via `RETURNDATASIZE` (returns byte length) and `RETURNDATACOPY(destOffset, srcOffset, size)` (copies return data to memory). Before any call is made, `RETURNDATASIZE` returns 0 — which is why pre-Shanghai code used it as a gas-cheap way to push zero (the PUSH0 trick mentioned above).

> **Module 5** covers the full pattern: making an external call, checking success, then using RETURNDATACOPY to process the result.

**Execution frames — the call stack:**

Every CALL, STATICCALL, DELEGATECALL, and CREATE starts a new **execution frame**. Each frame has its own:
- **Stack** — fresh, empty stack (not shared with the caller)
- **Memory** — fresh, zeroed memory (not shared with the caller)
- **Program counter** — starts at 0 in the called code

What IS shared between frames:
- **Storage** — the same contract's storage (or the caller's storage for DELEGATECALL)
- **Transient storage** — shared within the transaction
- **Gas** — forwarded from the parent (minus the 1/64 retention)

This isolation is why a called contract can't corrupt the caller's stack or memory. The only communication channels are: calldata (input), returndata (output), storage (for DELEGATECALL), and state changes (logs, balance transfers).

**CALL, STATICCALL, DELEGATECALL — Stack Signatures:**

When you write `call(gas, addr, value, argsOffset, argsSize, retOffset, retSize)` in Yul, each argument maps directly to a stack position. Understanding the full signature — and how it differs across call types — is essential for reading and writing assembly:

| Opcode | Stack args (top → bottom) | Key difference |
|--------|--------------------------|---------------|
| `CALL` | gas, addr, value, argsOffset, argsSize, retOffset, retSize | Full call — 7 args, can send ETH |
| `STATICCALL` | gas, addr, argsOffset, argsSize, retOffset, retSize | 6 args — no `value`, state changes revert |
| `DELEGATECALL` | gas, addr, argsOffset, argsSize, retOffset, retSize | 6 args — no `value`, runs in caller's context |
| `CALLCODE` | gas, addr, value, argsOffset, argsSize, retOffset, retSize | 7 args — deprecated, like DELEGATECALL but wrong msg.sender |

All four return `1` (success) or `0` (failure) on the stack. They do **not** revert the caller on failure — you must check the return value explicitly.

```
CALL in Yul — the 7 arguments:

┌─────────┬──────────┬────────────┬────────────┬──────────┬───────────┬──────────┐
│   gas   │   addr   │   value    │ argsOffset │ argsSize │ retOffset │ retSize  │
│         │          │            │            │          │           │          │
│ How much│ Target   │ Wei to     │ Where in   │ How many │ Where to  │ How many │
│ gas to  │ contract │ send with  │ memory is  │ bytes of │ write     │ bytes of │
│ forward │          │ the call   │ calldata   │ calldata │ returndata│ returndata│
└─────────┴──────────┴────────────┴────────────┴──────────┴───────────┴──────────┘
                          ▲
                          │
            STATICCALL and DELEGATECALL
            remove this argument (6 args total)
```

**Why the return value matters:** Unlike Solidity's `address.call()` which returns `(bool success, bytes memory data)`, the raw opcode only pushes a `0` or `1`. If you forget to check:

```solidity
assembly {
    // WRONG — ignoring return value, execution continues silently on failure
    call(gas(), target, 0, 0, 0, 0, 0)

    // RIGHT — check and revert on failure
    let success := call(gas(), target, 0, 0, 0, 0, 0)
    if iszero(success) { revert(0, 0) }
}
```

**Extra costs for CALL with value:** Sending ETH (value > 0) adds 9,000 gas (the `callValueTransfer` cost). If the target account doesn't exist yet, add another 25,000 gas (the `newAccountGas` cost). This is why `CALL` with value is much more expensive than `STATICCALL`.

> **Module 5** covers the complete call pattern: encoding calldata in memory, making the call, checking success, and decoding returndata with RETURNDATACOPY.

**Yul `verbatim` — escape hatch for unsupported opcodes:**

Yul provides `verbatim_<n>i_<m>o(data, ...)` to inject raw bytecode that Yul doesn't natively support. For example, if a new EIP adds an opcode before Solidity supports it:

```solidity
assembly {
    // verbatim_1i_1o: 1 stack input, 1 stack output
    // 0x5c = TLOAD opcode byte (before Solidity had native tload support)
    let val := verbatim_1i_1o(hex"5c", slot)
}
```

You'll rarely need this in practice — most new opcodes get Yul built-ins quickly. But it's useful for experimental EIPs or custom chains with non-standard opcodes. Solady used `verbatim` for early TLOAD/TSTORE support before the Cancun fork.

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

**How precompile gas works:** Unlike regular opcodes with fixed costs, precompile gas is computed per-call based on the input. For `ecrecover` it's a flat 3,000 gas. For `modexp` (0x05), the gas formula considers the exponent size and modulus size — it can range from 200 to millions of gas. For BN256 pairing (0x08), it's `45,000 × number_of_pairs`. You invoke precompiles just like a regular STATICCALL — the EVM checks if the target address is 0x01-0x0a and, if so, runs native code instead of interpreting EVM bytecode.

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
┌──────────────┬───────────┬──────────────────────────┬──────────────────────────────────┐
│ Tier         │ Gas Cost  │ Opcodes                  │ Why this cost?                   │
├──────────────┼───────────┼──────────────────────────┼──────────────────────────────────┤
│ Zero         │ 0         │ STOP, RETURN, REVERT     │ Terminate execution — no work    │
│ Base         │ 2         │ CALLER, CALLVALUE,       │ Read from execution context —    │
│              │           │ TIMESTAMP, CHAINID       │ already in memory, no computation│
│ Very Low     │ 3         │ ADD, SUB, NOT, LT, GT,   │ Single ALU operation on values   │
│              │           │ PUSH, DUP, SWAP, MLOAD   │ already on stack or in memory    │
│ Low          │ 5         │ MUL, DIV, SHL, SHR, SAR  │ 256-bit multiply/divide is more  │
│              │           │                          │ work than add/compare            │
│ Mid          │ 8         │ JUMP, ADDMOD, MULMOD     │ JUMP validates JUMPDEST; modular │
│              │           │                          │ arithmetic = multiply + divide   │
│ High         │ 10        │ JUMPI, EXP (base)        │ Conditional + branch prediction; │
│              │           │                          │ EXP adds 50/byte of exponent     │
│ Transient    │ 100       │ TLOAD, TSTORE            │ Flat cost — data discarded after │
│              │           │                          │ tx, no permanent state burden    │
│ Storage Read │ 100-2100  │ SLOAD                    │ Cold = trie node loading from    │
│              │           │                          │ disk; warm = cached in memory    │
│ Storage Write│ 2900-20000│ SSTORE                   │ Modifies world state trie — all  │
│              │           │                          │ nodes must persist permanently   │
│ Hashing      │ 30+       │ KECCAK256                │ 30 base + 6/word — CPU-intensive │
│              │           │                          │ hash scales with input size      │
│ External Call│ 100-2600+ │ CALL, STATICCALL,        │ New execution frame + cold addr  │
│              │           │ DELEGATECALL             │ = trie lookup for target account │
│ Logging      │ 375+      │ LOG0-LOG4                │ 375 receipt + 375/topic (Bloom   │
│              │           │                          │ filter) + 8/byte (data storage)  │
│ Create       │ 32000+    │ CREATE, CREATE2          │ New account + code execution +   │
│              │           │                          │ 200/byte code deposit cost       │
└──────────────┴───────────┴──────────────────────────┴──────────────────────────────────┘
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

#### 🔍 Deep Dive: SSTORE Cost — The State Machine

SSTORE's gas cost isn't a single number — it depends on the **original value** (at transaction start), the **current value** (after any prior writes in this transaction), and the **new value** you're writing. [EIP-2200](https://eips.ethereum.org/EIPS/eip-2200) defines four cases:

```
SSTORE Gas Schedule (simplified):
────────────────────────────────────────────────────────────────
Original  Current   New       Gas Cost    What happened
────────────────────────────────────────────────────────────────
0         0         nonzero   20,000      Fresh write (new slot)
nonzero   nonzero   nonzero   2,900       Update existing value
nonzero   nonzero   0         2,900       Delete (+ refund)
nonzero   0         nonzero   20,000      Re-create after delete
────────────────────────────────────────────────────────────────

Special case: If new == current → 100 gas (SLOAD cost, no-op write)
```

**Why it matters — the Uniswap V2 reentrancy guard optimization:**

```solidity
// Expensive pattern (V2 original):  0 → 1 → 0
unlocked = 1;   // 20,000 gas (fresh write)
// ... do work ...
unlocked = 0;   // 2,900 gas (but 0→1→0 lifecycle refunded partially)

// Cheap pattern (V2 optimized):  1 → 2 → 1
unlocked = 2;   // 2,900 gas (update nonzero → nonzero)
// ... do work ...
unlocked = 1;   // 2,900 gas (update nonzero → nonzero)
```

Using `1 → 2 → 1` instead of `0 → 1 → 0` saves ~15,000 gas per guarded call, because it never crosses the zero/nonzero boundary that triggers the 20,000-gas fresh write cost.

> **Gas refunds** ([EIP-3529](https://eips.ethereum.org/EIPS/eip-3529)): When you SSTORE to zero (clear a slot), you receive a refund of **4,800 gas**. But refunds are capped at **1/5 of total gas used** in the transaction, preventing "gas token" exploits that abused refunds for on-chain gas banking. The refund mechanism is why clearing storage (setting to zero) is encouraged — it reduces state size.

> **Full state machine coverage:** Module 3 (Storage Deep Dive) covers the complete SSTORE cost state machine with a flow chart showing all branches, including EIP-2200 dirty tracking and EIP-3529 refund caps in detail.

---

<a id="memory-expansion"></a>
#### 🔍 Deep Dive: Memory Expansion Cost

**The problem:** Memory is dynamically sized — it starts at zero bytes and grows as needed. But growing memory gets progressively more expensive.

**The cost formula:**

```
memory_cost = 3 * words + (words² / 512)

where words = ceil(memory_size / 32)
```

The `words²` term means memory cost grows **quadratically**. This is intentional DoS prevention — without the quadratic term, an attacker could allocate gigabytes of memory for linear cost, forcing every validating node to allocate that memory. The quadratic penalty makes large allocations prohibitively expensive, bounding the resources any single transaction can consume. For small amounts of memory (a few hundred bytes), it's negligible. For large amounts, it becomes dominant:

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

<a id="failure-modes"></a>
#### 🔍 Deep Dive: Failure Modes

Not all failures are equal in the EVM. Understanding the distinction is critical for writing safe assembly and debugging production reverts.

**The four ways execution can stop abnormally:**

| Failure Mode | Opcode | Gas consumed | Returndata available? | When it happens |
|-------------|--------|-------------|----------------------|----------------|
| **REVERT** | `0xFD` | Only gas used so far | Yes — can include error message | Explicit `revert()`, `require()` failure |
| **INVALID** | `0xFE` | **ALL** remaining gas | No | `assert()` pre-0.8.1, designated invalid opcode |
| **Out of gas** | (none) | **ALL** remaining gas | No | Gas exhausted during execution |
| **Stack overflow/underflow** | (none) | **ALL** remaining gas | No | Stack exceeds 1024 items, or pops from empty stack |

The critical distinction: **REVERT** refunds unused gas and can pass error data. Everything else burns all remaining gas with no information.

```
Normal execution:
  Gas budget: 100,000 → uses 30,000 → 70,000 refunded to caller
  ┌──────────────────────┬───────────────────────────────┐
  │   Gas used: 30,000   │      Refunded: 70,000         │
  └──────────────────────┴───────────────────────────────┘

REVERT:
  Gas budget: 100,000 → uses 30,000 → state rolled back, 70,000 refunded
  ┌──────────────────────┬───────────────────────────────┐
  │  Gas used: 30,000 🔴 │      Refunded: 70,000         │
  └──────────────────────┴───────────────────────────────┘
  State: rolled back ↩   Return data: available ✓

INVALID / Out of gas / Stack overflow:
  Gas budget: 100,000 → ALL consumed, state rolled back, no error info
  ┌──────────────────────────────────────────────────────┐
  │            ALL gas consumed: 100,000 🔴              │
  └──────────────────────────────────────────────────────┘
  State: rolled back ↩   Return data: none ✗
```

**Why this matters in assembly:**

In Yul, `revert(offset, size)` uses the REVERT opcode — it returns unused gas and can pass error data back to the caller. But if you make a mistake that causes out-of-gas or stack overflow, ALL gas is consumed with no error message, making debugging much harder.

```solidity
assembly {
    // REVERT — returns unused gas, includes 4-byte error selector + message
    mstore(0x00, 0x08c379a000000000000000000000000000000000000000000000000000000000)
    mstore(0x04, 0x20)         // offset to string data
    mstore(0x24, 0x0d)         // string length: 13
    mstore(0x44, "Access denied")
    revert(0x00, 0x64)         // Returns error data, refunds unused gas

    // INVALID — consumes ALL gas, no return data, no information
    invalid()                   // 0xFE opcode — you almost never want this
}
```

**REVERT vs INVALID across Solidity versions:**

| Solidity construct | Pre-0.8.1 | Post-0.8.1 |
|---|---|---|
| `require(false, "msg")` | REVERT | REVERT |
| `assert(false)` | INVALID (all gas burned!) | REVERT with `Panic(0x01)` |
| Division by zero | INVALID | REVERT with `Panic(0x12)` |
| Array out of bounds | INVALID | REVERT with `Panic(0x32)` |
| Arithmetic overflow | Wraps silently (no check) | REVERT with `Panic(0x11)` |

Post-0.8.1, Solidity almost never emits INVALID. But in **raw assembly, you're responsible** — the compiler won't insert safety checks for you. Every division, every array access, every assumption about values must be validated explicitly or you risk a silent all-gas-consuming failure.

**DeFi implications:**

1. **Gas griefing attacks** — If a callback target can force an out-of-gas or INVALID condition, the caller loses all forwarded gas. This is why safe external calls use bounded gas forwarding (`call(gasLimit, ...)` rather than `call(gas(), ...)`) when calling untrusted contracts

2. **Error propagation in assembly** — When a sub-call reverts, its error data is available via `RETURNDATASIZE` / `RETURNDATACOPY`. The standard pattern to bubble up the revert reason:

```solidity
assembly {
    let success := call(gas(), target, 0, 0x00, calldatasize(), 0, 0)
    if iszero(success) {
        // Copy the revert reason from the sub-call and re-throw it
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
    }
}
```

3. **Debugging "out of gas"** — When a transaction fails with no return data, it's either out-of-gas, stack overflow, or INVALID. Use `cast run <txhash> --trace` to step through opcodes and find where execution diverges. Module 5 covers this debugging workflow in detail.

---

<a id="63-64-rule"></a>
#### ⚠️ The 63/64 Rule

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

#### ⚠️ Common Mistakes

- **Hardcoding gas costs** — Gas costs change with EIPs (EIP-2929 doubled cold access costs). Never use magic numbers like `gas: 2300` for transfers — use `call{value: amount}("")` and let the compiler handle it
- **Forgetting cold/warm distinction** — The first access to a storage slot or external address costs 2100/2600 gas, subsequent accesses cost 100. Not accounting for this in gas estimates leads to unexpected reverts
- **Ignoring the 63/64 rule in nested calls** — Only 63/64 of remaining gas is forwarded to a sub-call. Deep call chains (>10 levels) can silently run out of gas even with plenty of gas at the top level
- **Assuming gas refunds reduce execution cost** — Post-EIP-3529, refunds are capped at 1/5 of total gas used. The old pattern of using SELFDESTRUCT for gas tokens no longer works

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

#### ⚠️ Common Mistakes

- **No type safety in Yul** — Everything is `uint256`. Writing `let x := 0xff` then using `x` as an address won't warn you. Cast bugs are invisible until they cause wrong behavior
- **Forgetting Yul evaluates right-to-left** — In `mstore(0x00, caller())`, `caller()` executes first, then `mstore`. This matters when operations have side effects
- **Not cleaning upper bits** — When reading from memory or calldata, values may have dirty upper bits. Always mask with `and(value, 0xff)` or `and(value, 0xffffffffffffffffffffffffffffffffffffffff)` for addresses

#### 💼 Job Market Context

**"When would you use inline assembly in production code?"**
- Good: "When the compiler generates inefficient code for a known-safe operation — like bitwise packing, or reading a specific storage slot"
- Great: "Only when the gas savings justify the audit burden. Solady uses assembly extensively because it's a library called millions of times — the cumulative savings matter. But for application-level code, the compiler usually gets within 5-10% of hand-written assembly, and the readability cost isn't worth it"

🚩 **Red flag:** Wanting to write everything in assembly "for performance" — signals inexperience with the real trade-offs

**Pro tip:** Showing you can *read* assembly (trace through Solady, understand proxy forwarding) is more valuable in interviews than writing it from scratch

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

**What happens step by step during deployment:**

```
1. Transaction with no 'to' field → EVM knows this is contract creation
2. EVM creates a new account with address = keccak256(rlp(sender, nonce))
3. EVM executes the transaction's data field as code (this is the creation code)
4. Creation code runs:
   a. 6080604052 — Initialize free memory pointer to 0x80
   b. Constructor logic executes (set state variables, etc.)
   c. CODECOPY — Copy the runtime portion of itself into memory
   d. RETURN — Hand runtime code back to the EVM
5. EVM charges code deposit cost: 200 gas × len(runtime code)
6. EVM stores the returned bytes as the contract's code
7. Contract is live — future calls execute the runtime code only
```

**Constructor arguments:** When a constructor takes parameters, the Solidity compiler appends ABI-encoded arguments after the creation code bytecode. During deployment, the creation code reads these arguments using `CODECOPY` (not `CALLDATALOAD` — constructor args aren't in calldata, they're part of the deployment bytecode itself). This is why `forge create` and deployment scripts ABI-encode constructor args and concatenate them with the bytecode.

**Immutables:** Variables declared `immutable` are set during construction but stored directly in the **runtime bytecode**, not in storage. The creation code computes their values, then patches them into the runtime code before RETURNing it. This is why immutables cost zero gas to read (they're just PUSH instructions in the bytecode) but cannot be changed after deployment — they're literally baked into the contract's code.

```
// Reading an immutable at runtime:
PUSH32 0x000000000000000000000000...actualValue   ← embedded in bytecode
// vs reading from storage:
PUSH1 0x00  SLOAD                                  ← 100-2100 gas per read
```

> Module 8 (Pure Yul Contracts) goes deep into writing creation code and runtime code by hand using Yul's `object` notation. For now, understand the two-phase model and that `forge inspect` lets you examine both forms.

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

#### ⚠️ Common Mistakes

- **Confusing creation code with runtime code** — `type(C).creationCode` includes the constructor; `type(C).runtimeCode` is what gets deployed. Using the wrong one in CREATE/CREATE2 is a common source of deployment failures
- **Forgetting immutables are in bytecode** — Immutable variables are baked into the runtime bytecode at deploy time. They don't occupy storage slots, which means `sload` won't find them. This trips up devs writing assembly that tries to read "constants"

#### 💼 Job Market Context

**"What happens when you deploy a contract?"**
- Good: "The creation code runs, which returns the runtime bytecode that gets stored on-chain"
- Great: "A transaction with `to: null` triggers contract creation. The EVM runs the initcode (creation bytecode), which executes the constructor logic, then uses RETURN to hand back the runtime bytecode. That runtime code is stored in the state trie at the new address. This is why constructor arguments aren't in the deployed bytecode — they're consumed during creation"

🚩 **Red flag:** Not distinguishing creation code from runtime code, or thinking the constructor is part of the deployed contract

**Pro tip:** `forge inspect Contract bytecode` vs `deployedBytecode` — knowing this distinction cold impresses interviewers

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

**🎯 Goal:** Build muscle memory for basic Yul syntax — `let`, `add`, `mul`, `gt`, `lt`, `eq`, `iszero`, `caller()`, `callvalue()`, `timestamp()`, `chainid()`, `calldataload()`.

Run: `FOUNDRY_PROFILE=part4 forge test --match-contract YulBasicsTest -vvv`

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

Run: `FOUNDRY_PROFILE=part4 forge test --match-contract GasExplorerTest -vvv`

---

<a id="summary"></a>
## 📋 Key Takeaways: EVM Fundamentals

**✓ Covered:**
- The EVM is a stack machine — 256-bit words (matching keccak-256 and secp256k1), LIFO, max depth 1024 (32 KB)
- Why DUP/SWAP limited to 16 — single-byte opcode encoding (0x80-0x8F, 0x90-0x9F)
- Opcodes organized by category — arithmetic, comparison, bitwise, memory, storage, flow, system, environment
- Control flow — JUMP/JUMPI/JUMPDEST, program counter, why JUMPDEST exists (bytecode injection prevention)
- CREATE/CREATE2 — nonce-dependent vs deterministic addresses, code deposit cost (200 gas/byte)
- Gas model — tiers from 2 gas (context opcodes) to 20,000 gas (new storage write), with "why" for each tier
- SSTORE cost state machine — 4 branches based on original→current→new values, gas refunds capped at 1/5
- EIP-2929 warm/cold access — first access loads trie nodes (expensive), subsequent cached (cheap)
- Quadratic memory expansion — DoS prevention via non-linear cost
- The 63/64 rule — external calls retain 1/64 gas at each depth
- Execution context — every Solidity global maps to a 2-3 gas opcode
- Execution frames — each CALL gets fresh stack + memory, shares storage + transient storage
- Calldata layout — selector (4 bytes) + ABI-encoded arguments
- Contract bytecode — creation code (constructor + CODECOPY + RETURN) vs runtime code, immutables baked into bytecode
- PUSH0, MCOPY, SELFBALANCE, STATICCALL restrictions, verbatim
- Precompiled contracts — 0x01-0x0a, gas computed per-call based on input
- Yul basics — `let`, `if`, `switch`, `for`, named variables mapped to stack by the compiler

**Key numbers to remember:**
- ADD/SUB: 3 gas | MUL/DIV: 5 gas | SLOAD cold: 2100 gas | SSTORE new: 20,000 gas
- TLOAD/TSTORE: 100 gas | KECCAK256: 30 + 6/word | CALL cold: 2600 gas | CALL warm: 100 gas
- LOG2 (typical Transfer): ~1,893 gas | CREATE: 32,000+ gas | Code deposit: 200 gas/byte
- SSTORE update: 2,900 gas | SSTORE refund (clear): 4,800 gas | Max refund: 1/5 of total gas

**Next:** [Module 2 — Memory & Calldata](2-memory-calldata.md) — deep dive into mload/mstore, the free memory pointer, ABI encoding by hand, and returndata handling.

---

<a id="resources"></a>
## 📚 Resources

### Essential References
- [evm.codes](https://www.evm.codes/) — Interactive opcode reference with gas costs, stack effects, and playground
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) — Formal specification (Appendix H has the opcode table)
- [Yul Documentation](https://docs.soliditylang.org/en/latest/yul.html) — Official Solidity docs on Yul syntax

### EIPs Referenced
- [EIP-7](https://eips.ethereum.org/EIPS/eip-7) — DELEGATECALL (replaced CALLCODE)
- [EIP-150](https://eips.ethereum.org/EIPS/eip-150) — 63/64 gas forwarding rule (Tangerine Whistle)
- [EIP-170](https://eips.ethereum.org/EIPS/eip-170) — Contract code size limit (24,576 bytes)
- [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) — Transient storage: TLOAD/TSTORE at 100 gas (Dencun fork)
- [EIP-1884](https://eips.ethereum.org/EIPS/eip-1884) — SELFBALANCE opcode (Istanbul fork)
- [EIP-2200](https://eips.ethereum.org/EIPS/eip-2200) — SSTORE cost state machine (Istanbul fork)
- [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929) — Cold/warm access costs (Berlin fork)
- [EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) — Access list transaction type (Berlin fork)
- [EIP-3529](https://eips.ethereum.org/EIPS/eip-3529) — Reduced SSTORE refunds (London fork)
- [EIP-3855](https://eips.ethereum.org/EIPS/eip-3855) — PUSH0 opcode (Shanghai fork)
- [EIP-4788](https://eips.ethereum.org/EIPS/eip-4788) — Beacon block root in EVM (Dencun fork)
- [EIP-5656](https://eips.ethereum.org/EIPS/eip-5656) — MCOPY opcode (Cancun fork)
- [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780) — SELFDESTRUCT deprecation (Dencun fork)
- [EIP-7692](https://eips.ethereum.org/EIPS/eip-7692) — EOF (EVM Object Format) meta-EIP (proposed)

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
