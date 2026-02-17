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

**Workspace:** [`workspace/test/part1/section5/`](../../workspace/test/part1/section5/) — base setup: [`BaseTest.sol`](../../workspace/test/part1/section5/BaseTest.sol), fork tests: [`UniswapV2Fork.t.sol`](../../workspace/test/part1/section5/UniswapV2Fork.t.sol), [`ChainlinkFork.t.sol`](../../workspace/test/part1/section5/ChainlinkFork.t.sol)

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

---

<a id="day12-exercise"></a>
## 🎯 Day 12 Build Exercise

**Workspace:** [`workspace/src/part1/section5/`](../../workspace/src/part1/section5/) — vault: [`SimpleVault.sol`](../../workspace/src/part1/section5/SimpleVault.sol), tests: [`SimpleVault.t.sol`](../../workspace/test/part1/section5/SimpleVault.t.sol), handler: [`VaultHandler.sol`](../../workspace/test/part1/section5/VaultHandler.sol), invariants: [`VaultInvariant.t.sol`](../../workspace/test/part1/section5/VaultInvariant.t.sol)

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

<a id="day13-exercise"></a>
## 🎯 Day 13 Build Exercise

**Workspace:** [`workspace/test/part1/section5/`](../../workspace/test/part1/section5/) — fork tests: [`UniswapSwapFork.t.sol`](../../workspace/test/part1/section5/UniswapSwapFork.t.sol), gas optimization: [`GasOptimization.sol`](../../workspace/src/part1/section5/GasOptimization.sol) and [`GasOptimization.t.sol`](../../workspace/test/part1/section5/GasOptimization.t.sol)

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

**Navigation:** [← Previous: Section 4 - Account Abstraction](../section4-account-abstraction/account-abstraction.md) | [Next: Section 6 - Proxy Patterns →](../section6-proxy-patterns/proxy-patterns.md)
