# Section 7: Deployment & Operations (~0.5 day)

## 📚 Table of Contents

**Day 16: From Local to Production**
- [The Deployment Pipeline](#deployment-pipeline)
- [Deployment Scripts](#deployment-scripts)
- [Contract Verification](#contract-verification)
- [Safe Multisig for Ownership](#safe-multisig)
- [Monitoring and Alerting](#monitoring-alerting)
- [Day 16 Build Exercise](#day16-exercise)

---

## Day 16: From Local to Production

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

# 2. Verify proxy (Etherscan auto-detects EIP-1967 proxies)
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

---

<a id="day16-exercise"></a>
## 🎯 Day 16 Build Exercise

This is the capstone exercise for Part 1:

1. **Write a complete deployment script** for your UUPS vault from Section 6:
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
   - ✅ Verify proxy is detected as EIP-1967 proxy
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

## 📋 Day 16 Summary

**✓ Covered:**
- Deployment pipeline — local → testnet → mainnet
- Solidity scripts — testable, reusable, type-safe deployment
- Contract verification — Etherscan, Sourcify
- Safe multisig — eliminating single-key risk
- Monitoring — Tenderly, Defender, event-based alerts

**Key takeaway:** Deployment is where code meets reality. A perfect contract with a broken deployment is useless. Test your deployment scripts as rigorously as your contracts.

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
- ✅ Modern token approval patterns (EIP-2612, Permit2)
- ✅ Account abstraction (ERC-4337, EIP-7702)
- ✅ Foundry testing workflow
- ✅ Proxy patterns and upgradeability
- ✅ Production deployment pipeline

**You're ready for Part 2:** Reading and building production DeFi protocols (Uniswap, Aave, MakerDAO).

---

**Navigation:** [← Previous: Section 6 - Proxy Patterns](../section6-proxy-patterns/proxy-patterns.md)
