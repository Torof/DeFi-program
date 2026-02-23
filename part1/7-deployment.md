# Module 7: Deployment & Operations (~0.5 day)

## 📚 Table of Contents

**From Local to Production**
- [The Deployment Pipeline](#deployment-pipeline)
- [Deployment Scripts](#deployment-scripts)
- [Contract Verification](#contract-verification)
- [Safe Multisig for Ownership](#safe-multisig)
- [Monitoring and Alerting](#monitoring-alerting)
- [Build Exercise: Deployment Capstone](#day16-exercise)

---

## From Local to Production

<a id="deployment-pipeline"></a>
### 💡 Concept: The Deployment Pipeline

**Why this matters:** The gap between "tests pass locally" and "production-ready" is where most protocols fail. [Nomad Bridge hack](https://medium.com/nomad-xyz-blog/nomad-bridge-hack-root-cause-analysis-875ad2e5aacd) ($190M) was caused by a deployment initialization error. The code was correct. The deployment was not.

**The production path:**

```
Local development (anvil)
    ↓ forge test
Testnet deployment (Sepolia)
    ↓ forge script --broadcast --verify
Contract verification (Etherscan)
    ↓ verify source code matches bytecode
Ownership transfer (Safe multisig)
    ↓ transfer admin to multisig
Monitoring setup (Tenderly/Defender)
    ↓ alert on key events and state changes
Mainnet deployment
    ↓ same script, different network
Post-deployment verification
    ↓ read state, verify configuration
```

> 🔍 **Deep dive:** [Foundry Book - Deploying](https://book.getfoundry.sh/tutorials/solidity-scripting) covers the full scripting workflow.

#### 🔗 DeFi Pattern Connection

**How real protocols handle deployment:**

| Protocol | Deployment Pattern | Why |
|----------|-------------------|-----|
| **Uniswap V4** | `CREATE2` deterministic + immutable core | Same address on every chain, no proxy overhead |
| **Aave V3** | Factory pattern + governance proposal | `PoolAddressesProvider` deploys all components atomically |
| **Permit2** | `CREATE2` with zero-nonce deployer | Canonical address `0x000000000022D473...` on every chain (← Module 3) |
| **Safe** | `CREATE2` proxy factory | Deterministic wallet addresses before deployment |
| **MakerDAO** | Spell-based deployment | Each upgrade is a "spell" contract voted through governance |

**The pattern:** Production DeFi deployment is never "run a script once." It's:
1. **Deterministic** — Same address across chains (`CREATE2`)
2. **Atomic** — Deploy + initialize in one transaction (prevent front-running)
3. **Governed** — Multisig or governance approval before execution
4. **Verified** — Source code verified immediately after deployment

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How do you handle multi-chain deployments?"**
   - Good answer: "Same Foundry script with different RPC URLs"
   - Great answer: "I use `CREATE2` for deterministic addresses across chains, with a deployer contract that ensures the same address everywhere. The deployment script verifies chain-specific parameters (token addresses, oracle feeds) from a config file, and I run fork tests against each target chain before broadcasting. Post-deployment, I verify on each chain's block explorer and run the same integration test suite against the live deployments"

2. **"What can go wrong during deployment?"**
   - Good answer: "Initialization front-running, wrong constructor args"
   - Great answer: "The biggest risk is initialization: if deploy and initialize aren't atomic, an attacker front-runs `initialize()` and takes ownership (← Module 6 Wormhole example). Second is address-dependent configuration — hardcoded token addresses that differ between chains. Third is gas estimation: a script that works on Sepolia may need different gas on mainnet during congestion. I always dry-run with `forge script` (no `--broadcast`) first"

**Interview Red Flags:**
- 🚩 Deploying without dry-running first
- 🚩 Not knowing about `CREATE2` deterministic deployment
- 🚩 Deploying proxy + initialize in separate transactions
- 🚩 Not verifying contracts on block explorers

**Pro tip:** Study how Permit2 achieved its canonical `0x000000000022D4...` address across every chain — it's the textbook `CREATE2` deployment. Being able to walk through deterministic deployment from salt selection to address prediction shows you understand the full deployment stack, not just `forge script --broadcast`.

---

<a id="deployment-scripts"></a>
### 💡 Concept: Deployment Scripts

**📊 Why Solidity scripts > JavaScript:**

| Feature | Solidity Scripts ✅ | JavaScript |
|---------|-------------------|------------|
| **Testable** | Can write tests for deployment | Hard to test |
| **Reusable** | Same script: local, testnet, mainnet | Often need separate files |
| **Type-safe** | Compiler catches errors | Runtime errors |
| **DRY** | Use contract imports directly | Duplicate ABIs/addresses |

```solidity
// script/Deploy.s.sol
import "forge-std/Script.sol";
import {VaultV1} from "../src/VaultV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() public returns (address) {
        // Load environment variables
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("VAULT_TOKEN");
        address initialOwner = vm.envOr("INITIAL_OWNER", vm.addr(deployerKey));

        console.log("=== UUPS Vault Deployment ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("Token:", tokenAddress);

        vm.startBroadcast(deployerKey);

        // Deploy implementation
        VaultV1 implementation = new VaultV1();
        console.log("Implementation:", address(implementation));

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            VaultV1.initialize,
            (tokenAddress, initialOwner)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy:", address(proxy));

        // Verify initialization
        VaultV1 vault = VaultV1(address(proxy));
        require(vault.owner() == initialOwner, "Init failed");
        require(address(vault.token()) == tokenAddress, "Token mismatch");

        vm.stopBroadcast();

        console.log("\n=== Next Steps ===");
        console.log("1. Verify on Etherscan (if not auto-verified)");
        console.log("2. Transfer ownership to Safe multisig");
        console.log("3. Test deposit/withdraw");

        return address(proxy);
    }
}
```

```bash
# Dry run (simulation) ✅
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC

# Deploy + verify in one command ✅
forge script script/Deploy.s.sol \
    --rpc-url $SEPOLIA_RPC \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_KEY

# Resume a failed broadcast (e.g., if verification timed out) ✅
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC --resume
```

> ⚡ **Common pitfall:** Forgetting to fund the deployer address with testnet/mainnet ETH before broadcasting. The script simulates successfully but fails on broadcast with "insufficient funds."

> 🔍 **Deep dive:** [Foundry - Best Practices for Writing Scripts](https://getfoundry.sh/guides/best-practices/writing-scripts/) covers testing scripts, error handling, and multi-chain deployments. [Cyfrin Updraft - Deploying with Foundry](https://updraft.cyfrin.io/courses/foundry/foundry-simple-storage/deploying-locally-anvil) provides hands-on tutorials.

💻 **Quick Try:**

After deploying any contract (even on a local `anvil` instance), interact with it using `cast`:

```bash
# Start a local anvil node (in another terminal)
anvil

# Deploy a simple contract
forge create src/VaultV1.sol:VaultV1 --rpc-url http://localhost:8545 --private-key 0xac0974...

# Read state (no gas cost)
cast call $CONTRACT_ADDRESS "owner()" --rpc-url http://localhost:8545
cast call $CONTRACT_ADDRESS "totalSupply()" --rpc-url http://localhost:8545

# Write state (costs gas)
cast send $CONTRACT_ADDRESS "deposit(uint256)" 1000000 --rpc-url http://localhost:8545 --private-key 0xac0974...

# Decode return data
cast call $CONTRACT_ADDRESS "balanceOf(address)" $USER_ADDRESS --rpc-url http://localhost:8545 | cast to-dec

# Read storage slots directly (useful for debugging proxies)
cast storage $CONTRACT_ADDRESS 0 --rpc-url http://localhost:8545
```

`cast` is your Swiss Army knife for interacting with deployed contracts. Master it — you'll use it constantly for post-deployment verification and debugging.

#### 🔍 Deep Dive: CREATE2 Deterministic Deployment

**The problem:** When deploying to multiple chains, `CREATE` gives different addresses because the deployer's nonce differs across chains. This breaks cross-chain composability — users and protocols need to know your address in advance.

**The solution:** `CREATE2` computes the address from `deployer + salt + initcode`, not the nonce:

```
CREATE2 address = keccak256(0xff ++ deployer ++ salt ++ keccak256(initcode))[12:]
```

```
┌──────────────────────────────────────────────────┐
│              CREATE vs CREATE2                    │
│                                                   │
│  CREATE:                                          │
│  address = keccak256(sender, nonce)[12:]           │
│  ├── Depends on nonce (different per chain)       │
│  └── Non-deterministic across chains ❌           │
│                                                   │
│  CREATE2:                                         │
│  address = keccak256(0xff, sender, salt, initCodeHash)[12:] │
│  ├── Same sender + same salt + same code          │
│  └── = Same address on every chain ✅             │
└──────────────────────────────────────────────────┘
```

**Production example — Permit2:**

Permit2 uses the same canonical address (`0x000000000022D473030F116dDEE9F6B43aC78BA3`) on every chain. This is why Uniswap, 1inch, and every other protocol can hardcode the Permit2 address.

```solidity
// Foundry script using CREATE2
contract DeterministicDeploy is Script {
    function run() public {
        vm.startBroadcast();

        // Same salt on every chain = same address
        bytes32 salt = keccak256("my-protocol-v1");

        MyContract c = new MyContract{salt: salt}(constructorArgs);

        console.log("Deployed at:", address(c));
        // This address will be identical on mainnet, Arbitrum, Optimism, etc.

        vm.stopBroadcast();
    }
}
```

```bash
# Predict the address before deployment
cast create2 --starts-with 0x --salt $SALT --init-code-hash $HASH
```

**When to use CREATE2:**
- Multi-chain protocols (same address everywhere)
- Factory patterns (predict child addresses before deployment)
- Vanity addresses (cosmetic, but Permit2's `0x000000000022D4...` is memorable)
- Counterfactual wallets in Account Abstraction (← Module 4)

#### 🎓 Intermediate Example: Multi-Chain Deployment Pattern

```solidity
contract MultiChainDeploy is Script {
    struct ChainConfig {
        string rpcUrl;
        address weth;
        address usdc;
        address chainlinkEthUsd;
    }

    function getConfig() internal view returns (ChainConfig memory) {
        if (block.chainid == 1) {
            return ChainConfig({
                rpcUrl: "mainnet",
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                chainlinkEthUsd: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
            });
        } else if (block.chainid == 42161) {
            return ChainConfig({
                rpcUrl: "arbitrum",
                weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                chainlinkEthUsd: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
            });
        } else {
            revert("Unsupported chain");
        }
    }

    function run() public {
        ChainConfig memory config = getConfig();
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        // Deploy with CREATE2 for same address across chains
        bytes32 salt = keccak256("my-vault-v1");
        VaultV1 impl = new VaultV1{salt: salt}();

        // Chain-specific initialization
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            address(impl),
            abi.encodeCall(VaultV1.initialize, (config.weth, config.chainlinkEthUsd))
        );

        vm.stopBroadcast();
    }
}
```

**The pattern:** Configuration varies per chain, but the deployment structure is identical. This is how production protocols achieve consistent addresses and behavior across L1 and L2s.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Deploy and initialize in separate transactions
vm.startBroadcast(deployerKey);
ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
vm.stopBroadcast();
// ... later ...
VaultV1(address(proxy)).initialize(owner);  // Attacker front-runs this!

// ✅ CORRECT: Atomic deploy + initialize
vm.startBroadcast(deployerKey);
ERC1967Proxy proxy = new ERC1967Proxy(
    address(impl),
    abi.encodeCall(VaultV1.initialize, (owner))  // Initialized in constructor
);
vm.stopBroadcast();

// ❌ WRONG: Hardcoded addresses across chains
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;  // Mainnet only!
// Deploying this to Arbitrum points to a wrong/nonexistent contract

// ✅ CORRECT: Chain-specific configuration
function getUSDC() internal view returns (address) {
    if (block.chainid == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    if (block.chainid == 42161) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    revert("Unsupported chain");
}

// ❌ WRONG: No post-deployment verification
vm.startBroadcast(deployerKey);
new ERC1967Proxy(address(impl), initData);
vm.stopBroadcast();
// Hope it worked... 🤞

// ✅ CORRECT: Verify state after deployment
VaultV1 vault = VaultV1(address(proxy));
require(vault.owner() == expectedOwner, "Owner mismatch");
require(address(vault.token()) == expectedToken, "Token mismatch");
require(vault.totalSupply() == 0, "Unexpected initial state");
```

---

<a id="contract-verification"></a>
### 💡 Concept: Contract Verification

**Why this matters:** Unverified contracts can't be audited by users. Verified contracts prove that deployed bytecode matches published source code. This is **mandatory** for any serious protocol. ✨

> Used by: [Etherscan](https://etherscan.io/), [Blockscout](https://blockscout.com/), [Sourcify](https://sourcify.dev/)

```bash
# ✅ Automatic verification (preferred)
forge script script/Deploy.s.sol \
    --rpc-url $SEPOLIA_RPC \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_KEY

# ✅ Manual verification (if auto-verify failed)
forge verify-contract <ADDRESS> src/VaultV1.sol:VaultV1 \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_KEY \
    --constructor-args $(cast abi-encode "constructor()" )

# For proxy verification:
# 1. Verify implementation
forge verify-contract <IMPL_ADDRESS> src/VaultV1.sol:VaultV1 \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_KEY

# 2. Verify proxy (Etherscan auto-detects [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) proxies)
#    Just mark it as a proxy in the Etherscan UI
```

> ⚡ **Common pitfall:** Constructor arguments. If your contract has constructor parameters, you MUST provide them with `--constructor-args`. Use `cast abi-encode` to format them correctly.

---

<a id="safe-multisig"></a>
### 💡 Concept: Safe Multisig for Ownership

**Why this matters:** A single private key is a single point of failure. Every significant protocol exploit includes the phrase "...and the admin key was compromised." [Ronin Bridge hack](https://www.halborn.com/blog/post/explained-the-ronin-hack-march-2022) ($625M) - single key access.

**⚠️ For any protocol managing real value, a single-key owner is unacceptable.**

> Use [Safe](https://safe.global/) (formerly Gnosis Safe) — battle-tested, used by Uniswap, Aave, Compound

**The pattern:**

1. **Deploy** with your development key as owner
2. **Verify** everything works (test transactions)
3. **Deploy or use existing Safe multisig**:
   - Mainnet: use a hardware wallet-backed Safe
   - Testnet: create a 2-of-3 Safe for testing
4. **Call `transferOwnership(safeAddress)`** (or the 2-step variant for safety)
5. **Confirm the transfer** from the Safe UI
6. **Verify the new owner** on-chain:
   ```bash
   cast call $PROXY "owner()" --rpc-url $RPC_URL
   # Should return: Safe address ✅
   ```

**🏗️ Safe resources:**
- [Safe App](https://app.safe.global/) — create and manage Safes
- [Safe Contracts](https://github.com/safe-global/safe-contracts) — source code
- [Safe Transaction Service](https://docs.safe.global/safe-core-api/available-services) — API for off-chain signature collection

> ⚡ **Common pitfall:** Using 1-of-N multisig. That's just a single key with extra steps. Use at minimum 2-of-3 for testing, 3-of-5+ for production.

---

<a id="monitoring-alerting"></a>
### 💡 Concept: Monitoring and Alerting

**Why this matters:** You need to know when things go wrong **before** users tweet about it. [Cream Finance exploit](https://medium.com/cream-finance/c-r-e-a-m-finance-post-mortem-amp-exploit-6ceb20a630c5) ($130M) - repeated attacks over several hours. Monitoring could have limited damage.

**The tools:**

**1. Tenderly**

Transaction simulation, debugging, and monitoring.

Set up alerts for:
- ⚠️ Failed transactions (might indicate attack attempts)
- ⚠️ Unusual parameter values (e.g., price > 2x normal)
- ⚠️ Oracle price deviations
- 💰 Large deposits/withdrawals (whale watching)
- 🔐 Admin function calls (ownership transfer, upgrades)

> [Tenderly Dashboard](https://dashboard.tenderly.co/)

**2. OpenZeppelin Defender**

Automated operations and monitoring:
- **Sentinel:** Monitor transactions and events, trigger alerts
- **Autotasks:** Scheduled transactions (keeper-like functions)
- **Admin:** Manage upgrades through UI with multisig integration
- **Relay:** Gasless transaction infrastructure

> [Defender Docs](https://docs.openzeppelin.com/defender/)

> 🔍 **Deep dive:** [OpenZeppelin - Introducing Defender Sentinels](https://blog.openzeppelin.com/introducing-sentinels) explains smart contract monitoring and emergency response patterns. [OpenZeppelin - Monitor Documentation](https://docs.openzeppelin.com/defender/module/monitor) provides setup guides for Sentinels with Forta integration.

**3. On-chain Events**

**Every significant state change should emit an event.** This isn't just good practice—it's essential for monitoring, indexing, and incident response.

```solidity
// ✅ GOOD: Emit events for all state changes
event Deposit(address indexed user, uint256 amount, uint256 shares);
event Withdraw(address indexed user, uint256 shares, uint256 amount);
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
event UpgradeAuthorized(address indexed implementation);

function deposit(uint256 amount) external {
    // ... logic ...
    emit Deposit(msg.sender, amount, shares);
}
```

**Event monitoring pattern:**

```javascript
// Example: Monitor large withdrawals
safe.filters.Withdraw(null, null, gte(1000000e18))
```

> ⚡ **Common pitfall:** Not indexing the right parameters. You can only index up to 3 parameters per event. Choose the ones you'll filter by (usually addresses and IDs).

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Single EOA as protocol owner
contract Vault is Ownable {
    constructor() Ownable(msg.sender) {}  // Deployer EOA = single point of failure
    // If the key leaks, attacker owns the entire protocol
}

// ✅ CORRECT: Transfer ownership to multisig after deployment
// Step 1: Deploy with EOA (convenient for setup)
// Step 2: Verify everything works
// Step 3: Transfer to Safe
vault.transferOwnership(safeMultisigAddress);

// ❌ WRONG: No events on critical state changes
function setFee(uint256 newFee) external onlyOwner {
    fee = newFee;  // Silent — no monitoring tool can detect this change
}

// ✅ CORRECT: Emit events for every admin action
event FeeUpdated(uint256 oldFee, uint256 newFee, address indexed updatedBy);
function setFee(uint256 newFee) external onlyOwner {
    emit FeeUpdated(fee, newFee, msg.sender);
    fee = newFee;
}

// ❌ WRONG: No emergency pause mechanism
// When an exploit starts, no way to stop the damage

// ✅ CORRECT: Include pausable for emergency response
contract Vault is Pausable, Ownable {
    function deposit(uint256 amount) external whenNotPaused { /* ... */ }
    function pause() external onlyOwner { _pause(); }  // Guardian can stop bleeding
}
```

#### 🔗 DeFi Pattern Connection

**How real protocols handle operations:**

1. **Uniswap Governance** — Timelock + Governor:
   - Protocol changes go through on-chain governance proposal
   - 2-day voting period, 2-day timelock delay
   - Anyone can see upcoming changes before execution
   - **Lesson:** Transparency builds trust more than multisig alone

2. **Aave Guardian** — Emergency multisig + governance:
   - Normal upgrades: Full governance process (propose → vote → timelock → execute)
   - Emergency: Guardian multisig can pause markets instantly
   - **Lesson:** Two paths — slow/safe for upgrades, fast for emergencies

3. **MakerDAO Spells** — Executable code as governance:
   - Each change is a "spell" — a contract that executes the change
   - Spell code is public and auditable before voting
   - Once voted, the spell executes atomically
   - **Lesson:** Governance proposals should be code, not descriptions

4. **Incident Response Pattern**:
   ```
   Detection (Tenderly alert) → 30 seconds
       ↓
   Triage (is this an exploit?) → 5 minutes
       ↓
   Pause protocol (Guardian multisig) → 10 minutes
       ↓
   Root cause analysis → hours
       ↓
   Fix + test + deploy → hours/days
       ↓
   Post-mortem → days
   ```
   - Having `pause()` functionality and a responsive multisig can be the difference between $0 and $100M+ lost

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you set up operations for a new protocol?"**
   - Good answer: "Safe multisig for admin, Tenderly for monitoring"
   - Great answer: "I'd separate concerns: a 3-of-5 multisig for routine operations (fee changes, parameter updates), a separate Guardian multisig for emergencies (pause), and a governance timelock for upgrades. Monitoring with Tenderly alerts on admin function calls, large token movements, and oracle deviations. Event emission for every state change so we can build dashboards and respond to anomalies. I'd also write runbooks for common scenarios — 'oracle goes stale', 'exploit detected', 'governance proposal needs execution'"

2. **"What's your deployment checklist before mainnet?"**
   - Good answer: "Tests pass, contract verified, multisig set up"
   - Great answer: "Pre-deployment: all tests pass including fork tests against mainnet, `forge inspect` confirms storage layout, dry-run with `forge script` (no broadcast). Deployment: atomic deploy+initialize, verify source on Etherscan/Sourcify immediately. Post-deployment: read all state variables with `cast call` to confirm configuration, transfer ownership to multisig, set up monitoring alerts, do a small real transaction to verify end-to-end, document all addresses in a deployment manifest"

**Interview Red Flags:**
- 🚩 Single-key ownership for any protocol managing value
- 🚩 No monitoring or alerting strategy
- 🚩 Not knowing about Safe multisig
- 🚩 No post-deployment verification process

**Pro tip:** The best DeFi teams have incident response playbooks *before* anything goes wrong. Being able to discuss operational security — pause mechanisms, monitoring thresholds, communication channels — shows you think about protocols holistically, not just the code.

---

<a id="day16-exercise"></a>
## 🎯 Build Exercise: Deployment Capstone

**Workspace:** [`workspace/script/`](../workspace/script/) — deployment script: [`DeployUUPSVault.s.sol`](../workspace/script/DeployUUPSVault.s.sol), tests: [`DeployUUPSVault.t.sol`](../workspace/test/part1/module7/DeployUUPSVault.t.sol)

This is the capstone exercise for Part 1:

1. **Write a complete deployment script** for your UUPS vault from Module 6:
   - Load configuration from environment variables
   - Deploy implementation
   - Deploy proxy with initialization
   - Verify initialization succeeded
   - Log all addresses and next steps

2. **Deploy to Sepolia testnet**:
   ```bash
   forge script script/Deploy.s.sol \
       --rpc-url $SEPOLIA_RPC \
       --broadcast \
       --verify \
       --etherscan-api-key $ETHERSCAN_KEY
   ```

3. **Verify the contract** on Etherscan:
   - ✅ Check both implementation and proxy are verified
   - ✅ Verify proxy is detected as [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) proxy
   - ✅ Test "Read Contract" and "Write Contract" tabs

4. **(Optional) Set up a Safe multisig** on Sepolia:
   - Create a 2-of-3 Safe at [safe.global](https://app.safe.global/)
   - Transfer vault ownership to the Safe
   - Execute a test transaction (deposit) through the Safe

5. **Post-deployment verification script**:
   ```bash
   # Verify owner
   cast call $PROXY "owner()" --rpc-url $SEPOLIA_RPC

   # Verify token
   cast call $PROXY "token()" --rpc-url $SEPOLIA_RPC

   # Verify version
   cast call $PROXY "version()" --rpc-url $SEPOLIA_RPC
   ```

**🎯 Goal:** Understand the full lifecycle from development to deployment. This pipeline is what you'll use in Part 2 when deploying your builds to testnets for more realistic testing.

---

## 📋 Summary: Deployment and Operations

**✓ Covered:**
- Deployment pipeline — local → testnet → mainnet
- Solidity scripts — testable, reusable, type-safe deployment
- Contract verification — Etherscan, Sourcify
- Safe multisig — eliminating single-key risk
- Monitoring — Tenderly, Defender, event-based alerts

**Key takeaway:** Deployment is where code meets reality. A perfect contract with a broken deployment is useless. Test your deployment scripts as rigorously as your contracts.

---

### 📖 How to Study Production Deployment Scripts

When you look at a protocol's `script/` directory, here's how to navigate it:

**Step 1: Find the main deployment script**
Usually named `Deploy.s.sol`, `DeployProtocol.s.sol`, or similar. This is the entry point.

**Step 2: Look for the configuration pattern**
How does the script handle different chains?
- Environment variables (`vm.envAddress`)
- Chain-specific config files
- `if (block.chainid == 1)` branching
- Separate config contracts

**Step 3: Trace the deployment order**
Contracts are deployed in dependency order. The script reveals the architecture:
```
1. Deploy libraries (no dependencies)
2. Deploy core contracts (depend on libraries)
3. Deploy proxies (wrap core contracts)
4. Initialize (set parameters, link contracts)
5. Transfer ownership (to multisig/governance)
```

**Step 4: Check post-deployment verification**
Good scripts verify state after deployment:
```solidity
require(vault.owner() == expectedOwner, "Owner mismatch");
require(vault.token() == expectedToken, "Token mismatch");
```

**Step 5: Look for upgrade scripts**
Separate from initial deployment — these handle proxy upgrades with storage layout checks.

**Don't get stuck on:** Helper utilities and test-specific deployment code. Focus on the production deployment path.

### 📖 Production Study Order

Study these deployment scripts in this order — each builds on patterns from the previous:

| # | Repository | Why Study This | Key Files |
|---|-----------|----------------|-----------|
| 1 | [Foundry Book - Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting) | Official patterns — learn the `Script` base class and `vm.broadcast` | Tutorial examples |
| 2 | [Morpho Blue scripts](https://github.com/morpho-org/morpho-blue/tree/main/script) | Clean, minimal production deployment — single contract, no proxies | Deploy.s.sol |
| 3 | [Uniswap V4 scripts](https://github.com/Uniswap/v4-core/tree/main/script) | `CREATE2` deterministic deployment — immutable core pattern | DeployPoolManager.s.sol |
| 4 | [Permit2 deployment](https://github.com/Uniswap/permit2) | Canonical `CREATE2` address — the gold standard for multi-chain deployment | DeployPermit2.s.sol |
| 5 | [Aave V3 deploy](https://github.com/aave/aave-v3-deploy) | Full production pipeline — multi-contract, multi-chain, proxy + beacon | deploy/, config/ |
| 6 | [Safe deployment](https://github.com/safe-global/safe-contracts/tree/main/scripts) | Factory + `CREATE2` for deterministic wallet addresses | deploy scripts |

**Reading strategy:** Start with the Foundry Book for idioms, then Morpho for the simplest real deployment. Move to Uniswap/Permit2 for `CREATE2` mastery. Finish with Aave for the most complex deployment you'll encounter — multi-contract, multi-chain, proxy architecture. Safe shows `CREATE2` applied to wallet infrastructure.

---

### 🔗 Cross-Module Concept Links

#### Building on Earlier Modules

| Module | Concept | How It Connects |
|--------|---------|-----------------|
| [← M1 Modern Solidity](1-solidity-modern.md) | `abi.encodeCall` | Type-safe initialization data in deployment scripts — compiler catches mismatched args |
| [← M1 Modern Solidity](1-solidity-modern.md) | Custom errors | Deployment validation failures with rich error data |
| [← M2 EVM Changes](2-evm-changes.md) | EIP-7702 delegation | Delegation targets must exist before EOA delegates — deployment order matters |
| [← M3 Token Approvals](3-token-approvals.md) | Permit2 `CREATE2` | Gold standard for deterministic multi-chain deployment — canonical address everywhere |
| [← M3 Token Approvals](3-token-approvals.md) | `DOMAIN_SEPARATOR` | Includes `block.chainid` — verify it differs per chain after deployment |
| [← M4 Account Abstraction](4-account-abstraction.md) | `CREATE2` factories | ERC-4337 wallet factories use counterfactual addresses — wallet exists before deployment |
| [← M5 Foundry](5-foundry.md) | `forge script` | Primary deployment tool — simulation, broadcast, resume |
| [← M5 Foundry](5-foundry.md) | `cast` commands | Post-deployment interaction: `cast call` for reads, `cast send` for writes |
| [← M6 Proxy Patterns](6-proxy-patterns.md) | Atomic deploy+init | UUPS proxy must deploy + initialize in one tx to prevent front-running |
| [← M6 Proxy Patterns](6-proxy-patterns.md) | Storage layout checks | `forge inspect storage-layout` before any upgrade deployment |

#### Part 2 Connections

| Part 2 Module | Deployment Pattern | Application |
|---------------|-------------------|-------------|
| [M1: Token Mechanics](../part2/1-token-mechanics.md) | Token deployment | ERC-20 deployment with initial supply, fee configuration, and access control setup |
| [M2: AMMs](../part2/2-amms.md) | Factory pattern | Pool creation through factory contracts — deterministic pool addresses from token pairs |
| [M3: Oracles](../part2/3-oracles.md) | Feed configuration | Chain-specific Chainlink feed addresses — different on every L2 |
| [M4: Lending](../part2/4-lending.md) | Multi-contract deploy | Aave V3 deploys Pool + Configurator + Oracle + aTokens atomically via AddressesProvider |
| [M5: Flash Loans](../part2/5-flash-loans.md) | Arbitrage scripts | Flash loan deployment with DEX router addresses per chain |
| [M6: Stablecoins](../part2/6-stablecoins-cdps.md) | CDP deployment | Multi-contract CDP engine with oracle + liquidation + stability modules |
| [M7: Vaults](../part2/7-vaults-yield.md) | Strategy deployment | Vault + strategy deploy scripts with yield source configuration per chain |
| [M8: Security](../part2/8-defi-security.md) | Post-deploy audit | Deployment verification as security practice — check all state before going live |
| [M9: Integration](../part2/9-integration-capstone.md) | Full pipeline | End-to-end deployment: factory → pools → oracles → governance → monitoring |

---

## 📚 Resources

### Deployment & Scripting
- [Foundry Book - Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting) — full tutorial
- [Foundry Book - Deploying](https://book.getfoundry.sh/reference/forge/forge-script) — `forge script` reference
- [Etherscan Verification](https://docs.etherscan.io/tutorials/verifying-contracts-programmatically) — API docs

### Safe Multisig
- [Safe App](https://app.safe.global/) — create and manage Safes
- [Safe Contracts](https://github.com/safe-global/safe-contracts) — source code
- [Safe Documentation](https://docs.safe.global/) — full docs
- [Safe Transaction Service API](https://docs.safe.global/safe-core-api/available-services)

### Monitoring & Operations
- [Tenderly](https://tenderly.co/) — monitoring and simulation
- [OpenZeppelin Defender](https://www.openzeppelin.com/defender) — automated ops
- [Blocknative Mempool Explorer](https://www.blocknative.com/) — real-time transaction monitoring

### Testnets & Faucets
- [Sepolia Faucet (Alchemy)](https://sepoliafaucet.com/)
- [Sepolia Faucet (Infura)](https://www.infura.io/faucet/sepolia)
- [Chainlist](https://chainlist.org/) — RPC endpoints for all networks

### Post-Deployment Security
- [Nomad Bridge postmortem](https://medium.com/nomad-xyz-blog/nomad-bridge-hack-root-cause-analysis-875ad2e5aacd) — initialization error ($190M)
- [Ronin Bridge postmortem](https://www.halborn.com/blog/post/explained-the-ronin-hack-march-2022) — compromised keys ($625M)
- [Rekt News](https://rekt.news/) — exploit case studies

---

## 🎉 Part 1 Complete!

You've now covered:
- ✅ Solidity 0.8.x modern features
- ✅ EVM-level changes (Dencun, Pectra)
- ✅ Modern token approval patterns ([EIP-2612](https://eips.ethereum.org/EIPS/eip-2612), Permit2)
- ✅ Account abstraction ([ERC-4337](https://eips.ethereum.org/EIPS/eip-4337), [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702))
- ✅ Foundry testing workflow
- ✅ Proxy patterns and upgradeability
- ✅ Production deployment pipeline

**You're ready for Part 2:** Reading and building production DeFi protocols (Uniswap, Aave, MakerDAO).

---

**Navigation:** [← Module 6: Proxy Patterns](6-proxy-patterns.md)
