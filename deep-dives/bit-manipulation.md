# Deep Dives — Bit Manipulation: The Complete Picture

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~90 minutes | **Exercises:** ~2 hours

---

## 📚 Table of Contents

**Foundations**
- [The Four Bitwise Logic Operators](#bitwise-logic)
- [Shift Operators: SHL, SHR, SAR](#shift-operators)
- [Byte-Level Operations](#byte-operations)
- [Operator Precedence & Gotchas](#precedence)

**Two's Complement**
- [How Negative Numbers Work](#twos-complement)
- [Why Addition Just Works](#twos-addition)
- [Sign Extension](#sign-extension)
- [The SIGNEXTEND Opcode](#signextend-opcode)
- [SAR Revisited](#sar-revisited)

**Masking Patterns**
- [What Is a Mask?](#what-is-mask)
- [Extract a Field](#extract-field)
- [Set a Field](#set-field)
- [Clear a Field](#clear-field)
- [Toggle a Bit](#toggle-bit)
- [Common Masking Mistakes](#masking-mistakes)

**Bitmap Sets**
- [uint256 as 256 Booleans](#bitmap-concept)
- [Core Operations](#bitmap-core)
- [Set Algebra](#set-algebra)
- [Population Count](#popcount)
- [Iterating Over Set Bits](#iterate-bits)
- [Multi-Word Bitmaps](#multi-word)

**LSB & MSB Isolation**
- [Isolate the Lowest Set Bit](#isolate-lsb)
- [Clear the Lowest Set Bit](#clear-lsb)
- [Count Trailing Zeros](#ctz)
- [Find the Highest Set Bit](#find-msb)
- [Count Leading Zeros](#clz)

**Power-of-2 Tricks**
- [Is Power of Two](#is-pow2)
- [Next Power of Two](#next-pow2)
- [Rounding to Alignment Boundaries](#alignment)
- [Modulo by Power of 2](#mod-pow2)

**Common Bit Idioms**
- [Branchless Conditional Select](#branchless-select)
- [Branchless Min / Max](#branchless-minmax)
- [Branchless Absolute Value](#branchless-abs)
- [Swap Without Temporary](#xor-swap)
- [Dirty Bits & Cleaning](#dirty-bits)
- [Checking Multiple Conditions at Once](#multi-condition)
- [Build Exercise: BitToolkit](#exercise1)

---

## 💡 Foundations — Bitwise Operators

Bit manipulation is the art of working with individual bits inside a number. In the EVM, every value is a 256-bit word — that's 256 individual switches you can flip, test, and combine. Mastering these operations unlocks the most gas-efficient patterns in Solidity and is essential for reading production assembly.

This section covers the building blocks. Everything else in this deep dive is a combination of these primitives.

<a id="bitwise-logic"></a>
### 💡 Concept: The Four Bitwise Logic Operators

**Why this matters:** Every masking operation, every packed struct, every bitmap flag — they all reduce to these four operations. If you understand these cold, the rest of bit manipulation is just recognizing patterns.

The four logic operators work **bit by bit** — each bit in the result depends only on the corresponding bits in the inputs.

#### AND (`&`)

**Rule:** The result bit is 1 only when **both** input bits are 1.

```
Truth table:        Example (8-bit):
  A  B  A&B
  0  0   0            0b_1100_1010
  0  1   0          & 0b_1111_0000
  1  0   0          ─────────────
  1  1   1            0b_1100_0000
```

**Mental model:** AND is a **filter**. The mask says which bits to keep — 1 means "keep this bit," 0 means "force it to zero." This is why AND is the core of every extraction pattern.

```solidity
// Keep only the lower 8 bits of a value
uint256 lower8 = value & 0xFF;   // 0xFF = 0b_1111_1111

// Check if bit 5 is set
bool isSet = (value & (1 << 5)) != 0;
```

#### OR (`|`)

**Rule:** The result bit is 1 when **at least one** input bit is 1.

```
Truth table:        Example (8-bit):
  A  B  A|B
  0  0   0            0b_1100_0000
  0  1   1          | 0b_0000_1010
  1  0   1          ─────────────
  1  1   1            0b_1100_1010
```

**Mental model:** OR is a **combiner**. It merges bits together without destroying existing ones. This is why OR is used to pack fields — you position each field, then OR them all together.

```solidity
// Set bit 3 (without touching other bits)
value = value | (1 << 3);

// Combine two non-overlapping fields
uint256 packed = (high << 128) | low;
```

#### XOR (`^`)

**Rule:** The result bit is 1 when the inputs are **different**.

```
Truth table:        Example (8-bit):
  A  B  A^B
  0  0   0            0b_1100_1010
  0  1   1          ^ 0b_1111_0000
  1  0   1          ─────────────
  1  1   0            0b_0011_1010
```

**Mental model:** XOR is a **conditional flipper**. The mask says which bits to toggle — 1 means "flip this bit," 0 means "leave it alone."

**Key property — self-inverse:** `a ^ b ^ b == a`. XOR-ing the same value twice cancels out. This is the basis for XOR swap, branchless select, and many cryptographic primitives.

```solidity
// Toggle bit 5
value = value ^ (1 << 5);

// Toggle it again — back to original
value = value ^ (1 << 5);
```

#### NOT (`~`)

**Rule:** Flips every bit. 0 becomes 1, 1 becomes 0.

```
Example (8-bit):         256-bit:
  ~ 0b_1100_1010           ~ 0x00000000...0000FFFF
  ─────────────           ────────────────────────
    0b_0011_0101             0xFFFFFFFF...FFFF0000
```

**Mental model:** NOT creates the **inverse mask**. If a mask selects certain bits, `~mask` selects everything else. This is essential for the "clear a field" pattern: `value & ~mask` zeros out exactly the bits the mask covers.

**Relationship to two's complement:** In the EVM, `~x == -x - 1` (or equivalently, `-x == ~x + 1`). This isn't a coincidence — it's how two's complement works. We'll explore this in the next section.

```solidity
// Clear the lower 16 bits
value = value & ~uint256(0xFFFF);

// Invert a selection mask
uint256 keepOthers = ~fieldMask;
```

<a id="shift-operators"></a>
### 💡 Concept: Shift Operators — SHL, SHR, SAR

**Why this matters:** Shifts are how you position bits. Every packing operation uses a shift to move a value to its slot. Every extraction uses a shift to move a field back to position 0. And in the EVM, shifts are the cheapest way to multiply or divide by powers of 2.

#### SHL — Shift Left (`<<`)

Moves all bits toward the most significant end. Vacated positions on the right fill with zeros. Bits that shift past the top are lost.

```
Before:   0b_0000_1011  (decimal 11)
SHL 3:    0b_0101_1000  (decimal 88)
              ^^^          ← these zeros filled in
                   ^^^     ← these bits moved left 3 positions

Equivalent: 11 × 2³ = 11 × 8 = 88
```

In the EVM (256-bit), shifting left by `n` is equivalent to multiplying by `2^n` — but at 3 gas (SHL) instead of 5 gas (MUL).

```solidity
// Position a value into the upper 128 bits of a uint256
uint256 positioned = value << 128;

// Multiply by 8
uint256 result = x << 3;   // x * 2³
```

#### SHR — Shift Right (unsigned) (`>>`)

Moves all bits toward the least significant end. Vacated positions on the left fill with **zeros**. Bits that shift past the bottom are lost.

```
Before:   0b_1011_0100  (decimal 180)
SHR 3:    0b_0001_0110  (decimal 22)
          ^^^              ← these zeros filled in
                    ^^^    ← these bits fell off (lost)

Equivalent: 180 / 2³ = 180 / 8 = 22  (integer division, remainder lost)
```

**Critical:** SHR always fills with zeros, regardless of the original sign. This is correct for unsigned values but **wrong for signed values** — see SAR below.

```solidity
// Extract the upper 128 bits of a uint256
uint256 upper = packed >> 128;

// Divide by 4
uint256 result = x >> 2;   // x / 2²
```

#### SAR — Shift Arithmetic Right

Moves bits right, but fills vacated positions with the **sign bit** (bit 255) instead of zero.

```
Positive number (sign bit = 0):
Before:   0b_0110_0000  (decimal 96, sign bit 0)
SAR 2:    0b_0001_1000  (decimal 24)
          ^^               ← filled with 0 (sign bit)
Same result as SHR — no difference for positive numbers.

Negative number (sign bit = 1):
Before:   0xFF...FA  (-6 in two's complement, sign bit 1)
SAR 1:    0xFF...FD  (-3)
          ^            ← filled with 1 (sign bit)

With SHR instead:
Before:   0xFF...FA  (-6 in two's complement)
SHR 1:    0x7F...FD  (huge positive number!)
          ^            ← filled with 0 (WRONG for signed!)
```

**The rule:** Use SHR for `uint` values, SAR for `int` values. Using the wrong one silently produces garbage.

In Solidity, the compiler picks the right shift automatically based on the type:
```solidity
uint256 u = 100;
int256  s = -100;

u >> 1;  // Compiles to SHR → 50
s >> 1;  // Compiles to SAR → -50
```

In assembly, you must choose explicitly:
```yul
let unsigned_result := shr(1, u)   // Zero-fill
let signed_result   := sar(1, s)   // Sign-fill
```

#### All Three Shifts — Side by Side

```
Input: 0b_1110_0100 (8-bit example)

SHL 2:  0b_1001_0000  ← bits move left, zeros fill right
SHR 2:  0b_0011_1001  ← bits move right, zeros fill left
SAR 2:  0b_1111_1001  ← bits move right, sign bit fills left
                         (sign bit was 1, so 1s fill in)
```

<a id="byte-operations"></a>
### 💡 Concept: Byte-Level Operations

**Why this matters:** The EVM is a 256-bit machine, but many real-world values are byte-sized (addresses are 20 bytes, selectors are 4 bytes, flags are 1 byte). The BYTE opcode and byte-oriented shift patterns let you work at byte granularity within a 256-bit word.

#### The BYTE Opcode

`byte(i, x)` extracts the `i`-th byte from the 256-bit word `x`, returning it as a `uint256` (right-aligned).

**Critical:** Byte indexing is **big-endian** — byte 0 is the **most** significant byte (leftmost), byte 31 is the **least** significant (rightmost).

```
256-bit word:
┌──────┬──────┬──────┬─────┬──────┬──────┐
│byte 0│byte 1│byte 2│ ... │byte30│byte31│
└──────┴──────┴──────┴─────┴──────┴──────┘
  MSB                                LSB

byte(0, 0xAB000000...00)  → 0xAB    (most significant byte)
byte(31, 0x00000000...CD) → 0xCD    (least significant byte)
```

#### BYTE vs Shift+Mask

You can achieve the same result with shifts and AND:

```yul
// These are equivalent:
let b := byte(i, x)
let b := and(shr(mul(sub(31, i), 8), x), 0xFF)
```

The shift version calculates: "to get byte `i`, shift right by `(31 - i) * 8` bits, then mask to 8 bits." The subtraction from 31 accounts for big-endian ordering.

**When to use which:**
- `byte(i, x)` — when you know the byte index at compile time, cleaner to read
- Shift+mask — when you need to extract multi-byte fields (2, 4, or 20 bytes), BYTE can only do one byte at a time

```yul
// Extract bytes 0-3 (a 4-byte selector from the MSB end)
let selector := shr(224, x)    // shift right 224 bits = 28 bytes

// Extract bytes 12-31 (a 20-byte address from the LSB end)
let addr := and(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
```

#### Big-Endian Byte Order

The EVM stores values big-endian: the most significant byte is at the lowest address. This matters when you're reading from memory or calldata:

```
Value: 0x0000...00000123 (uint256 = 291)

In memory (32 bytes):
Address:  0x00 0x01 0x02 ... 0x1D 0x1E 0x1F
Content:  0x00 0x00 0x00 ... 0x00 0x01 0x23
          ^^^^^^^^^^^^^^       ^^^^^^^^^^^
          leading zeros        actual value (right-aligned)
```

Value types like `uint8`, `address`, `bool` are **right-aligned** when stored as 256-bit words in the EVM — padded with zeros on the left.

The exception: `bytesN` types (not `bytes memory`, but fixed `bytes1` through `bytes32`) are **left-aligned** — padded with zeros on the right:

```
bytes4(0xDEADBEEF) as a 256-bit word:
0xDEADBEEF00000000000000000000000000000000000000000000000000000000
^^^^^^^^^^ value                                              ^^^^^^ padding
```

This is why extracting a function selector requires `shr(224, calldataload(0))` — the 4-byte selector sits in the leftmost bytes, and you shift it right to position 0.

<a id="precedence"></a>
### 💡 Concept: Operator Precedence & Gotchas

#### Solidity Precedence Trap

Solidity's operator precedence can surprise you. Bitwise operators have **lower precedence** than comparison operators:

```solidity
// ⚠️ WRONG — this compiles but doesn't do what you think:
if (value & 0xFF == 0) { ... }
// Parses as: value & (0xFF == 0) → value & false → value & 0

// ✅ CORRECT — explicit parentheses:
if ((value & 0xFF) == 0) { ... }
```

**The rule:** Always parenthesize bitwise expressions when combined with comparisons. The compiler won't warn you — the wrong version is syntactically valid.

Full precedence (highest to lowest, for the operators we care about):
1. `~` (NOT), unary `-`
2. `**` (exponentiation)
3. `*`, `/`, `%`
4. `+`, `-`
5. `<<`, `>>` (shifts)
6. `<`, `>`, `<=`, `>=` (comparisons)
7. `==`, `!=`
8. `&` (AND)
9. `^` (XOR)
10. `|` (OR)

Notice: shifts come before comparisons, but comparisons come before all bitwise operators. This means `a << 2 | b` is `(a << 2) | b` (correct), but `a & b == c` is `a & (b == c)` (almost certainly wrong).

#### Assembly Has No Precedence

In Yul/inline assembly, there is no operator precedence — everything is a function call:

```yul
// No ambiguity — explicit nesting
let result := and(shr(128, packed), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
```

This is one reason assembly code, despite being harder to read at first, avoids an entire class of precedence bugs.

---

## 💡 Two's Complement

Every signed integer in the EVM uses two's complement representation. If you've ever wondered why `type(int256).min` is `-2^255` but `type(int256).max` is only `2^255 - 1`, or why `-1` in two's complement (all ones) equals `type(uint256).max`, this section explains the underlying mechanics.

<a id="twos-complement"></a>
### 💡 Concept: How Negative Numbers Work

**Why this matters:** Signed integers appear throughout Solidity — `int256` for price deltas, `int128` for balance changes, `int24` for tick values. Every time you pack, unpack, shift, or compare a signed value, two's complement rules apply. Misunderstand them and your math silently breaks.

**The problem:** A bit can only be 0 or 1. How do you represent negative numbers?

**The solution:** Reserve the top bit as a sign indicator. If bit 255 is 0, the number is non-negative. If bit 255 is 1, the number is negative. But it's not as simple as "a sign flag" — the actual encoding uses two's complement.

#### The Encoding Rule

To negate a number: **flip all bits, then add 1.**

Let's trace through with 8 bits (the same logic applies to 256 bits):

```
Step 1: Start with 5
  0000_0101  (decimal 5)

Step 2: Flip all bits (NOT)
  1111_1010  (this is "one's complement" of 5)

Step 3: Add 1
  1111_1011  (this is -5 in two's complement)
```

Let's verify: 5 + (-5) should equal 0:
```
    0000_0101  ( 5)
  + 1111_1011  (-5)
  ───────────
  1_0000_0000  (the 1 overflows out of 8 bits → result is 0) ✓
```

#### The Number Line (8-bit)

```
Binary:    0000_0000  ...  0111_1111  1000_0000  ...  1111_1111
Unsigned:      0      ...     127        128     ...     255
Signed:        0      ...    +127       -128     ...      -1
                              ↑           ↑
                           max pos     min neg (the "extra" negative)
```

Key observations:
- **Positive range:** `0` to `2^(n-1) - 1` (0 to 127 for 8-bit)
- **Negative range:** `-1` to `-2^(n-1)` (-1 to -128 for 8-bit)
- **There's one more negative than positive** — this asymmetry is inherent to two's complement
- `1111_1111` is -1 (not -127), and `1000_0000` is -128 (not -0)
- **-1 is all ones** — `0xFF` in 8-bit, `0xFF...FF` in 256-bit. This is why `uint256(int256(-1)) == type(uint256).max`

#### Common Values to Memorize

| Value | 8-bit | 256-bit |
|-------|-------|---------|
| 0 | `0x00` | `0x00...00` |
| 1 | `0x01` | `0x00...01` |
| -1 | `0xFF` | `0xFF...FF` |
| max positive | `0x7F` (127) | `0x7F...FF` (2²⁵⁵ - 1) |
| min negative | `0x80` (-128) | `0x80...00` (-2²⁵⁵) |

<a id="twos-addition"></a>
### 💡 Concept: Why Addition Just Works

**The beauty of two's complement:** The CPU doesn't need separate circuits for signed and unsigned addition. The same binary addition works for both — overflow just wraps around naturally.

```
Example: 3 + (-5) = -2

  0000_0011  ( 3)
+ 1111_1011  (-5)
───────────
  1111_1110  (-2 ✓)

Verify: flip + add 1:
  ~1111_1110 = 0000_0001
  0000_0001 + 1 = 0000_0010 = 2
  So the original was -2 ✓
```

This is why the EVM only has one `ADD` opcode, not separate signed/unsigned versions. At the bit level, `add(a, b)` is the same regardless of interpretation.

**Where signed/unsigned diverge:** Comparison (`slt` vs `lt`) and division (`sdiv` vs `div`). The bits are the same — the interpretation differs.

```yul
// 0xFF...FF as uint256 = 2²⁵⁶ - 1 (huge positive)
// 0xFF...FF as int256 = -1

lt(0xFFFFFFFF...FF, 1)    // 0 (false: 2²⁵⁶-1 is NOT less than 1)
slt(0xFFFFFFFF...FF, 1)   // 1 (true: -1 IS less than 1)
```

<a id="sign-extension"></a>
### 💡 Concept: Sign Extension

**The problem:** You have an `int8` value (-5 = `0xFB`) stored in a 256-bit word. The EVM sees `0x00000000...000000FB`. But that's +251 as a uint256, not -5. How does the EVM know it's negative?

**The answer:** When you cast a smaller signed type to a larger one, Solidity **sign-extends** — it copies the sign bit into all the new upper bits.

```
int8(-5) in 8 bits:     1111_1011
                         ^
                         sign bit (1 = negative)

Sign-extend to 256 bits:
  1111_1111_1111_1111_..._1111_1111_1111_1011
  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  All new bits copy the sign bit (1)

Result: 0xFFFFFFFF...FFFFFFFB = -5 as int256 ✓
```

For a positive value, sign extension fills with zeros (because the sign bit is 0):
```
int8(5) in 8 bits:      0000_0101
                         ^
                         sign bit (0 = positive)

Sign-extend to 256 bits:
  0000_0000_0000_0000_..._0000_0000_0000_0101
  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  All new bits copy the sign bit (0)

Result: 0x00000000...00000005 = 5 as int256 ✓
```

**Why this preserves the value:** Two's complement guarantees that sign extension doesn't change the number's value. The proof is simple — adding leading 1s to a negative number is like adding `0xFF00` to `0xFB`, which in two's complement is the same as adding `-256 + 256 = 0`.

**In Solidity**, sign extension happens automatically when you cast:
```solidity
int8 small = -5;
int256 big = int256(small);  // Compiler inserts sign extension
// big == -5 (0xFFFFFFFF...FFFFFFFB)
```

**In assembly**, you must handle it yourself — see SIGNEXTEND below.

<a id="signextend-opcode"></a>
### 💡 Concept: The SIGNEXTEND Opcode

**Why this matters:** When you read a packed signed integer from storage or calldata in assembly, you get raw bits with no type information. If the value was an `int8`, you have 8 meaningful bits inside a 256-bit word. SIGNEXTEND tells the EVM: "treat byte `b` as the sign byte and extend it."

**Syntax:** `signextend(b, x)` — extends the sign of byte `b` (0-indexed from the least significant end) through all higher bits.

```
signextend(0, x)  → treat x as int8 (1 byte), sign-extend to 256 bits
signextend(1, x)  → treat x as int16 (2 bytes), sign-extend to 256 bits
signextend(2, x)  → treat x as int24 (3 bytes), sign-extend to 256 bits
signextend(15, x) → treat x as int128 (16 bytes), sign-extend to 256 bits
```

**Walkthrough:**

```
x = 0x00000000...0000009C   (156 in decimal)

As uint8: 156 (positive)
As int8:  -100 (negative! because bit 7 of byte 0 is 1)

signextend(0, x):
  Byte 0 of x = 0x9C = 1001_1100
                        ^
                        sign bit is 1 → extend with 1s

  Result: 0xFFFFFFFF...FFFFFF9C = -100 as int256 ✓
```

Another example with a positive value:
```
x = 0x00000000...0000005A   (90 in decimal)

signextend(0, x):
  Byte 0 of x = 0x5A = 0101_1010
                        ^
                        sign bit is 0 → extend with 0s (no change)

  Result: 0x00000000...0000005A = 90 as int256 ✓
```

**Common pattern — unpacking a signed field from storage:**

```yul
// Packed: [uint128 amount0 | int128 amount1]
// amount1 is in the lower 128 bits

let raw := and(packed, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)  // Extract lower 128 bits
let amount1 := signextend(15, raw)  // byte 15 = bit 127 = sign bit of int128
```

Without SIGNEXTEND, `raw` containing a negative int128 would be interpreted as a huge positive number.

<a id="sar-revisited"></a>
### 💡 Concept: SAR Revisited

Now that you understand two's complement and sign extension, SAR makes complete sense.

**SAR is a signed division by 2^n** — it must preserve the sign. It does this by filling the vacated upper bits with the sign bit, exactly like sign extension.

```
SAR on -6 (shift right by 1 = divide by 2):

  -6 = 0xFFFFFFFF...FFFFFFFA
  Binary: ...1111_1010

  SAR 1: ...1111_1101 = -3 ✓
         ^
         sign bit (1) fills in from the left

SHR on -6 (same bits, treated as unsigned):

  0xFFFFFFFF...FFFFFFFA  (huge positive number in unsigned)

  SHR 1: 0x7FFFFFFFFFFF...FD  (half of that huge number)
         ^
         zero fills in from the left → positive result
```

**Rounding behavior:** SAR rounds toward negative infinity, not toward zero.

```
SAR 1 on -7:
  -7 = ...1111_1001
  SAR 1: ...1111_1100 = -4  (rounds down, not toward zero)

  Integer division: -7 / 2 = -3 (rounds toward zero)
  SAR:              -7 >> 1 = -4 (rounds toward -∞)
```

This difference matters when precision counts. If you need round-toward-zero behavior for signed division, use `sdiv` instead of SAR.

---

## 💡 Masking Patterns

A mask is a bit pattern used to select, modify, or test specific bits within a word. If bitwise operators are the tools, masks are the stencils. Every packing/unpacking operation, every flag check, every field update uses a mask.

This section teaches masking as a **system of patterns** — learn these four operations and you can read or write any packed data structure.

<a id="what-is-mask"></a>
### 💡 Concept: What Is a Mask?

**A mask is a pattern of 1s and 0s that selects which bits to operate on.**

The simplest mask is a contiguous run of 1s:

```
0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF
                                                  ^^^^^^^^^^^^^^^^
                                                  64 bits of 1s = lower 64 bits selected
```

#### Building Masks

**A mask of `width` ones (starting from bit 0):**

```solidity
uint256 mask = (1 << width) - 1;
```

Why this works:
```
1 << 8    = 0b_1_0000_0000  (256)
256 - 1   = 0b_0_1111_1111  (255 = eight 1s)
```

**A positioned mask (at a given offset):**

```solidity
uint256 positioned = mask << offset;
```

```
mask = 0xFF (8 bits)
offset = 16

positioned:
  0b_0000_0000_1111_1111_0000_0000_0000_0000
                ^^^^^^^^
                8 ones at bit position 16-23
```

#### Visual: A 256-Bit Word With Fields

```
Bit position:   255  ...  192  191  ...  128  127  ...  64   63  ...   0
              ┌──────────┬──────────┬──────────┬──────────┐
              │ Field D  │ Field C  │ Field B  │ Field A  │
              │ 64 bits  │ 64 bits  │ 64 bits  │ 64 bits  │
              └──────────┴──────────┴──────────┴──────────┘

Mask for Field A: (1 << 64) - 1                     = 0x00...00FFFFFFFFFFFFFFFF
Mask for Field B: ((1 << 64) - 1) << 64             = 0x00...FFFFFFFFFFFFFFFF00...00
Mask for Field C: ((1 << 64) - 1) << 128
Mask for Field D: ((1 << 64) - 1) << 192
```

<a id="extract-field"></a>
### 💡 Concept: Extract a Field

**Goal:** Read a field's value from a packed word.

**Pattern:** Shift right to position 0, then AND with mask to discard everything above.

```
extract(word, offset, width):
    return (word >> offset) & ((1 << width) - 1)
```

**Step-by-step example:** Extract Field B (bits 64-127) from a packed word:

```
Packed word:
  0x_DDDDDDDDDDDDDDDD_CCCCCCCCCCCCCCCC_BBBBBBBBBBBBBBBB_AAAAAAAAAAAAAAAA

Step 1: Shift right by 64
  0x_0000000000000000_DDDDDDDDDDDDDDDD_CCCCCCCCCCCCCCCC_BBBBBBBBBBBBBBBB
                                                         ^^^^^^^^^^^^^^^^
                                                         Field B is now at position 0

Step 2: AND with mask (64 bits of 1s)
  0x_0000000000000000_0000000000000000_0000000000000000_BBBBBBBBBBBBBBBB
                                                       ^^^^^^^^^^^^^^^^
                                                       Only Field B remains
```

In Solidity:
```solidity
uint256 fieldB = (packed >> 64) & type(uint64).max;
```

In assembly:
```yul
let fieldB := and(shr(64, packed), 0xFFFFFFFFFFFFFFFF)
```

#### Alternative Form: Mask First, Then Shift

```
extract(word, offset, width):
    return (word & (mask << offset)) >> offset
```

Both forms produce identical results. The first (shift-then-mask) is slightly more common because the mask is always at position 0, making it simpler.

<a id="set-field"></a>
### 💡 Concept: Set a Field (Write)

**Goal:** Replace a field's value in a packed word without disturbing other fields.

**Pattern:** Clear the field, then OR in the new value.

```
set(word, offset, width, newValue):
    mask = ((1 << width) - 1) << offset
    return (word & ~mask) | ((newValue << offset) & mask)
```

This is a **read-modify-write** operation — three steps:

**Step-by-step:** Set Field B (bits 64-127) to `0x1234567812345678`:

```
Packed word:
  0x_DDDDDDDDDDDDDDDD_CCCCCCCCCCCCCCCC_BBBBBBBBBBBBBBBB_AAAAAAAAAAAAAAAA

Step 1: Create positioned mask
  mask << 64 = 0x_0000000000000000_0000000000000000_FFFFFFFFFFFFFFFF_0000000000000000

Step 2: Clear the field — AND with inverted mask
  ~mask      = 0x_FFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF_0000000000000000_FFFFFFFFFFFFFFFF
  word & ~mask:
  0x_DDDDDDDDDDDDDDDD_CCCCCCCCCCCCCCCC_0000000000000000_AAAAAAAAAAAAAAAA
                                        ^^^^^^^^^^^^^^^^
                                        Field B is now zero

Step 3: Position new value and OR
  newValue << 64 = 0x_0000000000000000_0000000000000000_1234567812345678_0000000000000000

  cleared | positioned:
  0x_DDDDDDDDDDDDDDDD_CCCCCCCCCCCCCCCC_1234567812345678_AAAAAAAAAAAAAAAA
                                        ^^^^^^^^^^^^^^^^
                                        New value in place, others untouched ✓
```

In assembly:
```yul
// Clear field B (bits 64-127), then write new value
let mask := shl(64, 0xFFFFFFFFFFFFFFFF)
let cleared := and(packed, not(mask))
let result := or(cleared, shl(64, newValue))
```

<a id="clear-field"></a>
### 💡 Concept: Clear a Field

**Goal:** Zero out a specific field without touching others.

**Pattern:** AND with the inverted positioned mask.

```
clear(word, offset, width):
    mask = ((1 << width) - 1) << offset
    return word & ~mask
```

This is just step 2 of the "set a field" pattern — without the OR step.

```solidity
// Clear bits 16-31
uint256 cleared = packed & ~(uint256(0xFFFF) << 16);
```

```yul
let cleared := and(packed, not(shl(16, 0xFFFF)))
```

<a id="toggle-bit"></a>
### 💡 Concept: Toggle a Bit

**Goal:** Flip a single bit — if it's 0, make it 1; if it's 1, make it 0.

**Pattern:** XOR with a 1 at the target position.

```
toggle(word, position):
    return word ^ (1 << position)
```

XOR's self-inverse property means toggling twice returns to the original:
```
word ^ (1 << 5) ^ (1 << 5) == word   // always true
```

```
Before:   ...0110_1010
Toggle bit 4:
  XOR     ...0001_0000
  Result: ...0111_1010
               ^
               flipped from 0 to 1

Toggle bit 4 again:
  XOR     ...0001_0000
  Result: ...0110_1010  ← back to original
```

<a id="masking-mistakes"></a>
### 💡 Concept: Common Masking Mistakes

#### Mistake 1: OR Without Clearing First

```solidity
// ⚠️ WRONG — bits accumulate instead of replace:
packed = packed | (newValue << offset);

// If the field already had non-zero bits, they persist!
// Old: ...1111_0000...    Field was 0xF0
// OR:  ...1010_0000...    New value 0xA0
// Got: ...1111_0000...    Still 0xF0! (1 OR 1 = 1)
```

**Fix:** Always clear before OR-ing:
```solidity
packed = (packed & ~(mask << offset)) | (newValue << offset);
```

#### Mistake 2: Off-by-One in Shift Amounts

```solidity
// Field is at bits 16-31 (16 bits wide, starting at bit 16)
uint256 value = (packed >> 15) & 0xFFFF;  // ⚠️ WRONG — shifted by 15, not 16
uint256 value = (packed >> 16) & 0xFFFF;  // ✅ Correct
```

The shift amount is the **starting bit position**, not "the bit before the field."

#### Mistake 3: Mask Too Wide

```solidity
// Trying to extract a 16-bit field but using 32-bit mask
uint256 value = (packed >> 16) & 0xFFFFFFFF;  // ⚠️ Reads 32 bits — includes adjacent field!
uint256 value = (packed >> 16) & 0xFFFF;      // ✅ Reads exactly 16 bits
```

#### Mistake 4: Dirty Upper Bits When Packing

```solidity
// newValue might have bits above the field width
uint256 newValue = 0x1FFFF;  // 17 bits! But field is only 16 bits wide

packed = (packed & ~(0xFFFF << 16)) | (newValue << 16);
// ⚠️ The extra bit (bit 32) corrupts the adjacent field!

// Fix: mask the value before packing
packed = (packed & ~(0xFFFF << 16)) | ((newValue & 0xFFFF) << 16);
```

---

## 💡 Bitmap Sets

A bitmap is a data structure where each bit represents the presence or absence of an element. A single `uint256` can track 256 boolean flags with O(1) access — set, check, clear, and even set-algebraic operations like union and intersection, all in a single operation.

<a id="bitmap-concept"></a>
### 💡 Concept: uint256 as 256 Booleans

**Why this matters:** Storing 256 separate `bool` variables costs 256 storage slots (256 × 2,100 = 537,600 gas cold). A bitmap stores them all in one slot (2,100 gas cold). That's a 256x gas reduction.

```
uint256 bitmap:
┌───┬───┬───┬───┬───┬─────┬───┬───┬───┬───┐
│255│254│253│...│ 5 │  4  │ 3 │ 2 │ 1 │ 0 │  ← bit position = element index
│ 0 │ 0 │ 1 │...│ 1 │  0  │ 1 │ 0 │ 1 │ 1 │  ← 1 = present, 0 = absent
└───┴───┴───┴───┴───┴─────┴───┴───┴───┴───┘

This bitmap contains elements: {0, 1, 3, 5, 253, ...}
```

<a id="bitmap-core"></a>
### 💡 Concept: Core Operations

All bitmap operations are single instructions:

#### Check Membership

**"Is element `i` in the set?"**

```solidity
bool member = ((bitmap >> i) & 1) != 0;
```

```yul
let member := and(shr(i, bitmap), 1)
```

Shift the target bit to position 0, then AND with 1 to isolate it.

#### Add to Set

**"Add element `i` to the set."**

```solidity
bitmap = bitmap | (1 << i);
```

```yul
bitmap := or(bitmap, shl(i, 1))
```

OR with a 1 at position `i`. If the bit is already set, OR is idempotent — no harm done.

#### Remove from Set

**"Remove element `i` from the set."**

```solidity
bitmap = bitmap & ~(1 << i);
```

```yul
bitmap := and(bitmap, not(shl(i, 1)))
```

AND with 0 at position `i` (the inverted mask). All other bits preserved.

#### Toggle Membership

**"Flip element `i` — add if absent, remove if present."**

```solidity
bitmap = bitmap ^ (1 << i);
```

#### Check if Empty

```solidity
bool empty = bitmap == 0;
```

```yul
let empty := iszero(bitmap)
```

<a id="set-algebra"></a>
### 💡 Concept: Set Algebra

The power of bitmaps: set-theoretic operations are single instructions.

```
Set A:  0b_1100_1010
Set B:  0b_1010_0110

Union (A ∪ B) — elements in A OR B:
  A | B = 0b_1110_1110

Intersection (A ∩ B) — elements in BOTH:
  A & B = 0b_1000_0010

Difference (A \ B) — elements in A but NOT B:
  A & ~B = 0b_0100_1000

Symmetric Difference (A △ B) — elements in one but NOT both:
  A ^ B = 0b_0110_1100
```

Each of these is a single EVM opcode (3 gas). Compared to looping through arrays and checking membership, this is orders of magnitude more efficient.

```solidity
// Check if setA is a subset of setB (every element of A is in B)
bool isSubset = (setA & setB) == setA;

// Check if sets overlap (share any elements)
bool overlaps = (setA & setB) != 0;

// Merge two sets
uint256 merged = setA | setB;
```

<a id="popcount"></a>
### 💡 Concept: Population Count (Counting Set Bits)

**"How many elements are in this bitmap set?"**

This is the **Hamming weight** or **popcount** problem. There's no EVM opcode for it, but there's an elegant O(log n) algorithm.

#### The Naive Approach

```solidity
function popcount(uint256 x) pure returns (uint256 count) {
    while (x != 0) {
        count += x & 1;
        x >>= 1;
    }
}
```

This loops up to 256 times. For a small number of set bits, there's a faster loop using "clear lowest set bit":

```solidity
function popcount(uint256 x) pure returns (uint256 count) {
    while (x != 0) {
        x = x & (x - 1);  // Clear lowest set bit
        count++;
    }
}
```

This loops once per set bit — much faster when only a few bits are set.

#### The Parallel Bit-Counting Trick

For a constant-time solution, count bits in parallel using divide-and-conquer:

```
Concept (shown with 8 bits for clarity):

Input:    1  0  1  1  0  1  1  0

Step 1: Count pairs of bits (add adjacent bits)
          01    10    01    01
          (1)   (2)   (1)   (1)

Step 2: Count groups of 4 (add adjacent pairs)
            0011      0010
             (3)       (2)

Step 3: Count groups of 8 (add adjacent quads)
               00000101
                  (5)     ← 5 bits were set ✓
```

Each step doubles the group size, using masks to isolate alternating groups:

```solidity
// Step 1: Count bits in pairs
// Mask 0x55...55 = ...0101_0101 (selects even-position bits)
x = (x & 0x5555...5555) + ((x >> 1) & 0x5555...5555);

// Step 2: Count bits in nibbles (groups of 4)
// Mask 0x33...33 = ...0011_0011 (selects lower 2 of each 4)
x = (x & 0x3333...3333) + ((x >> 2) & 0x3333...3333);

// Step 3: Count bits in bytes (groups of 8)
x = (x & 0x0F0F...0F0F) + ((x >> 4) & 0x0F0F...0F0F);

// Continue doubling: 16, 32, 64, 128, 256
// ... (or use a multiply trick to sum all bytes at once)
```

The total operation count is constant regardless of input — no loops, no branches.

<a id="iterate-bits"></a>
### 💡 Concept: Iterating Over Set Bits

**"Process each element in the bitmap set."**

Pattern: repeatedly isolate and clear the lowest set bit.

```solidity
function forEachBit(uint256 bitmap) pure {
    while (bitmap != 0) {
        // Isolate the lowest set bit
        uint256 lsb = bitmap & (~bitmap + 1);  // same as bitmap & (-bitmap)

        // Find its position (index)
        // lsb is a power of 2 — its log2 gives the bit position
        uint256 index = log2(lsb);

        // Process element 'index'
        // ...

        // Clear the lowest set bit and continue
        bitmap = bitmap & (bitmap - 1);
    }
}
```

This visits each set bit exactly once, in order from lowest to highest.

<a id="multi-word"></a>
### 💡 Concept: Multi-Word Bitmaps

When 256 bits aren't enough, extend to multiple words:

```solidity
mapping(uint256 => uint256) private bitmap;

function isSet(uint256 index) internal view returns (bool) {
    uint256 wordIndex = index >> 8;       // index / 256
    uint256 bitIndex  = index & 0xFF;     // index % 256
    return ((bitmap[wordIndex] >> bitIndex) & 1) != 0;
}

function set(uint256 index) internal {
    uint256 wordIndex = index >> 8;
    uint256 bitIndex  = index & 0xFF;
    bitmap[wordIndex] |= (1 << bitIndex);
}
```

Note the use of bit tricks for the index decomposition:
- `index >> 8` is `index / 256` (SHR is cheaper than DIV)
- `index & 0xFF` is `index % 256` (AND is cheaper than MOD)

Both work because 256 is a power of 2. This pattern is covered in detail in the [Power-of-2 Tricks](#mod-pow2) section.

---

## 💡 LSB & MSB Isolation

Isolating the lowest or highest set bit in a word is one of the most useful bit manipulation primitives. It's the core of bitmap iteration, binary search on bit positions, and several algorithmic tricks.

<a id="isolate-lsb"></a>
### 💡 Concept: Isolate the Lowest Set Bit

**The trick:** `x & (-x)`

**Result:** A value with only the lowest set bit of `x` remaining. All other bits are zero.

```
x      = 0b_1010_1100
-x     = 0b_0101_0100  (flip + add 1)
x & -x = 0b_0000_0100  ← only the lowest set bit
```

**Why it works — step by step:**

```
x  = ...1010_1100
           ^^
           lowest set bit is here (bit 2)

Step 1: ~x (flip all bits)
~x = ...0101_0011

Step 2: ~x + 1 = -x (add 1)
-x = ...0101_0100
     The +1 carry propagates through the trailing 1s of ~x,
     flipping them to 0, until it reaches the first 0 (which was
     the lowest set bit of x), flipping it to 1.

Step 3: x & -x
x  = ...1010_1100
-x = ...0101_0100
AND= ...0000_0100  ← only bit 2 survives
```

The key insight: `-x` has the same lowest set bit as `x`, but all higher bits are inverted. AND-ing them cancels everything except that one bit.

```yul
let lsb := and(x, sub(0, x))   // x & (-x)
```

The result is always a power of 2 (or zero if x was zero).

<a id="clear-lsb"></a>
### 💡 Concept: Clear the Lowest Set Bit

**The trick:** `x & (x - 1)`

**Result:** `x` with its lowest set bit turned off.

```
x      = 0b_1010_1100
x - 1  = 0b_1010_1011  (subtracting 1 flips the lowest set bit and all zeros below it)
x & x-1= 0b_1010_1000  ← lowest set bit cleared
```

**Why it works:**

```
x      = ...1010_1100
                 ^
                 lowest set bit

x - 1  = ...1010_1011
                 ^
     Subtraction borrows from the lowest set bit:
     - That bit flips 0→1... wait, let's trace carefully:
     - Starting from the right, bit 0 is 0, borrow propagates
     - Bit 1 is 0, borrow propagates
     - Bit 2 is 1, borrow stops: this bit becomes 0, all bits below become 1
     x-1 = ...1010_1011

x & (x-1):
     ...1010_1100
   & ...1010_1011
   = ...1010_1000
     The lowest set bit and everything below it are now all different,
     so AND zeroes them. Everything above is identical, so AND preserves them.
```

This is the foundation of several tricks:
- **Iteration:** Clear the lowest bit after processing it
- **`isPowerOfTwo`:** A power of 2 has exactly one bit, so `x & (x-1) == 0`
- **Counting set bits:** Loop: clear lowest bit, increment counter, repeat until zero

<a id="ctz"></a>
### 💡 Concept: Count Trailing Zeros (CTZ)

**"How many zero bits are below the lowest set bit?"**

This tells you the **position** of the lowest set bit. Equivalent to `log2(x & -x)`.

#### Approach 1: Loop

```solidity
function ctz(uint256 x) pure returns (uint256 count) {
    if (x == 0) return 256;  // No set bits
    uint256 lsb = x & (~x + 1);  // Isolate LSB
    // lsb is a power of 2 — count how many times to shift
    while (lsb > 1) {
        lsb >>= 1;
        count++;
    }
}
```

Worst case: 255 iterations.

#### Approach 2: Binary Search

The same approach used for finding MSB (discussed later), but applied to the isolated LSB:

```solidity
function ctz(uint256 x) pure returns (uint256 r) {
    if (x == 0) return 256;
    x = x & (~x + 1);  // Isolate LSB (now a power of 2)

    // Binary search: is the set bit in the upper half?
    if (x >= (1 << 128)) { r += 128; x >>= 128; }
    if (x >= (1 << 64))  { r += 64;  x >>= 64; }
    if (x >= (1 << 32))  { r += 32;  x >>= 32; }
    if (x >= (1 << 16))  { r += 16;  x >>= 16; }
    if (x >= (1 << 8))   { r += 8;   x >>= 8; }
    if (x >= (1 << 4))   { r += 4;   x >>= 4; }
    if (x >= (1 << 2))   { r += 2;   x >>= 2; }
    if (x >= (1 << 1))   { r += 1; }
}
```

8 comparisons regardless of input. Constant-time.

#### Approach 3: De Bruijn Sequence (Constant-Time Lookup)

A de Bruijn sequence is a special number where every `n`-bit substring (when shifted) is unique. By multiplying the isolated LSB by this magic constant and shifting, you get a unique index that maps to a lookup table.

```solidity
// For 256-bit values, the de Bruijn constant and table are large.
// Simplified concept with 8 bits:

// De Bruijn constant for 8 bits: 0x17 (0b_00010111)
// Every 3-bit window in its binary expansion is unique:
// 000, 001, 010, 101, 011, 111, 110, 100

// Multiply isolated LSB by constant, shift to get table index
uint8 index = uint8((lsb * DEBRUIJN) >> 5);  // Top 3 bits = index
uint8 position = LOOKUP_TABLE[index];
```

This is O(1) with no branches — a multiply, a shift, and a table lookup. Production implementations use this for 256-bit words with a 256-entry lookup table.

<a id="find-msb"></a>
### 💡 Concept: Find the Highest Set Bit (MSB / Bit Length)

**"What is the position of the most significant set bit?"**

Equivalently: "How many bits does this number need?" (its bit-length minus 1).

**Approach: Binary search by halving.**

The idea: Is the highest set bit in the upper 128 bits or the lower 128? If upper, record 128 and shift right to focus on that half. Repeat with 64, 32, 16, 8, 4, 2, 1.

```
Input: x = 0x00000000_00000000_00000000_00000005_00000000_00000000_00000000_00000000

Is x >= 2^128?  Yes → r = 128, x >>= 128
Now x = 0x00000005

Is x >= 2^64?   No
Is x >= 2^32?   No
Is x >= 2^16?   No
Is x >= 2^8?    No
Is x >= 2^4?    No
Is x >= 2^2?    Yes → r += 2 = 130, x >>= 2
Now x = 0x01

Is x >= 2^1?    No

Result: MSB position = 130
```

In assembly (branchless version):

```yul
function findMSB(x) -> r {
    // Each step: if x is large enough, add to r and shift down
    let bit := shl(7, lt(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, x))
    r := or(r, bit)
    x := shr(bit, x)

    bit := shl(6, lt(0xFFFFFFFFFFFFFFFF, x))
    r := or(r, bit)
    x := shr(bit, x)

    bit := shl(5, lt(0xFFFFFFFF, x))
    r := or(r, bit)
    x := shr(bit, x)

    bit := shl(4, lt(0xFFFF, x))
    r := or(r, bit)
    x := shr(bit, x)

    bit := shl(3, lt(0xFF, x))
    r := or(r, bit)
    x := shr(bit, x)

    bit := shl(2, lt(0xF, x))
    r := or(r, bit)
    x := shr(bit, x)

    bit := shl(1, lt(0x3, x))
    r := or(r, bit)
    x := shr(bit, x)

    r := or(r, lt(0x1, x))
}
```

**How the branchless trick works:** `lt(threshold, x)` returns 0 or 1. `shl(7, ...)` turns that into 0 or 128. `or(r, ...)` conditionally adds 128 to the result — no JUMPI needed.

This is the same pattern used in Solady's `log2` implementation.

<a id="clz"></a>
### 💡 Concept: Count Leading Zeros (CLZ)

**"How many zero bits are above the highest set bit?"**

```
CLZ = 255 - MSB_position
```

For `x = 0`, CLZ is 256 (all bits are zero).

This is simply the inverse of finding the MSB:

```solidity
function clz(uint256 x) pure returns (uint256) {
    if (x == 0) return 256;
    return 255 - findMSB(x);
}
```

CLZ is useful for:
- Determining the bit-width of a value (256 - CLZ = bit width)
- Normalizing values for fixed-point operations
- Efficient comparisons ("does this number fit in N bits?")

---

## 💡 Power-of-2 Tricks

Powers of 2 have a special property: they have exactly one bit set. This makes them uniquely suited to bit manipulation tricks — faster than general-purpose arithmetic for alignment, modulo, and range checks.

<a id="is-pow2"></a>
### 💡 Concept: Is Power of Two

**The trick:** `x != 0 && (x & (x - 1)) == 0`

**Why it works:** A power of 2 has exactly one bit set. `x - 1` flips that bit and sets all bits below it. AND-ing gives zero — the only bit they shared was the one that got flipped.

```
x = 8:     0b_0000_1000  (one bit set — power of 2)
x - 1 = 7: 0b_0000_0111
AND:        0b_0000_0000  ← zero! ✓

x = 6:     0b_0000_0110  (two bits set — not power of 2)
x - 1 = 5: 0b_0000_0101
AND:        0b_0000_0100  ← non-zero! ✗
```

The `x != 0` check is needed because `0 & (0 - 1)` wraps to `0 & 0xFF...FF = 0`, which would incorrectly report zero as a power of 2.

```solidity
function isPowerOfTwo(uint256 x) pure returns (bool) {
    return x != 0 && (x & (x - 1)) == 0;
}
```

<a id="next-pow2"></a>
### 💡 Concept: Next Power of Two (Round Up)

**Goal:** Find the smallest power of 2 that is ≥ x.

**The approach:** Fill all bits below the highest set bit with 1s, then add 1.

```
x = 0b_0010_1001  (decimal 41)

Step 1: Smear bits downward
  x |= x >> 1   → 0b_0011_1101
  x |= x >> 2   → 0b_0011_1111
  x |= x >> 4   → 0b_0011_1111  (already done for 8-bit)

After smearing:     0b_0011_1111  (all bits below MSB are set)

Step 2: Add 1
  0b_0011_1111 + 1 = 0b_0100_0000  (decimal 64)

64 is the next power of 2 ≥ 41 ✓
```

**Why the smearing works:** Each `x |= x >> N` copies the highest set bit down by N positions. After all shifts, every bit from the MSB down to bit 0 is set. Adding 1 carries through all those 1s, producing a single bit one position above the original MSB.

For 256-bit values, you need shifts of 1, 2, 4, 8, 16, 32, 64, and 128:

```solidity
function nextPowerOfTwo(uint256 x) pure returns (uint256) {
    if (x == 0) return 1;
    x -= 1;  // Handle exact powers of 2 (e.g., 64 → 64, not 128)
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    x |= x >> 32;
    x |= x >> 64;
    x |= x >> 128;
    return x + 1;
}
```

The `x -= 1` at the start ensures that exact powers of 2 round to themselves (not the next one).

<a id="alignment"></a>
### 💡 Concept: Rounding to Alignment Boundaries

**Goal:** Round a value up or down to the nearest multiple of a power-of-2 alignment.

#### Round Down (Floor)

```
roundDown(x, alignment):
    return x & ~(alignment - 1)
```

This clears the lower bits — equivalent to rounding down to the nearest multiple.

```
x = 37,  alignment = 16

alignment - 1 = 15 = 0b_0000_1111
~15           =      0b_1111_0000

37 & ~15:
  0b_0010_0101   (37)
& 0b_1111_0000
= 0b_0010_0000   (32) ← nearest multiple of 16 ≤ 37 ✓
```

#### Round Up (Ceiling)

```
roundUp(x, alignment):
    return (x + alignment - 1) & ~(alignment - 1)
```

Add `alignment - 1` first to "push" past the boundary if not already aligned, then round down.

```
x = 37, alignment = 16

37 + 15 = 52
52 & ~15:
  0b_0011_0100   (52)
& 0b_1111_0000
= 0b_0011_0000   (48) ← nearest multiple of 16 ≥ 37 ✓
```

**EVM memory uses this pattern** for 32-byte word alignment:

```yul
// Round size up to nearest 32-byte boundary
let aligned := and(add(size, 31), not(31))
```

<a id="mod-pow2"></a>
### 💡 Concept: Modulo by Power of 2

**The trick:** `x & (modulus - 1)` replaces `x % modulus` when modulus is a power of 2.

**Why it works:** The remainder of dividing by 2^n is exactly the lower `n` bits.

```
x = 53, modulus = 16 (2⁴)

53 % 16 = 5

53 in binary: 0b_0011_0101
  16 - 1 = 15: 0b_0000_1111

53 & 15:
  0b_0011_0101
& 0b_0000_1111
= 0b_0000_0101  (5) ✓
```

The lower 4 bits ARE the remainder when dividing by 16. The upper bits represent how many complete groups of 16 fit.

```solidity
// These are equivalent (when modulus is a power of 2):
uint256 r = x % 256;       // MOD opcode: 5 gas
uint256 r = x & 255;       // AND opcode: 3 gas
uint256 r = x & 0xFF;      // Same thing, hex notation
```

This pattern appears in multi-word bitmap indexing:
```solidity
uint256 wordIndex = index >> 8;     // index / 256
uint256 bitIndex  = index & 0xFF;   // index % 256
```

---

## 💡 Common Bit Idioms

These are recurring patterns built from the primitives above. They appear in production code, gas-optimized libraries, and assembly routines. Each one replaces a branching operation with pure arithmetic.

<a id="branchless-select"></a>
### 💡 Concept: Branchless Conditional Select

**Goal:** Select value `a` or `b` based on a condition, without branching (no `if`, no JUMPI).

**Pattern:**

```
select(condition, a, b):
    mask = 0 - condition        // condition is 0 or 1
    return b ^ (mask & (a ^ b)) // if mask=0: b; if mask=all-1s: a
```

**How it works:**

```
Case 1: condition = 1 (select a)
  mask = 0 - 1 = 0xFFFF...FFFF  (all 1s)
  a ^ b = difference bits
  mask & (a ^ b) = a ^ b        (all bits pass through)
  b ^ (a ^ b) = a               ✓

Case 2: condition = 0 (select b)
  mask = 0 - 0 = 0x0000...0000  (all 0s)
  mask & (a ^ b) = 0            (all bits blocked)
  b ^ 0 = b                     ✓
```

**Why branchless matters:** In the EVM, `JUMPI` costs 10 gas and introduces a conditional code path. Branchless select uses AND + XOR (6 gas total) and executes the same instructions regardless of the condition — constant gas, no jump.

```yul
// Select between two values based on a boolean (0 or 1)
let mask := sub(0, condition)
let result := xor(b, and(mask, xor(a, b)))
```

<a id="branchless-minmax"></a>
### 💡 Concept: Branchless Min / Max

Built on conditional select:

```yul
// min(a, b)
let isLess := lt(a, b)                      // 1 if a < b, 0 otherwise
let mask := sub(0, isLess)                   // all-1s if a < b, all-0s otherwise
let minimum := xor(b, and(mask, xor(a, b))) // select a if a < b, else b

// max(a, b) — flip the condition
let isGreater := lt(b, a)
let mask2 := sub(0, isGreater)
let maximum := xor(b, and(mask2, xor(a, b)))
```

Or more directly:

```yul
// min(a, b) — equivalent but easier to read
let minimum := xor(a, and(xor(a, b), sub(0, lt(b, a))))
```

Trace with `a = 5, b = 3`:
```
lt(b, a) = lt(3, 5) = 1
sub(0, 1) = 0xFFFF...FFFF (all 1s)
xor(a, b) = xor(5, 3) = 6
and(0xFFFF...FFFF, 6) = 6
xor(a, 6) = xor(5, 6) = 3 = min(5, 3) ✓
```

<a id="branchless-abs"></a>
### 💡 Concept: Branchless Absolute Value

**The trick:** Use SAR to extract the sign, then conditionally negate.

```yul
let mask := sar(255, x)    // All-zeros if x ≥ 0, all-ones if x < 0
let abs_x := xor(add(x, mask), mask)
```

**How it works:**

```
Case 1: x = 5 (positive)
  sar(255, 5) = 0x00...00 (all zeros — sign bit was 0)
  add(5, 0) = 5
  xor(5, 0) = 5 ✓

Case 2: x = -5 (negative)
  sar(255, -5) = 0xFF...FF (all ones — sign bit was 1)
  add(-5, 0xFF...FF) = add(-5, -1) = -6
  xor(-6, 0xFF...FF) = ~(-6) = 5 ✓
```

**Why `xor(x, all_ones)` = `~x`:** XOR with 1 flips each bit — same as NOT.

**Why `~(-6) = 5`:** In two's complement, `~x = -x - 1`, so `~(-6) = 6 - 1 = 5`.

The combined effect of `add(x, -1)` then NOT is: `~(x - 1) = -x`. This is the two's complement negation rule in disguise.

<a id="xor-swap"></a>
### 💡 Concept: Swap Without Temporary

**The XOR swap:**

```yul
a := xor(a, b)    // a now holds a^b
b := xor(b, a)    // b = b ^ (a^b) = a  (original a)
a := xor(a, b)    // a = (a^b) ^ a = b  (original b)
```

**Trace with a = 5, b = 3:**
```
a = xor(5, 3)  = 6
b = xor(3, 6)  = 5  (original a ✓)
a = xor(6, 5)  = 3  (original b ✓)
```

**Why it works:** XOR is self-inverse. `a ^ b ^ b = a`. Each step undoes one layer.

#### ⚠️ Warning: Aliasing

If `a` and `b` refer to the same memory location (or same variable), XOR swap fails:

```
// If a and b alias the same location:
a = xor(a, a) = 0      // Oops — zeroed out!
b = xor(0, 0) = 0
a = xor(0, 0) = 0      // Both are zero. Data lost.
```

In practice, this aliasing issue rarely occurs in EVM assembly (stack variables don't alias), but be aware of it for memory/storage operations.

<a id="dirty-bits"></a>
### 💡 Concept: Dirty Bits & Cleaning

**The problem:** The EVM operates on 256-bit words, but most types are smaller. An `address` is 160 bits, a `uint96` is 96 bits, a `bool` is 1 bit. The remaining bits in the word can contain leftover data from previous operations — these are **dirty bits**.

**Why it matters:**

```yul
// Suppose 'addr' has garbage in the upper 96 bits:
// addr = 0xDEADBEEF_AAAAAAAA_BBBBBBBB_11111111_22222222_33333333_44444444_55555555
//        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//        dirty bits (should be zero for a 160-bit address)

// Comparing with another clean address will FAIL even if the lower 160 bits match:
let same := eq(addr, clean_addr)   // Returns 0 (false) because upper bits differ!
```

**Cleaning patterns:**

```yul
// Method 1: AND with mask
let clean := and(addr, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)  // 160-bit mask

// Method 2: Shift left then right (clears upper bits)
let clean := shr(96, shl(96, addr))  // shift left 96 (push dirty bits off), shift right 96

// Method 3: For Solidity-level code, explicit cast
address cleaned = address(uint160(dirtyValue));
```

**When dirty bits appear:**
- Reading raw calldata in assembly (callers can send garbage in upper bytes)
- After arithmetic on packed fields (carry bits can leak)
- After `mload` on memory that wasn't fully initialized
- Return values from external calls (malicious contracts can return dirty data)

**The rule:** Always clean values **before** using them in comparisons, storage writes, or LOG topics. Dirty bits in storage waste gas (non-zero bytes cost more) and can cause logic errors.

<a id="multi-condition"></a>
### 💡 Concept: Checking Multiple Conditions at Once

**Goal:** Check if several boolean conditions are all true (or all false) in a single operation.

**Pattern:** Pack conditions into a bitmap, then use AND to check them all at once.

```solidity
uint256 constant ACTIVE       = 1 << 0;  // bit 0
uint256 constant NOT_PAUSED   = 1 << 1;  // bit 1
uint256 constant HAS_BALANCE  = 1 << 2;  // bit 2

uint256 constant REQUIRED = ACTIVE | NOT_PAUSED | HAS_BALANCE;  // 0b_111

// Check all conditions at once
uint256 flags = ...;  // Each bit set based on current state
bool allMet = (flags & REQUIRED) == REQUIRED;
```

**How it works:**

```
flags    = 0b_101  (ACTIVE and HAS_BALANCE, but paused)
REQUIRED = 0b_111

flags & REQUIRED = 0b_101
0b_101 == 0b_111 → false (NOT_PAUSED bit missing)
```

**Checking forbidden conditions** (none should be set):

```solidity
uint256 constant FORBIDDEN = BLACKLISTED | EXPIRED;

bool noForbidden = (flags & FORBIDDEN) == 0;
```

This replaces chained `&&` conditions with a single AND + comparison — fewer opcodes, constant gas, cleaner code.

---

<a id="exercise1"></a>
## 🎯 Build Exercise: BitToolkit

**Workspace:**
- Implementation: [`workspace/src/deep-dives/bit-manipulation/exercise1-bit-toolkit/BitToolkit.sol`](../workspace/src/deep-dives/bit-manipulation/exercise1-bit-toolkit/BitToolkit.sol)
- Tests: [`workspace/test/deep-dives/bit-manipulation/exercise1-bit-toolkit/BitToolkit.t.sol`](../workspace/test/deep-dives/bit-manipulation/exercise1-bit-toolkit/BitToolkit.t.sol)

Build a reusable bit manipulation library that implements the core patterns from this deep dive. The library works with packed `uint256` words and bitmap sets.

**What you'll implement:**

1. **`extractField`** — Extract a field of `width` bits at `offset` from a packed word
2. **`setField`** — Write a value into a field (read-modify-write pattern)
3. **`bitmapAdd` / `bitmapRemove` / `bitmapContains`** — Bitmap set operations
4. **`popcount`** — Count the number of set bits in a word
5. **`isolateLSB`** — Isolate the lowest set bit
6. **`isPowerOfTwo`** — Check if a value is a power of 2
7. **`branchlessSelect`** — Select between two values without branching

**🎯 Goal:** Internalize the core bit manipulation patterns so that reading (and writing) packed data structures becomes second nature.

Run: `forge test --match-contract BitToolkitTest -vvv`

---

## 📋 Summary

**✓ Covered:**

- **Foundations:** AND, OR, XOR, NOT as filter/combiner/flipper/inverter; SHL, SHR, SAR with visual bit diagrams; BYTE opcode and big-endian byte ordering; precedence traps in Solidity vs explicit nesting in assembly
- **Two's complement:** Flip-and-add-1 encoding, the asymmetric number line, why addition works for both signed and unsigned, sign extension for type widening, SIGNEXTEND opcode for assembly, SAR vs SHR on negative values
- **Masking patterns:** Building masks from width and offset, extract/set/clear/toggle as a system, read-modify-write as the complete pattern, four common masking mistakes
- **Bitmap sets:** uint256 as 256 booleans, membership/add/remove in single opcodes, set algebra (union/intersection/difference) as AND/OR, population count with parallel counting, iteration via LSB clearing, multi-word extension with mapping
- **LSB & MSB:** Isolate lowest set bit with `x & -x`, clear lowest with `x & (x-1)`, count trailing zeros (loop, binary search, de Bruijn), find highest set bit with halving binary search, branchless MSB in assembly
- **Power-of-2 tricks:** isPowerOfTwo, next power of two via bit smearing, alignment rounding (floor and ceiling), modulo by AND
- **Bit idioms:** Branchless select/min/max/abs, XOR swap (with aliasing warning), dirty bits and cleaning patterns, multi-condition checking with bitmap flags

---

## 📚 Resources

### EVM Reference
- [EVM Opcodes — Bitwise](https://www.evm.codes/#16) — Interactive reference for AND, OR, XOR, NOT, SHL, SHR, SAR, BYTE, SIGNEXTEND
- [Solidity Docs — Operators](https://docs.soliditylang.org/en/latest/types.html#operators) — Precedence table and type rules

### Bit Manipulation
- [Bit Twiddling Hacks (Stanford)](https://graphics.stanford.edu/~seander/bithacks.html) — Classic reference for bit tricks (C-focused, but the math is universal)
- [Chess Programming Wiki — Bitboards](https://www.chessprogramming.org/Bitboards) — Deep dive on bitmap sets (chess uses 64-bit bitmaps extensively)
- [Hacker's Delight (Henry Warren)](https://en.wikipedia.org/wiki/Hacker%27s_Delight) — The definitive book on bit manipulation

### Production Code Using These Patterns
- [Solady FixedPointMathLib](https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol) — log2, sqrt, mulDiv using branchless bit tricks
- [OpenZeppelin BitMaps](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/BitMaps.sol) — Multi-word bitmap implementation

---

**Navigation:** [← Errors](errors.md) | [Deep Dives Overview](README.md)
