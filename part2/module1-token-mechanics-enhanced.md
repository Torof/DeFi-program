# Part 2 — Module 1: Token Mechanics in Practice

**Duration:** ~1 day (3–4 hours)
**Prerequisites:** Part 1 complete (including Permit and Permit2 from Section 3), Foundry installed
**Pattern:** Concept → Read production code → Build → Extend
**Builds on:** Part 1 Section 3 (Permit/Permit2), Part 1 Section 5 (Foundry)
**Used by:** Every subsequent module — SafeERC20, balance-before-after, and WETH patterns are foundational

---

## Why This Module Comes First

**Why this matters:** Every DeFi protocol moves tokens. AMMs swap them, lending pools custody them, vaults compound them. Before you build any of that, you need to deeply understand how token interactions actually work at the contract level — not just the [ERC-20 interface](https://eips.ethereum.org/EIPS/eip-20), but the real-world edge cases that have caused millions in losses.

> **Real impact:** [Hundred Finance hack](https://rekt.news/hundred-rekt/) ($7M, April 2022) — exploited lending pool that didn't account for [ERC-777 reentrancy hooks](https://github.com/d-xo/weird-erc20#tokens-with-more-than-one-address). [SushiSwap MISO incident](https://www.coindesk.com/tech/2021/09/17/3m-in-ether-stolen-from-sushiswap-token-launchpad/) ($3M, September 2021) — malicious token with transfer() that silently failed but returned true, draining auction funds.

> **Note:** Permit ([EIP-2612](https://eips.ethereum.org/EIPS/eip-2612)) and [Permit2](https://github.com/Uniswap/permit2) patterns are covered in Part 1 Section 3. This module focuses on the ERC-20 edge cases and safe integration patterns that will affect every protocol you build in Part 2.

---

## ERC-20 Interactions in DeFi Context

### Concept: The Approval Model

**Why this matters:** The approve/transferFrom two-step isn't just a design pattern — it's the foundation that every DeFi interaction is built on. Understanding *why* it exists and how it shapes protocol architecture is essential before building anything.

**The core problem:** A smart contract can't "pull" tokens from a user without prior authorization. Unlike ETH (which can be sent with `msg.value`), ERC-20 tokens require the user to first call `approve(spender, amount)` on the token contract, granting the spender permission. The protocol then calls `transferFrom(user, protocol, amount)` to actually move the tokens.

This creates the foundational DeFi interaction pattern:

```
User → Token.approve(protocol, amount)    // tx 1: grant permission
User → Protocol.deposit(amount)           // tx 2: protocol calls transferFrom internally
```

Every DeFi protocol you'll ever build begins here. [Uniswap V2](https://github.com/Uniswap/v2-core), [Aave V3](https://github.com/aave/aave-v3-core), [Compound V3](https://github.com/compound-finance/comet) — all use this exact pattern.

> **Deep dive:** [EIP-20 specification](https://eips.ethereum.org/EIPS/eip-20) defines the standard, but see [Weird ERC-20 catalog](https://github.com/d-xo/weird-erc20) for what the standard *doesn't* cover.

---

### Read: OpenZeppelin ERC20 and SafeERC20

**Source:** [@openzeppelin/contracts v5.x](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/token/ERC20)

Read the [OpenZeppelin ERC20 implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol) end-to-end. Pay attention to:

- The `_update()` function (v5.x replaced `_beforeTokenTransfer`/`_afterTokenTransfer` hooks with a single `_update` function — this is a design change you'll encounter when reading older protocol code vs newer code)
- How `approve()` and `transferFrom()` interact through the `_allowances` mapping
- The `_spendAllowance()` helper and its special case for `type(uint256).max` (infinite approval)

Then read [SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) carefully. This is not optional — it's mandatory for any protocol that accepts arbitrary tokens.

**The key insight:** The [ERC-20 standard](https://eips.ethereum.org/EIPS/eip-20) says `transfer()` and `transferFrom()` should return `bool`, but major tokens like [USDT](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7) don't return anything at all. SafeERC20 handles this by using low-level calls and checking both the return data length and value.

**Key functions to understand:**
- `safeTransfer` / `safeTransferFrom` — handles non-compliant tokens that don't return bool
- `forceApprove` — replaces the deprecated `safeApprove`, handles USDT's "must approve to 0 first" behavior

> **Used by:** [Uniswap V3 NonfungiblePositionManager](https://github.com/Uniswap/v3-periphery/blob/main/contracts/NonfungiblePositionManager.sol#L9), [Aave V3 Pool](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L11), [Compound V3 Comet](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) — every major protocol uses SafeERC20.

---

### Read: The Weird ERC-20 Catalog

**Source:** [github.com/d-xo/weird-erc20](https://github.com/d-xo/weird-erc20)

**Why this matters:** This repository documents real tokens with behaviors that break naive assumptions. As a protocol builder, you must design for these. The critical categories:

**1. Missing return values**

[USDT](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code), [BNB](https://etherscan.io/token/0xB8c77482e45F1F44dE1745F52C74426C631bDD52), [OMG](https://etherscan.io/token/0xd26114cd6EE289AccF82350c8d8487fedB8A0C07) don't return `bool`. If your protocol does `require(token.transfer(...))`, it will fail on these tokens. SafeERC20 exists specifically for this.

> **Common pitfall:** Writing `require(token.transfer(to, amount))` without SafeERC20. This compiles fine with standard ERC-20 but silently reverts with USDT. Always use `token.safeTransfer(to, amount)`.

**2. Fee-on-transfer tokens**

[STA](https://etherscan.io/token/0xa7DE087329BFcda5639aF29130af3Da1C99dF6e4), [PAXG](https://etherscan.io/token/0x45804880De22913dAFE09f4980848ECE6EcbAf78), and others deduct a fee on every transfer. If a user sends 100 tokens, the protocol might only receive 97.

**The standard pattern to handle this:**

```solidity
uint256 balanceBefore = token.balanceOf(address(this));
token.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - balanceBefore;
// Use `received`, not `amount`
```

This "balance-before-after" pattern adds ~2,000 gas but is essential when supporting arbitrary tokens. You'll see this in [Uniswap V2's `swap()` function](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L159-L160) and many lending protocols.

> **Real impact:** Early AMM forks that assumed `amount` == received balance got arbitraged to death when fee-on-transfer tokens were added to pools. The fee was extracted by the token contract but the AMM credited the full amount, leading to protocol insolvency.

**3. Rebasing tokens**

[stETH](https://etherscan.io/token/0xae7ab96520de3a18e5e111b5eaab095312d7fe84), [AMPL](https://etherscan.io/token/0xd46ba6d942050d489dbd938a2c909a5d5039a161), [OHM](https://etherscan.io/token/0x64aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5) change user balances automatically. A protocol that stores `balanceOf` at deposit time may find the actual balance has changed by withdrawal.

**Protocols either:**
- (a) Wrap rebasing tokens into non-rebasing versions ([wstETH](https://docs.lido.fi/contracts/wsteth/) for stETH)
- (b) Explicitly exclude them ([Uniswap V2 explicitly warns against rebasing tokens](https://docs.uniswap.org/contracts/v2/reference/smart-contracts/common-errors#rebasing-tokens))

> **Used by:** [Aave V3 treats stETH specially](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) by wrapping to wstETH, [Curve has dedicated pools for rebasing tokens](https://curve.fi/#/ethereum/pools/steth/deposit) with special accounting.

**4. Approval race condition**

If Alice has approved 100 tokens to a spender, and then calls `approve(200)`, the spender can front-run to spend the original 100, then spend the new 200, getting 300 total.

**Solutions:**
- USDT's brute-force: "approve to zero first" requirement
- Better: use `increaseAllowance`/`decreaseAllowance` (removed from OZ v5 core but still available in extensions)
- Best: use [Permit (EIP-2612)](https://eips.ethereum.org/EIPS/eip-2612) or [Permit2](https://github.com/Uniswap/permit2) (covered in Part 1 Section 3)

> **Common pitfall:** Calling `approve(newAmount)` directly without first checking if existing approval is non-zero. With USDT, this reverts. Use `forceApprove` which handles the zero-first pattern automatically.

**5. Tokens that revert on zero transfer**

[LEND](https://etherscan.io/token/0x80fB784B7eD66730e8b1DBd9820aFD29931aab03) and others revert when transferring 0 tokens. Your protocol logic needs to guard against this:

```solidity
if (amount > 0) {
    token.safeTransfer(to, amount);
}
```

> **Common pitfall:** Batch operations that might include zero amounts (e.g., claiming rewards when no rewards are due). Always guard against zero transfers when supporting arbitrary tokens.

**6. Tokens with multiple entry points**

Some proxied tokens have multiple addresses pointing to the same contract. Don't use `address(token)` as a unique identifier without care.

> **Used by:** [Aave V3 uses internal assetId mappings](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) rather than relying solely on token addresses.

---

### Read: WETH

**Source:** The canonical [WETH9 contract](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) (deployed December 2017)

**Why this matters:** WETH exists because ETH doesn't conform to ERC-20. Protocols that want to treat ETH uniformly with other tokens use WETH. The contract is trivially simple:

- `deposit()` (payable): accepts ETH, mints equivalent WETH (1:1)
- `withdraw(uint256 wad)`: burns WETH, sends ETH back

Understand that many protocols ([Uniswap](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L18), [Aave](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/WETHGateway.sol), etc.) have dual paths — one for ETH (wraps to WETH internally) and one for ERC-20 tokens.

**When you build your own protocols, you'll face the same design choice:**
- Support raw ETH: better UX (users don't need to wrap), but requires separate code paths and careful handling of `msg.value`
- Require WETH: simpler code (single ERC-20 path), but users must wrap ETH themselves

> **Used by:** [Uniswap V2 Router](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol) has `swapExactETHForTokens` (wraps ETH → WETH internally), [Aave WETHGateway](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/WETHGateway.sol) wraps/unwraps for users, [Uniswap V4 dropped native ETH support](https://github.com/Uniswap/v4-core) and requires WETH for simplicity.

> **Deep dive:** [WETH9 source code](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) — only 60 lines. Read it.

---

### Build: Token Interaction Test Suite (Foundry)

Create a Foundry project that tests your understanding of these patterns:

```bash
forge init token-mechanics
cd token-mechanics
forge install OpenZeppelin/openzeppelin-contracts
```

**Exercise 1: Build a simple `Vault` contract** that accepts ERC-20 deposits and tracks balances. Requirements:
- Uses [SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) for all token interactions
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

**Foundry tip:** Use `vm.mockCall` or write mock token contracts to simulate weird behaviors. For fee-on-transfer, write a simple ERC-20 that overrides `_update()` to burn 3% on every transfer:

```solidity
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_BPS = 300; // 3%

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            // Burn 3% on transfers (not mints/burns)
            uint256 fee = (amount * FEE_BPS) / 10000;
            super._update(from, address(0), fee); // burn fee
            super._update(from, to, amount - fee); // transfer remainder
        } else {
            super._update(from, to, amount);
        }
    }
}
```

> **Common pitfall:** Testing only with standard ERC-20 mocks. Your vault will pass all tests but fail in production when encountering USDT or fee-on-transfer tokens. Always test with weird token mocks.

---

## Practice Challenges

After completing this module, try these challenges to test your understanding:

- **Damn Vulnerable DeFi #15 — "ABI Smuggling":** Explores token approval patterns and how calldata can be manipulated to bypass access controls on token operations. [Challenge link](https://www.damnvulnerabledefi.xyz/)

---

## Key Takeaways for Protocol Development

After completing this module, you should have internalized these patterns:

**1. Always use SafeERC20** — there is no reason not to. The gas overhead is negligible compared to the risk of silent failures.

```solidity
// ❌ BAD: Breaks on USDT
require(token.transfer(to, amount));

// ✅ GOOD: Works on all tokens
token.safeTransfer(to, amount);
```

**2. Balance-before-after for untrusted tokens** — if your protocol accepts arbitrary tokens, never trust `amount` parameters. Measure what you actually received.

```solidity
// ✅ GOOD: Handles fee-on-transfer tokens
uint256 balanceBefore = token.balanceOf(address(this));
token.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - balanceBefore;
shares = convertToShares(received); // Use received, not amount
```

**3. Design for weird tokens** — decide early whether your protocol supports arbitrary tokens (more complex) or a curated allowlist (simpler, safer). Most serious protocols do both: a permissionless mode with full safety checks, and an optimized path for known-good tokens.

> **Examples:** [Aave V3 has an asset listing process](https://docs.aave.com/developers/v/2.0/guides/asset-listing) (curated allowlist), [Uniswap V3 is permissionless](https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/the-full-contract) (but warns about weird tokens), [Yearn V3 vaults](https://docs.yearn.fi/developers/v3/overview) handle fee-on-transfer explicitly.

---

## Resources

**Reference implementations:**
- [OpenZeppelin ERC20 (v5.x)](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/token/ERC20)
- [Weird ERC-20 catalog](https://github.com/d-xo/weird-erc20)
- [WETH9 source](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) (Etherscan verified)

**Specifications:**
- [EIP-20 (ERC-20)](https://eips.ethereum.org/EIPS/eip-20)
- [EIP-2612 (Permit)](https://eips.ethereum.org/EIPS/eip-2612)

**Production examples:**
- [Uniswap V2 Pair.sol](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) — balance-before-after pattern in `swap()`
- [Aave V3 Pool.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) — SafeERC20 usage, wstETH wrapping
- [Compound V3 Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) — allowlist approach with SafeERC20

**Security reading:**
- [MixBytes — DeFi patterns: ERC20 token transfers](https://mixbytes.io/blog/defi-patterns-erc20-token-transfers-howto)
- [Integrating arbitrary ERC-20 tokens (cheat sheet)](https://andrej.hashnode.dev/integrating-arbitrary-erc-20-tokens)
- [Hundred Finance postmortem](https://rekt.news/hundred-rekt/) — ERC-777 reentrancy ($7M)
- [SushiSwap MISO incident](https://www.coindesk.com/tech/2021/09/17/3m-in-ether-stolen-from-sushiswap-token-launchpad/) — malicious token ($3M)

---

*Next module: AMMs from First Principles — constant product formula, building a minimal swap pool, Uniswap V2→V3→V4 progression.*
