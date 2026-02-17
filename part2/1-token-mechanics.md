# Part 2 — Module 1: Token Mechanics in Practice

**Duration:** ~1 day (3–4 hours)
**Prerequisites:** Part 1 complete (including Permit and Permit2 from Section 3), Foundry installed
**Pattern:** Concept → Read production code → Build → Extend
**Builds on:** Part 1 Section 3 (Permit/Permit2), Part 1 Section 5 (Foundry)
**Used by:** Every subsequent module — SafeERC20, balance-before-after, and WETH patterns are foundational

---

## Why This Module Comes First

Every DeFi protocol moves tokens. AMMs swap them, lending pools custody them, vaults compound them. Before you build any of that, you need to deeply understand how token interactions actually work at the contract level — not just the ERC-20 interface, but the real-world edge cases that have caused millions in losses. This module gives you the vocabulary and patterns that every subsequent module depends on.

> **Note:** Permit (EIP-2612) and Permit2 patterns are covered in Part 1 Section 3. This module focuses on the ERC-20 edge cases and safe integration patterns that will affect every protocol you build in Part 2.

---

## ERC-20 Interactions in DeFi Context

### Concept: The Approval Model

You know the ERC-20 interface. What matters for DeFi development is understanding *why* the approve/transferFrom two-step exists and how it shapes every protocol interaction.

The core problem: a smart contract can't "pull" tokens from a user without prior authorization. Unlike ETH (which can be sent with `msg.value`), ERC-20 tokens require the user to first call `approve(spender, amount)` on the token contract, granting the spender permission. The protocol then calls `transferFrom(user, protocol, amount)` to actually move the tokens.

This creates the foundational DeFi interaction pattern:

```
User → Token.approve(protocol, amount)    // tx 1: grant permission
User → Protocol.deposit(amount)           // tx 2: protocol calls transferFrom internally
```

Every DeFi protocol you'll ever build begins here.

### Read: OpenZeppelin ERC20 and SafeERC20

**Source:** `@openzeppelin/contracts/token/ERC20/ERC20.sol` (v5.x)
**Source:** `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`

Read the OpenZeppelin ERC20 implementation end-to-end. Pay attention to:

- The `_update()` function (v5.x replaced `_beforeTokenTransfer`/`_afterTokenTransfer` hooks with a single `_update` function — this is a design change you'll encounter when reading older protocol code vs newer code)
- How `approve()` and `transferFrom()` interact through the `_allowances` mapping
- The `_spendAllowance()` helper and its special case for `type(uint256).max` (infinite approval)

Then read SafeERC20 carefully. This is not optional — it's mandatory for any protocol that accepts arbitrary tokens. The key insight: the ERC-20 standard says `transfer()` and `transferFrom()` should return `bool`, but major tokens like USDT don't return anything at all. SafeERC20 handles this by using low-level calls and checking both the return data length and value.

**Key functions to understand:**
- `safeTransfer` / `safeTransferFrom` — handles non-compliant tokens
- `forceApprove` — replaces the deprecated `safeApprove`, handles USDT's "must approve to 0 first" behavior

### Read: The Weird ERC-20 Catalog

**Source:** https://github.com/d-xo/weird-erc20

This repository documents real tokens with behaviors that break naive assumptions. As a protocol builder, you must design for these. The critical categories:

**Missing return values** — USDT, BNB, OMG don't return `bool`. If your protocol does `require(token.transfer(...))`, it will fail on these tokens. SafeERC20 exists specifically for this.

**Fee-on-transfer tokens** — STA, PAXG, and others deduct a fee on every transfer. If a user sends 100 tokens, the protocol might only receive 97. The standard pattern to handle this:

```solidity
uint256 balanceBefore = token.balanceOf(address(this));
token.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - balanceBefore;
// Use `received`, not `amount`
```

This "balance-before-after" pattern adds gas but is essential when supporting arbitrary tokens. You'll see this in Uniswap V2's `swap()` function and many lending protocols.

**Rebasing tokens** — stETH, AMPL, OHM change user balances automatically. A protocol that stores `balanceOf` at deposit time may find the actual balance has changed by withdrawal. Protocols either: (a) wrap rebasing tokens into non-rebasing versions (wstETH), or (b) explicitly exclude them.

**Approval race condition** — If Alice has approved 100 tokens to a spender, and then calls `approve(200)`, the spender can front-run to spend the original 100, then spend the new 200, getting 300 total. USDT's "approve to zero first" requirement is a brute-force solution. Better: use `increaseAllowance`/`decreaseAllowance` (removed from OZ v5 core but still available) or Permit (Part 1 Section 3).

**Tokens that revert on zero transfer** — LEND and others revert when transferring 0 tokens. Your protocol logic needs to guard against this.

**Tokens with multiple entry points** — Some proxied tokens have multiple addresses pointing to the same contract. Don't use `address(token)` as a unique identifier without care.

### Read: WETH

**Source:** The canonical WETH9 contract (0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)

WETH exists because ETH doesn't conform to ERC-20. Protocols that want to treat ETH uniformly with other tokens use WETH. The contract is trivially simple:

- `deposit()` (payable): accepts ETH, mints equivalent WETH
- `withdraw(uint256 wad)`: burns WETH, sends ETH back

Understand that many protocols (Uniswap, Aave, etc.) have dual paths — one for ETH (wraps to WETH internally) and one for ERC-20 tokens. When you build your own protocols, you'll face the same design choice: support raw ETH, or require WETH?

### Build: Token Interaction Test Suite (Foundry)

Create a Foundry project that tests your understanding of these patterns:

```
forge init token-mechanics
cd token-mechanics
forge install OpenZeppelin/openzeppelin-contracts
```

**Exercise 1: Build a simple `Vault` contract** that accepts ERC-20 deposits and tracks balances. Requirements:
- Uses SafeERC20 for all token interactions
- Handles fee-on-transfer tokens correctly (balance-before-after pattern)
- Allows deposits and withdrawals
- Emits events for deposits and withdrawals

**Exercise 2: Write comprehensive Foundry tests** including:
- Deploy a standard ERC-20, deposit, withdraw — the happy path
- Deploy a fee-on-transfer mock token, verify the vault credits the correct (reduced) amount
- Deploy a token that doesn't return `bool` (USDT-style), verify SafeERC20 handles it
- Test the approval race condition scenario
- Test zero-amount transfer behavior

**Exercise 3: Test with a WETH wrapper path** — add a `depositETH()` function that wraps incoming ETH to WETH before depositing.

**Foundry tip:** Use `vm.mockCall` or write mock token contracts to simulate weird behaviors. For fee-on-transfer, write a simple ERC-20 that overrides `_update()` to burn 3% on every transfer.

---

## Practice Challenges

After completing this module, try these challenges to test your understanding:

- **Damn Vulnerable DeFi #15 — "ABI Smuggling":** Explores token approval patterns and how calldata can be manipulated to bypass access controls on token operations.

---

## Key Takeaways for Protocol Development

After completing this module, you should have internalized these patterns:

1. **Always use SafeERC20** — there is no reason not to. The gas overhead is negligible compared to the risk of silent failures.

2. **Balance-before-after for untrusted tokens** — if your protocol accepts arbitrary tokens, never trust `amount` parameters. Measure what you actually received.

3. **Design for weird tokens** — decide early whether your protocol supports arbitrary tokens (more complex) or a curated allowlist (simpler, safer). Most serious protocols do both: a permissionless mode with full safety checks, and an optimized path for known-good tokens.

---

## Resources

**Reference implementations:**
- OpenZeppelin ERC20 (v5.x): https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/token/ERC20
- Weird ERC-20 catalog: https://github.com/d-xo/weird-erc20
- WETH9 source: Etherscan verified at 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

**Specifications:**
- EIP-20 (ERC-20): https://eips.ethereum.org/EIPS/eip-20

**Security reading:**
- MixBytes — DeFi patterns: ERC20 token transfers: https://mixbytes.io/blog/defi-patterns-erc20-token-transfers-howto
- Integrating arbitrary ERC-20 tokens (cheat sheet): https://andrej.hashnode.dev/integrating-arbitrary-erc-20-tokens

---

*Next module: AMMs from First Principles — constant product formula, building a minimal swap pool, Uniswap V2→V3→V4 progression.*
