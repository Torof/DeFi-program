# DeFi Protocol Engineering — Workspace

Unified Foundry project for all curriculum exercises (Part 1, Part 2, Part 3).

## Structure

```
workspace/
├── src/
│   ├── part1/
│   │   ├── module1/
│   │   │   ├── exercise1-share-math/
│   │   │   └── exercise2-transient-guard/
│   │   ├── module2/
│   │   │   ├── exercise1-flash-accounting/
│   │   │   └── exercise2-eip7702-delegate/
│   │   └── ...
│   └── part2/
│       ├── module1/
│       │   ├── exercise1-defensive-vault/
│       │   ├── exercise2-decimal-normalizer/
│       │   └── mocks/
│       └── ...
├── test/                  # Mirrors src/ structure
└── script/                # Deployment scripts
```

Each module contains numbered exercise subfolders (`exercise1-name/`, `exercise2-name/`, etc.).
Shared files (mocks, interfaces) stay at the module level.

## Setup

```bash
# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies (run from the workspace directory)
cd workspace
git init   # needed if not already a git repo
forge install foundry-rs/forge-std
```

## How It Works

Each exercise has two files:

| File | Role |
|------|------|
| `src/partN/moduleN/exerciseN-name/Exercise.sol` | **Scaffold** — types, signatures, and TODO comments. You fill in the implementations. |
| `test/partN/moduleN/exerciseN-name/Exercise.t.sol` | **Tests** — pre-written, complete. They verify your implementation is correct. |

**Workflow:**
1. Read the scaffold file and the corresponding curriculum section
2. Fill in each `// TODO` block
3. Run `forge test` — when all tests pass, the exercise is complete

**Note:** Some tests pass before you implement anything — this is by design.
Baseline tests prove the vulnerability exists and the vault works for normal use.
Your job is to make the **failing** tests pass.

## Running Tests

```bash
# Run all tests
forge test -vvv

# Run all Part 1 tests
forge test --match-path "test/part1/**/*.sol" -vvv

# Run a specific module
forge test --match-path "test/part1/module1/**/*.sol" -vvv

# Run a specific exercise
forge test --match-contract ShareMathTest -vvv
forge test --match-contract TransientGuardTest -vvv
```

## Current Exercises

### Part 1: Solidity, EVM & Modern Tooling

#### Module 1: Solidity 0.8.x Modern Features

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Vault Share Calculator | `src/part1/module1/exercise1-share-math/ShareMath.sol` | `test/part1/module1/exercise1-share-math/ShareMath.t.sol` | UDVTs, custom operators, free functions, unchecked, custom errors, abi.encodeCall |
| Transient Reentrancy Guard | `src/part1/module1/exercise2-transient-guard/TransientGuard.sol` | `test/part1/module1/exercise2-transient-guard/TransientGuard.t.sol` | transient keyword, tstore/tload assembly, modifier patterns, gas comparison |

#### Module 2: EVM-Level Changes (EIP-1153, EIP-4844, EIP-7702)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Flash Accounting | `src/part1/module2/exercise1-flash-accounting/FlashAccounting.sol` | `test/part1/module2/exercise1-flash-accounting/FlashAccounting.t.sol` | transient storage deep dive, Uniswap V4 pattern, delta accounting |
| EIP-7702 Delegation | `src/part1/module2/exercise2-eip7702-delegate/EIP7702Delegate.sol` | `test/part1/module2/exercise2-eip7702-delegate/EIP7702Delegate.t.sol` | EOA delegation, batching, EIP-1271 signature validation |

#### Module 3: Modern Token Approvals (EIP-2612, Permit2)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| EIP-2612 Permit Vault | `src/part1/module3/exercise1-permit-vault/PermitVault.sol` | `test/part1/module3/exercise1-permit-vault/PermitVault.t.sol` | EIP-2612 permit, EIP-712 signatures, single-tx deposits |
| Safe Permit Wrapper | `src/part1/module3/exercise2-safe-permit/SafePermit.sol` | `test/part1/module3/exercise2-safe-permit/SafePermit.t.sol` | Front-running protection, try/catch patterns, defensive programming |
| Permit2 Integration | `src/part1/module3/exercise3-permit2-vault/Permit2Vault.sol` | `test/part1/module3/exercise3-permit2-vault/Permit2Vault.t.sol` | Permit2 contract, SignatureTransfer, AllowanceTransfer, witness data |

#### Module 4: Account Abstraction (ERC-4337)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Simple Smart Account | `src/part1/module4/exercise1-simple-smart-account/SimpleSmartAccount.sol` | `test/part1/module4/exercise1-simple-smart-account/SimpleSmartAccount.t.sol` | IAccount interface, validateUserOp, ECDSA validation |
| EIP-1271 Support | `src/part1/module4/exercise2-smart-account-eip1271/SmartAccountEIP1271.sol` | `test/part1/module4/exercise2-smart-account-eip1271/SmartAccountEIP1271.t.sol` | Contract signature verification, isValidSignature |
| Paymasters | `src/part1/module4/exercise3-paymasters/Paymasters.sol` | `test/part1/module4/exercise3-paymasters/Paymasters.t.sol` | VerifyingPaymaster, ERC20Paymaster, gas abstraction |

#### Module 5: Foundry Workflow & Testing

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Simple Vault | `src/part1/module5/exercise1-simple-vault/SimpleVault.sol` | `test/part1/module5/exercise1-simple-vault/SimpleVault.t.sol` | ERC-4626 pattern, shares/assets conversion, fuzz testing |
| Gas Optimization | `src/part1/module5/exercise2-gas-optimization/GasOptimization.sol` | `test/part1/module5/exercise2-gas-optimization/GasOptimization.t.sol` | Custom errors, storage packing, calldata vs memory, unchecked |
| Vault Invariants | `test/part1/module5/exercise3-vault-invariant/VaultHandler.sol` | `test/part1/module5/exercise3-vault-invariant/VaultInvariant.t.sol` | Handler pattern, ghost variables, invariant testing, solvency checks |
| Base Test Setup | `test/part1/module5/exercise4-base-test/BaseTest.sol` | `test/part1/module5/exercise4-base-test/BaseTest.t.sol` | Abstract base test, mainnet fork, test users, helper functions |
| Fork Tests | N/A | `test/part1/module5/exercise5-fork-tests/` | Uniswap V2, Chainlink oracles, full swap workflow |
| Deployment Script | `script/DeploySimpleVault.s.sol` | N/A | Foundry scripts, vm.broadcast, env variables |

#### Module 6: Proxy Patterns & Upgradeability

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Uninitialized Proxy | `src/part1/module6/exercise1-uninitialized-proxy/UninitializedProxy.sol` | `test/part1/module6/exercise1-uninitialized-proxy/UninitializedProxy.t.sol` | Proxy attack vectors, initializer modifier, _disableInitializers |
| Storage Collision | `src/part1/module6/exercise2-storage-collision/StorageCollision.sol` | `test/part1/module6/exercise2-storage-collision/StorageCollision.t.sol` | Storage layout compatibility, append-only upgrades, storage gaps |
| Beacon Proxy | `src/part1/module6/exercise3-beacon-proxy/BeaconProxy.sol` | `test/part1/module6/exercise3-beacon-proxy/BeaconProxy.t.sol` | Beacon pattern, multi-proxy upgrades, shared implementation |
| UUPS Vault | `src/part1/module6/exercise4-uups-vault/UUPSVault.sol` | `test/part1/module6/exercise4-uups-vault/UUPSVault.t.sol` | UUPS pattern, V1→V2 upgrade, _authorizeUpgrade, reinitializer |

#### Module 7: Deployment

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Deploy UUPS Vault | `script/DeployUUPSVault.s.sol` | `test/part1/module7/exercise1-deploy-uups/DeployUUPSVault.t.sol` | UUPS deploy + upgrade scripts, proxy verification, multi-network |

### Part 2: DeFi Foundations

#### Module 1: Token Mechanics

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Defensive Vault | `src/part2/module1/exercise1-defensive-vault/DefensiveVault.sol` | `test/part2/module1/exercise1-defensive-vault/DefensiveVault.t.sol` | SafeERC20, fee-on-transfer, balance-before/after |
| Decimal Normalizer | `src/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.sol` | `test/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.t.sol` | Multi-decimal token support, normalization math |

#### Module 2: AMMs & Swaps

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Constant Product Pool | `src/part2/module2/exercise1-constant-product/ConstantProductPool.sol` | `test/part2/module2/exercise1-constant-product/ConstantProductPool.t.sol` | x*y=k, add/remove liquidity, swap math |
| V2 Extensions | N/A (inline TODOs) | `test/part2/module2/exercise1b-v2-extensions/V2Extensions.t.sol` | Flash swap consumer, multi-hop router, TWAP oracle (test-only) |
| V3 Position Calculator | `src/part2/module2/exercise2-v3-position/V3PositionCalculator.sol` | `test/part2/module2/exercise2-v3-position/V3PositionCalculator.t.sol` | Concentrated liquidity, tick math, sqrtPriceX96 |
| Dynamic Fee Hook | `src/part2/module2/exercise3-dynamic-fee/DynamicFeeHook.sol` | `test/part2/module2/exercise3-dynamic-fee/DynamicFeeHook.t.sol` | Uniswap V4 hooks, EWMA volatility, dynamic fees |

#### Module 3: Oracles

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Oracle Consumer | `src/part2/module3/exercise1-oracle-consumer/OracleConsumer.sol` | `test/part2/module3/exercise1-oracle-consumer/OracleConsumer.t.sol` | Chainlink integration, staleness checks, sequencer uptime |
| TWAP Oracle | `src/part2/module3/exercise2-twap-oracle/TWAPOracle.sol` | `test/part2/module3/exercise2-twap-oracle/TWAPOracle.t.sol` | Time-weighted average price, observation ring buffer |
| Dual Oracle | `src/part2/module3/exercise3-dual-oracle/DualOracle.sol` | `test/part2/module3/exercise3-dual-oracle/DualOracle.t.sol` | Chainlink + TWAP fallback, Liquity-inspired pattern |
| Spot Price Manipulation | `src/part2/module3/exercise4-spot-price/SpotPriceManipulation.sol` | `test/part2/module3/exercise4-spot-price/SpotPriceManipulation.t.sol` | AMM spot price attack, oracle-secured lending |

#### Module 4: Lending

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Interest Rate Model | `src/part2/module4/exercise1-interest-rate/InterestRateModel.sol` | `test/part2/module4/exercise1-interest-rate/InterestRateModel.t.sol` | Kink-based rates, utilization, Aave/Compound model |
| Lending Pool | `src/part2/module4/exercise2-lending-pool/LendingPool.sol` | `test/part2/module4/exercise2-lending-pool/LendingPool.t.sol` | Supply/borrow, health factor, oracle integration |
| Config Bitmap | `src/part2/module4/exercise3-config-bitmap/ConfigBitmap.sol` | `test/part2/module4/exercise3-config-bitmap/ConfigBitmap.t.sol` | Bit packing, Aave V3 reserve config pattern |
| Flash Liquidator | `src/part2/module4/exercise4-flash-liquidator/FlashLiquidator.sol` | `test/part2/module4/exercise4-flash-liquidator/FlashLiquidator.t.sol` | Flash loan liquidation, profit extraction |
| Liquidation Scenarios | N/A (inline TODOs) | `test/part2/module4/exercise4b-liquidation-scenarios/LiquidationScenarios.t.sol` | Cascade liquidation, bad debt socialization (test-only) |

#### Module 5: Flash Loans

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Flash Loan Receiver | `src/part2/module5/exercise1-flash-loan-receiver/FlashLoanReceiver.sol` | `test/part2/module5/exercise1-flash-loan-receiver/FlashLoanReceiver.t.sol` | Aave V3 callback, security checks, repayment |
| Flash Loan Arbitrage | `src/part2/module5/exercise2-flash-loan-arbitrage/FlashLoanArbitrage.sol` | `test/part2/module5/exercise2-flash-loan-arbitrage/FlashLoanArbitrage.t.sol` | DEX arbitrage, profit calculation, atomic execution |
| Collateral Swap | `src/part2/module5/exercise3-collateral-swap/CollateralSwap.sol` | `test/part2/module5/exercise3-collateral-swap/CollateralSwap.t.sol` | Multi-step flash loan composition, credit delegation |
| Vault Donation Attack | `src/part2/module5/exercise4-vault-donation/VaultDonationAttack.sol` | `test/part2/module5/exercise4-vault-donation/VaultDonationAttack.t.sol` | ERC-4626 inflation attack, share price manipulation |

#### Module 6: Stablecoins & CDPs (MakerDAO Pattern)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Simple Vat | `src/part2/module6/exercise1-simple-vat/SimpleVat.sol` | `test/part2/module6/exercise1-simple-vat/SimpleVat.t.sol` | Core CDP engine, normalized debt, frob/grab/fold |
| Simple Jug | `src/part2/module6/exercise2-simple-jug/SimpleJug.sol` | `test/part2/module6/exercise2-simple-jug/SimpleJug.t.sol` | Stability fee accumulation, rpow, drip |
| Simple Dog | `src/part2/module6/exercise3-simple-dog/SimpleDog.sol` | `test/part2/module6/exercise3-simple-dog/SimpleDog.t.sol` | Liquidation engine, Dutch auction, bark/take |
| Simple PSM | `src/part2/module6/exercise4-simple-psm/SimplePSM.sol` | `test/part2/module6/exercise4-simple-psm/SimplePSM.t.sol` | Peg Stability Module, 1:1 swap with fee |
| Peg Dynamics | N/A (test-only) | `test/part2/module6/exercise4b-peg-dynamics/PegDynamics.t.sol` | PSM peg restoration, reserve depletion, stability fee dynamics (test-only) |

#### Module 7: Vaults & Yield

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Simple Vault | `src/part2/module7/exercise1-simple-vault/SimpleVault.sol` | `test/part2/module7/exercise1-simple-vault/SimpleVault.t.sol` | ERC-4626 from scratch, deposit/withdraw/mint/redeem |
| Inflation Attack | `src/part2/module7/exercise2-inflation-attack/DefendedVault.sol` | `test/part2/module7/exercise2-inflation-attack/InflationAttack.t.sol` | Share inflation defense, virtual shares/assets offset |
| Simple Allocator | `src/part2/module7/exercise3-simple-allocator/SimpleAllocator.sol` | `test/part2/module7/exercise3-simple-allocator/SimpleAllocator.t.sol` | Multi-strategy yield aggregator, allocation/harvest |
| Auto Compounder | `src/part2/module7/exercise4-auto-compounder/AutoCompounder.sol` | `test/part2/module7/exercise4-auto-compounder/AutoCompounder.t.sol` | Reward compounding, swap integration, harvest timing |

#### Module 8: DeFi Security

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Read-Only Reentrancy | `src/part2/module8/exercise1-reentrancy/ReentrancyAttack.sol` | `test/part2/module8/exercise1-reentrancy/ReadOnlyReentrancy.t.sol` | View function reentrancy, inflated share price, vault.locked() defense |
| Oracle Manipulation | `src/part2/module8/exercise2-oracle/OracleAttack.sol` | `test/part2/module8/exercise2-oracle/OracleManipulation.t.sol` | Flash loan + AMM spot price exploit, Chainlink defense |
| Vault Invariant Testing | `src/part2/module8/exercise3-invariant/VaultHandler.sol` | `test/part2/module8/exercise3-invariant/VaultInvariant.t.sol` | Write tests that find bugs, handler + invariant pattern |
