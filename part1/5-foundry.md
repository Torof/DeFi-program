# Section 5: Foundry Workflow & Testing (~2-3 days)

## 📚 Table of Contents

**Day 11: Foundry Essentials**
- [Why Foundry](#why-foundry)
- [Setup](#setup)
- [Core Cheatcodes for DeFi Testing](#core-cheatcodes)
- [Configuration](#configuration)
- [Day 11 Build Exercise](#day11-exercise)

**Day 12: Fuzz Testing and Invariant Testing**
- [Fuzz Testing](#fuzz-testing)
- [Invariant Testing](#invariant-testing)
- [Day 12 Build Exercise](#day12-exercise)

**Day 13: Fork Testing and Gas Optimization**
- [Fork Testing for DeFi](#fork-testing)
- [Gas Optimization Workflow](#gas-optimization)
- [Foundry Scripts for Deployment](#foundry-scripts)
- [Day 13 Build Exercise](#day13-exercise)

---

## Day 11: Foundry Essentials for DeFi Development

<a id="why-foundry"></a>
### 💡 Concept: Why Foundry

**Why this matters:** Every production DeFi protocol launched after 2023 uses Foundry. Uniswap V4, Aave V3, MakerDAO's new contracts—all built and tested with Foundry. If you want to contribute to or understand modern DeFi codebases, Foundry fluency is mandatory, not optional.

> Created by [Paradigm](https://www.paradigm.xyz/), now the de facto standard for Solidity development. [Foundry Book](https://book.getfoundry.sh/)

**📊 Why it replaced Hardhat:**

| Feature | Foundry | Hardhat |
|---------|---------|---------|
| **Test language** | Solidity (same as contracts) ✨ | JavaScript (context switching) |
| **Fuzzing** | Built-in, powerful | Requires external tools |
| **Fork testing** | Seamless, fast | Slower, more setup |
| **Gas snapshots** | `forge snapshot` built-in | Manual tracking |
| **Speed** | Rust-based, parallelized | Node.js-based |
| **EVM cheatcodes** | `vm.prank`, `vm.deal`, etc. | Limited |

If you've used Hardhat, the key mental shift: **everything happens in Solidity**. Your tests, your deployment scripts, your interactions—all Solidity.

> 🔍 **Deep dive:** Read the [Foundry Book - Projects](https://book.getfoundry.sh/projects/creating-a-new-project) section to understand the full project structure and how git submodules work for dependencies.

#### 🔗 DeFi Pattern Connection

**Where Foundry dominates in DeFi:**

1. **Protocol Development** — Every major protocol launched since 2023 uses Foundry:
   - [Uniswap V4](https://github.com/Uniswap/v4-core) — 1000+ tests, invariant suites, gas snapshots
   - [Aave V3](https://github.com/aave/aave-v3-core) — Fork tests against live markets, invariant testing
   - [Morpho Blue](https://github.com/morpho-org/morpho-blue) — Formal verification + Foundry fuzz testing
   - [Euler V2](https://github.com/euler-xyz/euler-vault-kit) — Modular vault architecture tested entirely in Foundry

2. **Security Auditing** — Top audit firms require Foundry fluency:
   - **Trail of Bits** — Uses Foundry + Echidna for invariant testing
   - **Spearbit** — All audit PoCs written in Foundry
   - **Cantina** — Competition PoCs must be Foundry-based
   - Exploit reproduction: Every post-mortem includes a Foundry PoC

3. **On-chain Testing & Simulation** — Fork testing is the standard for:
   - Governance proposal simulation (Compound, MakerDAO)
   - Liquidation bot testing against live oracle prices
   - MEV strategy backtesting against historical blocks

**The pattern:** If you're building, auditing, or researching DeFi — Foundry is the language you speak.

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"What testing framework do you use?"**
   - Good answer: "Foundry — I write Solidity tests with fuzz and invariant testing"
   - Great answer: "Foundry for everything — unit tests, fuzz tests, invariant suites with handlers, fork tests against mainnet, and gas snapshots in CI. I use Hardhat only when I need JavaScript integration tests for frontend"

2. **"How do you test DeFi composability?"**
   - Good answer: "Fork testing against mainnet"
   - Great answer: "I pin fork tests to specific blocks for determinism, test against multiple market conditions, and use `deal()` instead of impersonating whales. For critical paths, I test against both mainnet and L2 forks"

**🚩 Interview Red Flags:**
- 🚩 Only knowing Hardhat/JavaScript testing in 2025+
- 🚩 Not understanding `vm.prank` vs `vm.startPrank` semantics
- 🚩 No experience with fuzz or invariant testing

**Pro tip:** When applying for DeFi roles, having a GitHub repo with well-written Foundry tests (fuzz + invariant + fork) is worth more than most take-home assignments. It demonstrates real protocol development experience.

---

<a id="setup"></a>
### 🏗️ Setup

```bash
# Install/update Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Create a new project
forge init my-project
cd my-project

# Project structure
# src/         — contract source files
# test/        — test files (*.t.sol)
# script/      — deployment/interaction scripts (*.s.sol)
# lib/         — dependencies (git submodules)
# foundry.toml — configuration

# Install OpenZeppelin
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Add remappings (tells compiler where to find imports)
echo '@openzeppelin/=lib/openzeppelin-contracts/' >> remappings.txt
```

---

<a id="core-cheatcodes"></a>
### 💡 Concept: Core Foundry Cheatcodes for DeFi Testing

**Why this matters:** Cheatcodes let you manipulate the EVM state (time, balances, msg.sender) in ways impossible on a real chain. This is how you test time-locked vaults, simulate whale swaps, and verify liquidation logic.

**The cheatcodes you'll use constantly:**

```solidity
// ✅ Impersonate an address (critical for fork testing)
vm.prank(someAddress);
someContract.doSomething(); // msg.sender == someAddress (for one call)

// ✅ Persistent impersonation
vm.startPrank(someAddress);
// ... multiple calls as someAddress
vm.stopPrank();

// ✅ Set block timestamp (essential for time-dependent DeFi logic)
vm.warp(block.timestamp + 1 days);

// ✅ Set block number
vm.roll(block.number + 100);

// ✅ Deal ETH or tokens to an address
deal(address(token), user, 1000e18);  // Give user 1000 tokens
deal(user, 100 ether);                // Give user 100 ETH

// ✅ Expect a revert with specific error
vm.expectRevert(CustomError.selector);
vm.expectRevert(abi.encodeWithSelector(CustomError.selector, arg1, arg2));

// ✅ Expect event emission (all 4 booleans: indexed1, indexed2, indexed3, data)
vm.expectEmit(true, true, false, true);
emit ExpectedEvent(indexed1, indexed2, data);
someContract.doSomething();  // Must emit the event

// ✅ Create labeled addresses (shows up in traces as "alice" not 0x...)
address alice = makeAddr("alice");
(address bob, uint256 bobKey) = makeAddrAndKey("bob");

// ✅ Sign messages (for EIP-712, permit, etc.)
(uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

// ✅ Snapshot and revert state (useful for testing multiple scenarios)
uint256 snapshot = vm.snapshot();
// ... modify state ...
vm.revertTo(snapshot);  // Back to snapshot state
```

> ⚡ **Common pitfall:** `vm.prank` only affects the **next** call. If you need multiple calls, use `vm.startPrank`/`vm.stopPrank`. Forgetting this leads to "hey why is msg.sender wrong?" debugging sessions.

💻 **Quick Try:**

Create a file `test/CheatcodePlayground.t.sol` and run it:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";

contract CheatcodePlayground is Test {
    function test_TimeTravel() public {
        uint256 now_ = block.timestamp;
        vm.warp(now_ + 365 days);
        assertEq(block.timestamp, now_ + 365 days);
        // You just jumped one year into the future!
    }

    function test_Impersonation() public {
        address vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        deal(vitalik, 1000 ether);
        vm.prank(vitalik);
        // Next call's msg.sender is Vitalik
        (bool ok,) = address(this).call{value: 1 ether}("");
        assertTrue(ok);
    }

    receive() external payable {}
}
```

Run with `forge test --match-contract CheatcodePlayground -vvv` and watch the traces. Feel how cheatcodes manipulate the EVM.

#### 🔗 DeFi Pattern Connection

**Where cheatcodes are essential in DeFi testing:**

1. **Time-dependent logic** (`vm.warp`):
   - Vault lock periods and vesting schedules
   - Oracle staleness checks (← Section 5 Day 13)
   - Interest accrual in lending protocols (→ Part 2 Module 3)
   - Governance timelocks and voting periods

2. **Access control testing** (`vm.prank`):
   - Testing admin-only functions (pause, upgrade, fee changes)
   - Simulating multi-sig signers
   - Testing permit/signature flows with `vm.sign` (← Section 3)
   - Account abstraction validation with `vm.prank(entryPoint)` (← Section 4)

3. **State manipulation** (`deal`):
   - Funding test accounts with exact token amounts
   - Simulating whale positions for liquidation testing
   - Setting up pool reserves for AMM testing (→ Part 2 Module 2)

4. **Event verification** (`vm.expectEmit`):
   - Verifying Transfer/Approval events for token standards
   - Checking protocol-specific events (Deposit, Withdraw, Swap)
   - Critical for integration testing: "did the downstream protocol emit the right event?"

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"Walk me through how you'd test a time-locked vault"**
   - Good answer: "Use `vm.warp` to advance past the lock period, test both before and after"
   - Great answer: "I'd test at key boundaries — 1 second before unlock, exact unlock time, and after. I'd also fuzz the lock duration and test with `vm.roll` for block-number-based locks. For production, I'd add invariant tests ensuring no withdrawals are possible before the lock expires across random deposit/warp/withdraw sequences"

2. **"How do you test signature-based flows?"**
   - Good answer: "Use `makeAddrAndKey` to create signers, then `vm.sign` for EIP-712 digests"
   - Great answer: "I create deterministic test signers with `makeAddrAndKey`, construct EIP-712 typed data hashes matching the contract's `DOMAIN_SEPARATOR`, sign with `vm.sign`, and test both valid signatures and invalid ones (wrong signer, expired deadline, replayed nonce). For EIP-1271, I test both EOA and contract signers"

**🚩 Interview Red Flags:**
- 🚩 Using `vm.assume` instead of `bound()` for constraining fuzz inputs
- 🚩 Not knowing `vm.expectRevert` with custom error selectors (Section 1 pattern)
- 🚩 Hardcoding block.timestamp instead of using `vm.warp` for time-dependent tests

**🏗️ Real usage:**

[Uniswap V4 test suite](https://github.com/Uniswap/v4-core/tree/main/test) extensively uses these cheatcodes. Read any test file to see production patterns.

---

<a id="configuration"></a>
### 🏗️ Configuration (foundry.toml)

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.28"                 # Latest stable
evm_version = "cancun"          # or "prague" for Pectra features
optimizer = true
optimizer_runs = 200            # Balance deployment cost vs runtime cost
via_ir = false                  # Enable for Permit2 integration (slower compile)

[profile.default.fuzz]
runs = 256                      # Increase for production: 10000+
max_test_rejects = 65536        # How many invalid inputs before giving up

[profile.default.invariant]
runs = 256                      # Number of random call sequences
depth = 15                      # Max calls per sequence
fail_on_revert = false          # Don't fail just because a call reverts

[rpc_endpoints]
mainnet = "${MAINNET_RPC_URL}"
arbitrum = "${ARBITRUM_RPC_URL}"
optimism = "${OPTIMISM_RPC_URL}"

[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }
```

> 🔍 **Deep dive:** [Foundry Book - Configuration](https://book.getfoundry.sh/reference/config/) has all available options.

---

<a id="day11-exercise"></a>
## 🎯 Day 11 Build Exercise

**Workspace:** [`workspace/test/part1/section5/`](../workspace/test/part1/section5/) — base setup: [`BaseTest.sol`](../workspace/test/part1/section5/BaseTest.sol), fork tests: [`UniswapV2Fork.t.sol`](../workspace/test/part1/section5/UniswapV2Fork.t.sol), [`ChainlinkFork.t.sol`](../workspace/test/part1/section5/ChainlinkFork.t.sol)

Set up the project structure you'll use throughout Part 2:

1. **Initialize a Foundry project** with OpenZeppelin and Permit2 as dependencies:
   ```bash
   forge init defi-protocol
   cd defi-protocol
   forge install OpenZeppelin/openzeppelin-contracts --no-commit
   forge install Uniswap/permit2 --no-commit
   ```

2. **Create a base test contract** (`BaseTest.sol`) with common setup:
   ```solidity
   // test/BaseTest.sol
   import "forge-std/Test.sol";

   abstract contract BaseTest is Test {
       // Mainnet addresses (save typing in every test)
       address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
       address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
       address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
       address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

       // Test users with private keys (for signing)
       address alice;
       uint256 aliceKey;
       address bob;
       uint256 bobKey;

       function setUp() public virtual {
           // Fork mainnet
           vm.createSelectFork("mainnet");

           // Create test users
           (alice, aliceKey) = makeAddrAndKey("alice");
           (bob, bobKey) = makeAddrAndKey("bob");

           // Fund them with ETH
           deal(alice, 100 ether);
           deal(bob, 100 ether);
       }
   }
   ```

3. **Write a simple fork test** that interacts with Uniswap V2 on mainnet:
   ```solidity
   contract UniswapV2ForkTest is BaseTest {
       IUniswapV2Pair constant WETH_USDC_PAIR =
           IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

       function testGetReserves() public view {
           (uint112 reserve0, uint112 reserve1,) = WETH_USDC_PAIR.getReserves();
           assertGt(reserve0, 0);
           assertGt(reserve1, 0);
       }
   }
   ```

4. **Write a fork test** that reads Chainlink price feed data:
   ```solidity
   contract ChainlinkForkTest is BaseTest {
       AggregatorV3Interface constant ETH_USD_FEED =
           AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

       function testPriceFeed() public view {
           (,int256 price,,,uint256 updatedAt) = ETH_USD_FEED.latestRoundData();
           assertGt(price, 0);
           assertLt(block.timestamp - updatedAt, 1 hours); // Not stale
       }
   }
   ```

**🎯 Goal:** Have a battle-ready test harness before you start Part 2. The BaseTest pattern saves you from rewriting setup in every test file.

---

## 📋 Day 11 Summary

**✓ Covered:**
- Why Foundry — Solidity tests, built-in fuzzing, fast execution
- Project setup — dependencies, remappings, configuration
- Core cheatcodes — `vm.prank`, `vm.warp`, `deal`, `vm.expectRevert`, `vm.sign`
- BaseTest pattern — reusable test setup for fork testing

**Next:** Day 12 — Fuzz testing and invariant testing for DeFi

---

## Day 12: Fuzz Testing and Invariant Testing

<a id="fuzz-testing"></a>
### 💡 Concept: Fuzz Testing

**Why this matters:** Manual unit tests check specific cases. Fuzz tests check properties across **all possible inputs**. The [Euler Finance hack](https://www.certik.com/resources/blog/euler-finance-hack-explained) ($197M) would have been caught by a simple fuzz test checking "can liquidate with 0 collateral?"

**How it works:**

Fuzz testing generates random inputs for your test functions. Instead of testing specific cases, you define properties that should hold for ALL valid inputs, and the fuzzer tries to break them.

```solidity
// ❌ Unit test: specific case
function testSwapExact() public {
    uint256 amountOut = pool.getAmountOut(1e18, reserveIn, reserveOut);
    assertGt(amountOut, 0);
}

// ✅ Fuzz test: property for ALL inputs
function testFuzz_SwapAlwaysPositive(uint256 amountIn) public {
    amountIn = bound(amountIn, 1, type(uint112).max); // Constrain to valid range
    uint256 amountOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
    assertGt(amountOut, 0);
}
```

**The `bound()` helper:**

`bound(value, min, max)` is your main tool for constraining fuzz inputs to valid ranges without skipping too many random values (which would trigger `max_test_rejects` and fail your test).

```solidity
// ❌ BAD: discards most inputs
function testBad(uint256 amount) public {
    vm.assume(amount > 0 && amount < 1000e18);  // Rejects 99.99% of inputs
    // ...
}

// ✅ GOOD: transforms inputs to valid range
function testGood(uint256 amount) public {
    amount = bound(amount, 1, 1000e18);  // Maps all inputs to [1, 1000e18]
    // ...
}
```

> 🔍 **Deep dive:** Read [Foundry Book - Fuzz Testing](https://book.getfoundry.sh/forge/fuzz-testing) for advanced techniques like stateful fuzzing. [Cyfrin - Fuzz and Invariant Tests Full Explainer](https://www.cyfrin.io/blog/fuzz-invariant-tests) provides comprehensive coverage with DeFi examples.

**Best practices for DeFi fuzz testing:**

- ✅ **Use `bound()`** to constrain inputs to realistic ranges (token amounts, timestamps, interest rates)
- ✅ **Test mathematical properties**: swap output ≤ reserve, interest ≥ 0, shares ≤ total supply
- ✅ **Test edge cases explicitly**: zero amounts, maximum values, minimum values
- ⚠️ **Use `vm.assume()` sparingly**—it discards inputs, `bound()` transforms them

---

<a id="invariant-testing"></a>
### 💡 Concept: Invariant Testing

**Why this matters:** Invariant testing found the critical bugs in [Vyper reentrancy vulnerability](https://hackmd.io/@LlamaRisk/BJzSKHNjn) (July 2023, $70M+ at risk). Fuzz tests check individual functions. Invariant tests check system-wide properties across **arbitrary sequences of operations**.

**How it works:**

Instead of testing individual functions, you define **system-wide invariants**—properties that must ALWAYS be true regardless of any sequence of operations—and the fuzzer generates random sequences of calls trying to violate them.

**The Handler Pattern (Essential):**

Without a handler, the fuzzer calls your contract with completely random calldata, which almost always reverts (wrong function selectors, invalid parameters). Handlers constrain the fuzzer to valid operation sequences while still exploring random states.

```solidity
// Target contract: the system under test
// Handler: constrains how the fuzzer interacts with the system

contract VaultHandler is Test {
    Vault public vault;
    MockToken public token;

    // Ghost variables: track cumulative state for invariants
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    constructor(Vault _vault, MockToken _token) {
        vault = _vault;
        token = _token;
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(address(this)));
        token.approve(address(vault), amount);
        vault.deposit(amount);

        ghost_depositSum += amount;  // Track total deposits
    }

    function withdraw(uint256 shares) public {
        shares = bound(shares, 1, vault.balanceOf(address(this)));
        uint256 assets = vault.withdraw(shares);

        ghost_withdrawSum += assets;  // Track total withdrawals
    }
}

contract VaultInvariantTest is Test {
    Vault vault;
    MockToken token;
    VaultHandler handler;

    function setUp() public {
        token = new MockToken();
        vault = new Vault(token);
        handler = new VaultHandler(vault, token);

        // Fund the handler
        token.mint(address(handler), 1_000_000e18);

        // Tell Foundry which contract to call randomly
        targetContract(address(handler));
    }

    // ✅ This must ALWAYS be true, no matter what sequence of deposits/withdrawals
    function invariant_totalAssetsMatchBalance() public view {
        assertEq(
            vault.totalAssets(),
            token.balanceOf(address(vault)),
            "Vault accounting broken"
        );
    }

    function invariant_solvency() public view {
        // Vault must have enough tokens to cover all shares
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 sharesValue = vault.convertToAssets(totalShares);

        assertGe(totalAssets, sharesValue, "Vault insolvent");
    }

    function invariant_conservation() public view {
        // Total deposited - total withdrawn ≤ vault balance (accounting for rounding)
        uint256 netDeposits = handler.ghost_depositSum() - handler.ghost_withdrawSum();
        uint256 vaultBalance = token.balanceOf(address(vault));

        assertApproxEqAbs(vaultBalance, netDeposits, 10, "Value leaked");
    }
}
```

**📊 Key invariant testing patterns for DeFi:**

1. **Conservation invariants:** Total assets in ≥ total assets out (accounting for fees)
2. **Solvency invariants:** Contract balance ≥ sum of user claims
3. **Monotonicity invariants:** Share price never decreases (for non-rebasing vaults)
4. **Supply invariants:** Sum of user balances == total supply

> ⚡ **Common pitfall:** Setting `fail_on_revert = true` (the old default). Many valid operations revert (withdraw with 0 balance, swap with 0 input). Set it to `false` and only care about invariant violations, not individual reverts.

**🏗️ Real usage:**

[Aave V3 invariant tests](https://github.com/aave/aave-v3-core/tree/master/test-suites/invariants) are the gold standard. Study their handler patterns and ghost variable usage.

> 🔍 **Deep dive:** [Cyfrin - Invariant Testing: Enter The Matrix](https://medium.com/cyfrin/invariant-testing-enter-the-matrix-c71363dea37e) explains advanced handler patterns. [RareSkills - Invariant Testing in Solidity](https://rareskills.io/post/invariant-testing-solidity) covers ghost variables and metrics. [Cyfrin Updraft - Handler Tutorial](https://updraft.cyfrin.io/courses/advanced-foundry/develop-defi-protocol/create-fuzz-tests-handler) provides step-by-step handler implementation.

#### 🔍 Deep Dive: Advanced Invariant Patterns

Beyond the basic handler pattern, production protocols use several advanced techniques:

**1. Multi-Actor Handlers**

Real DeFi protocols have many users interacting simultaneously. A single-actor handler misses concurrency bugs:

```solidity
contract MultiActorHandler is Test {
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function deposit(uint256 amount, uint256 actorSeed) public useActor(actorSeed) {
        amount = bound(amount, 1, token.balanceOf(currentActor));
        // ... deposit as random actor
    }
}
```

**Why this matters:** The [Euler Finance hack](https://www.certik.com/resources/blog/euler-finance-hack-explained) involved multiple actors interacting in a specific sequence. Single-actor invariant tests wouldn't have caught it.

**2. Time-Weighted Invariants**

Many DeFi invariants only hold after time passes (interest accrual, oracle updates):

```solidity
function handler_advanceTime(uint256 timeSkip) public {
    timeSkip = bound(timeSkip, 1, 7 days);
    vm.warp(block.timestamp + timeSkip);

    ghost_timeAdvanced += timeSkip;
}

// Invariant: interest only increases over time
function invariant_interestMonotonicity() public view {
    assertGe(pool.totalDebt(), ghost_previousDebt, "Debt decreased without repayment");
}
```

**3. Ghost Variable Accounting**

Track what *should* be true alongside what *is* true:

```
┌─────────────────────────────────────────┐
│         Ghost Variable Pattern          │
│                                         │
│  Handler tracks:                        │
│  ├── ghost_totalDeposited  (cumulative) │
│  ├── ghost_totalWithdrawn  (cumulative) │
│  ├── ghost_userDeposits[user] (per-user)│
│  └── ghost_callCount       (metrics)    │
│                                         │
│  Invariant checks:                      │
│  ├── vault.balance == deposits - withdrawals  │
│  ├── Σ userDeposits == ghost_totalDeposited   │
│  └── vault.totalShares >= 0                    │
└─────────────────────────────────────────┘
```

Ghost variables are your **parallel accounting system** — if the contract's state diverges from your ghost tracking, you've found a bug.

#### 🔗 DeFi Pattern Connection

**Where fuzz and invariant testing catch real bugs:**

1. **AMM Invariants** (→ Part 2 Module 2):
   - `x * y >= k` after every swap (constant product)
   - No tokens can be extracted without providing the other side
   - LP share value never decreases from swaps (fees accumulate)

2. **Lending Protocol Invariants** (→ Part 2 Module 3):
   - Total borrows ≤ total supplied (solvency)
   - Health factor < 1 → liquidatable (always)
   - Interest index only increases (monotonicity)

3. **Vault Invariants** (→ Part 2 Module 4):
   - `convertToShares(convertToAssets(shares)) <= shares` (no free shares — rounding in protocol's favor)
   - Total assets ≥ sum of all redeemable assets (solvency)
   - First depositor can't steal from subsequent depositors (inflation attack)

4. **Governance Invariants**:
   - Vote count ≤ total delegated power
   - Executed proposals can't be re-executed
   - Timelock delay is always enforced

**The pattern:** For every DeFi protocol, ask "what must ALWAYS be true?" — those are your invariants.

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"How do you approach testing a new DeFi protocol?"**
   - Good answer: "Unit tests for individual functions, fuzz tests for properties, invariant tests for system-wide correctness"
   - Great answer: "I start by identifying the protocol's invariants — solvency, conservation of value, monotonicity of share price. Then I build handlers that simulate realistic user behavior (deposits, withdrawals, swaps, liquidations), use ghost variables to track expected state, and run invariant tests with high depth. I also write targeted fuzz tests for mathematical edge cases like rounding and overflow boundaries"

2. **"What's the difference between fuzz testing and invariant testing?"**
   - Good answer: "Fuzz tests random inputs to one function, invariant tests random sequences of calls"
   - Great answer: "Fuzz testing verifies properties of individual functions across all inputs — like 'swap output is always positive for positive input.' Invariant testing verifies system-wide properties across arbitrary call sequences — like 'the pool is always solvent regardless of what operations happened.' The key insight is that bugs often emerge from *sequences* of valid operations, not from any single call"

3. **"Have you ever found a bug with fuzz/invariant testing?"**
   - This is increasingly common in DeFi interviews. Having a real example (even from your own learning exercises) is powerful

**🚩 Interview Red Flags:**
- 🚩 Only writing unit tests with hardcoded values (no fuzzing)
- 🚩 Not knowing the handler pattern for invariant testing
- 🚩 Using `fail_on_revert = true` (shows lack of invariant testing experience)
- 🚩 Can't articulate what invariants a vault or AMM should have

**Pro tip:** The #1 skill that separates junior from senior DeFi developers is the ability to identify and test protocol invariants. If you can articulate "these 5 things must always be true about this protocol" and write tests proving it, you're already ahead of most candidates.

---

<a id="day12-exercise"></a>
## 🎯 Day 12 Build Exercise

**Workspace:** [`workspace/src/part1/section5/`](../workspace/src/part1/section5/) — vault: [`SimpleVault.sol`](../workspace/src/part1/section5/SimpleVault.sol), tests: [`SimpleVault.t.sol`](../workspace/test/part1/section5/SimpleVault.t.sol), handler: [`VaultHandler.sol`](../workspace/test/part1/section5/VaultHandler.sol), invariants: [`VaultInvariant.t.sol`](../workspace/test/part1/section5/VaultInvariant.t.sol)

1. **Build a simple vault** (accepts one ERC-20 token, issues shares proportional to deposit size):
   ```solidity
   contract Vault is ERC20 {
       IERC20 public immutable token;

       function deposit(uint256 assets) external returns (uint256 shares) {
           shares = convertToShares(assets);
           token.transferFrom(msg.sender, address(this), assets);
           _mint(msg.sender, shares);
       }

       function withdraw(uint256 shares) external returns (uint256 assets) {
           assets = convertToAssets(shares);
           _burn(msg.sender, shares);
           token.transfer(msg.sender, assets);
       }

       function convertToShares(uint256 assets) public view returns (uint256) {
           uint256 supply = totalSupply();
           return supply == 0 ? assets : (assets * supply) / totalAssets();
       }

       function convertToAssets(uint256 shares) public view returns (uint256) {
           uint256 supply = totalSupply();
           return supply == 0 ? shares : (shares * totalAssets()) / supply;
       }

       function totalAssets() public view returns (uint256) {
           return token.balanceOf(address(this));
       }
   }
   ```

2. **Write fuzz tests** for the deposit and withdraw functions individually:
   ```solidity
   function testFuzz_Deposit(uint256 amount) public {
       amount = bound(amount, 1, 1000000e18);
       deal(address(token), alice, amount);

       vm.startPrank(alice);
       token.approve(address(vault), amount);
       vault.deposit(amount);
       vm.stopPrank();

       assertEq(vault.balanceOf(alice), vault.convertToShares(amount));
   }
   ```

3. **Write a Handler contract and invariant tests** for the vault:
   - `invariant_solvency`: vault token balance ≥ what all shareholders could withdraw
   - `invariant_supplyConsistency`: sum of all share balances == totalSupply
   - `invariant_noFreeMoney`: total withdrawals ≤ total deposits

4. **Run with high iterations** and see if the fuzzer finds any violations:
   ```bash
   forge test --match-test invariant -vvv
   ```

5. **Intentionally break an invariant** (e.g., remove `_burn` from withdraw) and verify the fuzzer catches it

**🎯 Goal:** Invariant testing is how real DeFi auditors find bugs. Getting comfortable with the handler pattern now pays off enormously in Part 2 when you're testing AMMs, lending pools, and CDPs.

---

## 📋 Day 12 Summary

**✓ Covered:**
- Fuzz testing — property-based testing for all inputs
- `bound()` helper — constraining inputs without rejecting them
- Invariant testing — system-wide properties across call sequences
- Handler pattern — constraining fuzzer to valid operations
- Ghost variables — tracking cumulative state for invariants

**Next:** Day 13 — Fork testing and gas optimization

---

### 📖 How to Study Production Test Suites

Production DeFi test suites can be overwhelming (Uniswap V4 has 100+ test files). Here's a strategy:

**Step 1: Start with the simplest test file**
Find a basic unit test (not invariant or fork). In Uniswap V4, start with `test/PoolManager.t.sol` basic swap tests, not the complex hook tests.

**Step 2: Read the base test contract**
Every production suite has a `BaseTest` or `TestHelper`. This shows:
- How they set up fork state
- What helper functions they use
- How they create test users and fund them
- Common assertions they reuse

**Step 3: Study the handler contracts**
Handlers reveal what the team considers "valid operations." Look at:
- Which functions are exposed (the attack surface)
- How inputs are bounded (what ranges are realistic)
- What ghost variables they track (what they think can go wrong)

**Step 4: Read the invariant definitions**
These are the protocol's core properties in code form:
```
Uniswap V4: "Pool reserves satisfy x*y >= k after every swap"
Aave V3:    "Total borrows never exceed total deposits"
Morpho:     "Sum of all user balances equals contract balance"
```

**Step 5: Look for edge case tests**
Search for tests with names like `test_RevertWhen_*`, `test_EdgeCase_*`, `testFuzz_*`. These reveal the bugs the team found and patched.

**Don't get stuck on:** Complex multi-contract integration tests or deployment scripts initially. Build up to those after understanding the unit and fuzz tests.

**Recommended study order:**
1. [Solmate tests](https://github.com/transmissions11/solmate/tree/main/src/test) — Clean, minimal, great for learning patterns
2. [OpenZeppelin tests](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/test) — Comprehensive, well-documented
3. [Uniswap V4 tests](https://github.com/Uniswap/v4-core/tree/main/test) — Production DeFi complexity
4. [Aave V3 invariant tests](https://github.com/aave/aave-v3-core/tree/master/test-suites/invariants) — Gold standard for invariant testing

---

## Day 13: Fork Testing and Gas Optimization

<a id="fork-testing"></a>
### 💡 Concept: Fork Testing for DeFi

**Why this matters:** You can't test DeFi composability in isolation. Your protocol will interact with Uniswap, Chainlink, Aave—you need to test against real deployed contracts with real liquidity. Fork testing makes this trivial.

**What fork testing does:**

Runs your tests against a snapshot of a real network's state. This lets you:
- ✅ **Interact with deployed protocols** (swap on Uniswap, borrow from Aave)
- ✅ **Test with real token balances and oracle prices**
- ✅ **Verify that your protocol composes correctly** with existing DeFi
- ✅ **Reproduce real exploits** on forked state (for security research)

```bash
# Run tests against mainnet fork
forge test --fork-url $MAINNET_RPC_URL

# Pin to a specific block (deterministic results)
forge test --fork-url $MAINNET_RPC_URL --fork-block-number 19000000

# Multiple forks in the same test
uint256 mainnetFork = vm.createFork("mainnet");
uint256 arbitrumFork = vm.createFork("arbitrum");

vm.selectFork(mainnetFork);  // Switch to mainnet
// ... test on mainnet ...

vm.selectFork(arbitrumFork);  // Switch to arbitrum
// ... test on arbitrum ...
```

> 🔍 **Deep dive:** [Foundry Book - Forking](https://book.getfoundry.sh/forge/fork-testing) covers advanced patterns like persisting fork state and cheatcodes.

**Best practices:**

- ✅ **Always pin to a specific block number** for deterministic tests
- ✅ **Use `deal()`** to fund test accounts rather than impersonating whale addresses (which can break if they change)
- ✅ **Cache fork data locally** to avoid rate-limiting your RPC provider: Foundry automatically caches fork state
- ✅ **Test against multiple blocks** to ensure your protocol works across different market conditions

> ⚡ **Common pitfall:** Forgetting to set `MAINNET_RPC_URL` in `.env`. Fork tests will fail with "RPC endpoint not found." Use [Alchemy](https://www.alchemy.com/) or [Infura](https://www.infura.io/) for reliable RPC endpoints.

---

<a id="gas-optimization"></a>
### 💡 Concept: Gas Optimization Workflow

**Why this matters:** Every 100 gas you save is $0.01+ per transaction at 100 gwei. For a protocol processing 100k transactions/day (like Uniswap), that's $1M+/year in user savings. Gas optimization is a competitive advantage.

```bash
# Gas report for all tests
forge test --gas-report

# Example output:
# | Function           | min   | avg    | max    |
# |--------------------|-------|--------|--------|
# | deposit            | 45123 | 50234  | 55345  |
# | withdraw           | 38956 | 42123  | 48234  |

# Gas snapshots — save current gas usage, then compare after optimization
forge snapshot                    # Creates .gas-snapshot
# ... make changes ...
forge snapshot --diff             # Shows increase/decrease

# Specific function gas usage
forge test --match-test testSwap -vvvv  # 4 v's shows gas per opcode
```

**📊 Gas optimization patterns you'll use in Part 2:**

| Pattern | Savings | Example |
|---------|---------|---------|
| **`unchecked` blocks** | ~20 gas/operation | Loop counters |
| **Packing storage variables** | ~15,000 gas/slot saved | `uint128 a; uint128 b;` in one slot |
| **`calldata` vs `memory`** | ~300 gas | Read-only arrays |
| **Custom errors** | ~24 gas/revert | vs `require` strings |
| **Cache storage reads** | ~100 gas/read | Local variable vs storage |

**Examples:**

```solidity
// ✅ 1. unchecked blocks for proven-safe arithmetic
unchecked { ++i; }  // Saves ~20 gas per loop iteration

// ✅ 2. Packing storage variables (multiple values in one slot)
// BAD: 3 storage slots (3 * 20k gas for cold writes)
uint256 a;
uint256 b;
uint256 c;

// GOOD: 1 storage slot if types fit
uint128 a;
uint64 b;
uint64 c;

// ✅ 3. Using calldata instead of memory for read-only function parameters
function process(uint256[] calldata data) external {  // calldata: no copy
    // vs
    // function process(uint256[] memory data) external {  // memory: copies
}

// ✅ 4. Caching storage reads in local variables
// BAD: reads totalSupply from storage 3 times
function bad() public view returns (uint256) {
    return totalSupply + totalSupply + totalSupply;
}

// GOOD: reads once, reuses local variable
function good() public view returns (uint256) {
    uint256 supply = totalSupply;
    return supply + supply + supply;
}
```

> 🔍 **Deep dive:** [Rareskills Gas Optimization Guide](https://www.rareskills.io/post/gas-optimization) is the comprehensive resource. [Alchemy - 12 Solidity Gas Optimization Techniques](https://www.alchemy.com/overviews/solidity-gas-optimization) provides a practical checklist. [Cyfrin - Advanced Gas Optimization Tips](https://www.cyfrin.io/blog/solidity-gas-optimization-tips) covers advanced techniques. [0xMacro - Gas Optimizations Cheat Sheet](https://0xmacro.com/blog/solidity-gas-optimizations-cheat-sheet/) is a quick reference.

---

<a id="foundry-scripts"></a>
### 💡 Concept: Foundry Scripts for Deployment

**Why this matters:** Deployment scripts in Solidity (not JavaScript) mean you can test your deployments before running them on-chain. You can also reuse the same scripts for local testing and production deployment.

```solidity
// script/Deploy.s.sol
import "forge-std/Script.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        MyContract c = new MyContract(constructorArg);

        vm.stopBroadcast();

        console.log("Deployed at:", address(c));
    }
}
```

```bash
# Dry run (simulation)
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# Actual deployment + etherscan verification
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Resume failed broadcast (e.g., if etherscan verification failed)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --resume
```

> ⚡ **Common pitfall:** Forgetting to fund the deployer address with ETH before broadcasting. The script will simulate successfully but fail when you try to broadcast.

---

#### 🎓 Intermediate Example: Differential Testing

Differential testing compares two implementations of the same function to find discrepancies. This is how auditors verify optimized code matches the reference implementation.

```solidity
contract DifferentialTest is Test {
    /// @dev Reference implementation: clear, readable, obviously correct
    function mulDivReference(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return (x * y) / d;  // Overflows for large values!
    }

    /// @dev Optimized implementation: handles full 512-bit intermediate
    function mulDivOptimized(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        // ... (Section 1's FullMath.mulDiv pattern)
        return FullMath.mulDiv(x, y, d);
    }

    /// @dev Fuzz: both implementations agree for non-overflowing inputs
    function testFuzz_MulDivEquivalence(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);

        // Only test where reference won't overflow
        unchecked {
            if (y != 0 && (x * y) / y != x) return; // Would overflow
        }

        assertEq(
            mulDivReference(x, y, d),
            mulDivOptimized(x, y, d),
            "Implementations disagree"
        );
    }
}
```

**Why this matters in DeFi:**
- Verifying gas-optimized swap math matches the readable version
- Comparing your oracle integration against a reference implementation
- Ensuring an upgraded contract produces identical results to the old one

**Production example:** Uniswap V3 uses differential testing to verify their `TickMath` and `SqrtPriceMath` libraries match reference implementations.

#### 🔗 DeFi Pattern Connection

**Where fork testing and gas optimization matter in DeFi:**

1. **Exploit Reproduction & Prevention**:
   - Every major hack post-mortem includes a Foundry fork test PoC
   - Pin to the block *before* the exploit, then replay the attack
   - Example: Reproduce the [Euler hack](https://github.com/iphelix/euler-exploit-v1) by forking at the pre-attack block
   - Security teams run fork tests against their own protocols to find similar vectors

2. **Oracle Integration Testing** (→ Part 2 Module 5):
   - Fork test Chainlink feeds with real price data
   - Test staleness checks: `vm.warp` past the heartbeat interval
   - Simulate oracle manipulation by forking at blocks with extreme prices

3. **Composability Verification**:
   - "Does my vault work when Aave V3 changes interest rates?"
   - "Does my liquidation bot handle Uniswap V3 tick crossing?"
   - Fork both protocols, simulate realistic sequences, verify no breakage

4. **Gas Benchmarking for Protocol Competitiveness**:
   - Uniswap V4 hooks: gas overhead determines viability
   - Lending protocols: gas cost of liquidation determines MEV profitability
   - Aggregators (1inch, Cowswap): route selection depends on gas estimates
   - `forge snapshot --diff` in CI prevents gas regressions

#### 💼 Job Market Context

**What DeFi teams expect:**

1. **"How would you reproduce a DeFi exploit?"**
   - Good answer: "Fork mainnet at the block before the exploit, replay the transactions"
   - Great answer: "I'd fork at `block - 1`, use `vm.prank` to impersonate the attacker, replay the exact call sequence, and verify the stolen amount matches the post-mortem. Then I'd write a test that proves the fix prevents the attack. I keep a library of exploit reproductions — it's the best way to learn DeFi security patterns"

2. **"How do you approach gas optimization?"**
   - Good answer: "Use `forge snapshot` to measure and compare"
   - Great answer: "I establish a baseline with `forge snapshot`, then use `forge test -vvvv` to identify the expensive opcodes. I focus on storage operations first (SLOAD/SSTORE dominate gas costs), then calldata optimizations, then arithmetic. I always run the full invariant suite after optimization to ensure correctness wasn't sacrificed. In CI, I use `forge snapshot --check` to catch regressions"

3. **"Walk me through testing a protocol integration"**
   - Good answer: "Fork test against the deployed protocol"
   - Great answer: "I pin to a specific block for determinism, set up realistic token balances with `deal()`, test the happy path first, then systematically test edge cases — what happens when the external protocol pauses? What happens during extreme market conditions? I test against multiple blocks to catch time-dependent behavior, and I test on both mainnet and relevant L2 forks"

**🚩 Interview Red Flags:**
- 🚩 Never having reproduced an exploit (shows no security awareness)
- 🚩 Optimizing gas without measuring first ("premature optimization")
- 🚩 Not pinning fork tests to specific block numbers (non-deterministic tests)
- 🚩 Not knowing the difference between `forge snapshot` and `forge test --gas-report`

**Pro tip:** Maintain a personal repository of exploit reproductions as Foundry fork tests. It's the most effective way to learn DeFi security, and it's impressive in interviews. Start with [DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) — they have 200+ reproductions.

---

<a id="day13-exercise"></a>
## 🎯 Day 13 Build Exercise

**Workspace:** [`workspace/test/part1/section5/`](../workspace/test/part1/section5/) — fork tests: [`UniswapSwapFork.t.sol`](../workspace/test/part1/section5/UniswapSwapFork.t.sol), gas optimization: [`GasOptimization.sol`](../workspace/src/part1/section5/GasOptimization.sol) and [`GasOptimization.t.sol`](../workspace/test/part1/section5/GasOptimization.t.sol)

1. **Write a fork test** that performs a full Uniswap V2 swap:
   ```solidity
   function testUniswapV2Swap() public {
       // Fork mainnet at specific block
       vm.createSelectFork("mainnet", 19000000);

       IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

       // Deal WETH to alice
       deal(WETH, alice, 10 ether);

       vm.startPrank(alice);

       // Approve router
       IERC20(WETH).approve(address(router), 10 ether);

       // Swap WETH → USDC
       address[] memory path = new address[](2);
       path[0] = WETH;
       path[1] = USDC;

       uint256[] memory amounts = router.swapExactTokensForTokens(
           1 ether,
           0,  // No slippage protection (test only!)
           path,
           alice,
           block.timestamp
       );

       vm.stopPrank();

       assertGt(IERC20(USDC).balanceOf(alice), 0);
   }
   ```

2. **Write a fork test** that reads Chainlink price feed data and verifies staleness:
   ```solidity
   function testChainlinkPrice() public {
       vm.createSelectFork("mainnet");

       AggregatorV3Interface feed = AggregatorV3Interface(
           0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419  // ETH/USD
       );

       (,int256 price,, uint256 updatedAt,) = feed.latestRoundData();

       assertGt(price, 1000e8);  // ETH > $1000
       assertLt(block.timestamp - updatedAt, 1 hours);  // Not stale
   }
   ```

3. **Create a gas optimization exercise**:
   - Write a token transfer function two ways: one with `require` strings, one with custom errors
   - Run `forge snapshot` on both and compare:
     ```bash
     forge snapshot --match-test testWithRequireStrings
     # Edit to use custom errors
     forge snapshot --diff
     ```

4. **Write a simple deployment script** for any contract you've built this section

**🎯 Goal:** You should be completely fluent in Foundry before starting Part 2. Fork testing and gas optimization are skills you'll use in every single module.

---

## 📋 Day 13 Summary

**✓ Covered:**
- Fork testing — testing against real deployed contracts and liquidity
- Gas optimization workflow — snapshots, reports, opcode-level analysis
- Optimization patterns — unchecked, packing, calldata, caching
- Foundry scripts — Solidity deployment scripts

**Key takeaway:** Foundry is your primary tool for building and testing DeFi. Master it before Part 2.

---

### 🔗 Cross-Section Concept Links

**Building on earlier sections:**
- **← Section 1 (Modern Solidity):** Custom errors tested with `vm.expectRevert(CustomError.selector)`, UDVTs for type-safe test assertions, transient storage patterns verified with cheatcodes
- **← Section 2 (EVM Changes):** Flash accounting tested with `vm.expectRevert` for lock violations, EIP-7702 delegation tested with `vm.etch` for code injection
- **← Section 3 (Token Approvals):** EIP-2612 permit flows tested with `vm.sign` + EIP-712 digest construction, Permit2 integration tested with `deal()` for token balances
- **← Section 4 (Account Abstraction):** ERC-4337 validation tested with `vm.prank(entryPoint)`, EIP-1271 signatures verified in fork tests against real smart wallets

**Connecting forward:**
- **→ Section 6 (Proxy Patterns):** Testing upgradeable contracts — verify storage layout compatibility, test initializers vs constructors, fork test upgrades against live proxies
- **→ Section 7 (Deployment):** Foundry scripts for deterministic deployment, `CREATE2` address prediction tests, multi-chain deployment verification
- **→ Part 2 (DeFi Protocols):** Every module uses Foundry extensively — AMM invariant tests, lending protocol fork tests, vault fuzz tests, oracle integration tests, flash loan PoCs

---

## 📚 Resources

### Foundry Documentation
- [Foundry Book](https://book.getfoundry.sh/) — official docs (read cover-to-cover)
- [Foundry GitHub](https://github.com/foundry-rs/foundry) — source code and examples
- [Foundry cheatcodes reference](https://book.getfoundry.sh/cheatcodes/) — all `vm.*` functions

### Testing Best Practices
- [Foundry Book - Testing](https://book.getfoundry.sh/forge/tests) — basics
- [Foundry Book - Fuzz Testing](https://book.getfoundry.sh/forge/fuzz-testing) — property-based testing
- [Foundry Book - Invariant Testing](https://book.getfoundry.sh/forge/invariant-testing) — advanced fuzzing

### Production Examples
- [Uniswap V4 test suite](https://github.com/Uniswap/v4-core/tree/main/test) — state-of-the-art testing patterns
- [Aave V3 invariant tests](https://github.com/aave/aave-v3-core/tree/master/test-suites/invariants) — handler patterns
- [Solmate tests](https://github.com/transmissions11/solmate/tree/main/src/test) — clean, minimal examples

### Gas Optimization
- [Rareskills Gas Optimization](https://www.rareskills.io/post/gas-optimization) — comprehensive guide
- [EVM Codes](https://www.evm.codes/) — opcode gas costs
- [Solidity gas optimization tips](https://gist.github.com/hrkrshnn/ee8fabd532058307229d65dcd5836ddc) — from Solidity team

### RPC Providers
- [Alchemy](https://www.alchemy.com/) — free tier, reliable
- [Infura](https://www.infura.io/) — industry standard
- [Ankr](https://www.ankr.com/rpc/) — multi-chain support

---

**Navigation:** [← Previous: Section 4 - Account Abstraction](4-account-abstraction.md) | [Next: Section 6 - Proxy Patterns →](6-proxy-patterns.md)
