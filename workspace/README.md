# DeFi Protocol Engineering — Workspace

Unified Foundry project for all curriculum exercises (Part 1, Part 2, Part 3).

## Structure

```
workspace/
├── src/
│   ├── part1/          # Solidity, EVM & Modern Tooling exercises
│   │   ├── module1/   # Solidity 0.8.x Modern Features
│   │   ├── module2/   # EVM Changes (EIP-1153, 4844, 7702)
│   │   └── ...
│   ├── part2/          # DeFi Foundations exercises (coming soon)
│   │   ├── module1/    # Token Mechanics
│   │   ├── module2/    # AMMs
│   │   └── ...
│   └── part3/          # Modern DeFi Stack exercises (coming soon)
└── test/
    ├── part1/
    ├── part2/
    └── part3/
```

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
| `src/partN/sectionN/Exercise.sol` | **Scaffold** — types, signatures, and TODO comments. You fill in the implementations. |
| `test/partN/sectionN/Exercise.t.sol` | **Tests** — pre-written, complete. They verify your implementation is correct. |

**Workflow:**
1. Read the scaffold file and the corresponding curriculum section
2. Fill in each `// TODO` block
3. Run `forge test` — when all tests pass, the exercise is complete

**Note:** Some tests pass before you implement anything — this is by design.
Baseline tests prove the vulnerability exists and the vault works for normal use.
For example, in TransientGuard, `test_UnguardedVault_IsVulnerable` shows the
reentrancy attack succeeds without a guard, and `NormalWithdraw` tests confirm
the vault handles legitimate deposits/withdrawals. Your job is to make the
**failing** tests pass (the guard and math tests).

## Running Tests

```bash
# Run all tests
forge test -vvv

# Run all Part 1 tests
forge test --match-path "test/part1/**/*.sol" -vvv

# Run a specific section
forge test --match-path "test/part1/module1/*.sol" -vvv

# Run a specific exercise
forge test --match-contract ShareMathTest -vvv
forge test --match-contract TransientGuardTest -vvv
```

## Current Exercises

### Part 1: Solidity, EVM & Modern Tooling

#### Module 1: Solidity 0.8.x Modern Features

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Vault Share Calculator | `src/part1/module1/ShareMath.sol` | `test/part1/module1/ShareMath.t.sol` | UDVTs, custom operators, free functions, unchecked, custom errors, abi.encodeCall |
| Transient Reentrancy Guard | `src/part1/module1/TransientGuard.sol` | `test/part1/module1/TransientGuard.t.sol` | transient keyword, tstore/tload assembly, modifier patterns, gas comparison |

#### Module 2: EVM-Level Changes (EIP-1153, EIP-4844, EIP-7702)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Flash Accounting | `src/part1/module2/FlashAccounting.sol` | `test/part1/module2/FlashAccounting.t.sol` | transient storage deep dive, tstore/tload assembly, Uniswap V4 pattern, delta accounting, settlement |
| EIP-7702 Delegation | `src/part1/module2/EIP7702Delegate.sol` | `test/part1/module2/EIP7702Delegate.t.sol` | EOA delegation, DELEGATECALL semantics, batching, EIP-1271 signature validation, account abstraction |

#### Module 3: Modern Token Approvals (EIP-2612, Permit2)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| EIP-2612 Permit Vault | `src/part1/module3/PermitVault.sol` | `test/part1/module3/PermitVault.t.sol` | EIP-2612 permit, EIP-712 signatures, single-tx deposits, nonce management, vm.sign() testing |
| Permit2 Integration | `src/part1/module3/Permit2Vault.sol` | `test/part1/module3/Permit2Vault.t.sol` | Permit2 contract, SignatureTransfer, AllowanceTransfer, witness data, mainnet fork testing |
| Safe Permit Wrapper | `src/part1/module3/SafePermit.sol` | `test/part1/module3/SafePermit.t.sol` | Front-running protection, try/catch patterns, non-EIP-2612 fallback, defensive programming |

#### Module 4: Account Abstraction (ERC-4337)

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Simple Smart Account | `src/part1/module4/SimpleSmartAccount.sol` | `test/part1/module4/SimpleSmartAccount.t.sol` | IAccount interface, validateUserOp, ECDSA validation, UserOperation flow, EntryPoint integration |
| EIP-1271 Support | `src/part1/module4/SmartAccountEIP1271.sol` | `test/part1/module4/SmartAccountEIP1271.t.sol` | Contract signature verification, isValidSignature, smart account + DeFi integration |
| Paymasters | `src/part1/module4/Paymasters.sol` | `test/part1/module4/Paymasters.t.sol` | VerifyingPaymaster, ERC20Paymaster, gas abstraction, validatePaymasterUserOp, postOp accounting |

#### Module 5: Foundry Workflow & Testing

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| Base Test Setup | `test/part1/module5/BaseTest.sol` | `test/part1/module5/BaseTest.t.sol` | Abstract base test, mainnet fork, test users, helper functions, labels |
| Uniswap V2 Fork | N/A | `test/part1/module5/UniswapV2Fork.t.sol` | Reading reserves, swap calculations, token order, price impact |
| Chainlink Fork | N/A | `test/part1/module5/ChainlinkFork.t.sol` | Price feeds, staleness checks, historical data, derived prices |
| Simple Vault | `src/part1/module5/SimpleVault.sol` | `test/part1/module5/SimpleVault.t.sol` | ERC-4626 pattern, shares/assets conversion, fuzz testing with bound() |
| Vault Handler | `test/part1/module5/VaultHandler.sol` | N/A | Handler pattern, ghost variables, actor management, constraining fuzzer |
| Vault Invariants | N/A | `test/part1/module5/VaultInvariant.t.sol` | Invariant testing, solvency checks, conservation laws, targetContract |
| Uniswap Swap Fork | N/A | `test/part1/module5/UniswapSwapFork.t.sol` | Full swap workflow, slippage protection, multi-hop swaps, price impact |
| Gas Optimization | `src/part1/module5/GasOptimization.sol` | `test/part1/module5/GasOptimization.t.sol` | Custom errors, storage packing, calldata vs memory, unchecked, loop optimization |
| Deployment Script | `script/DeploySimpleVault.s.sol` | N/A | Foundry scripts, vm.broadcast, env variables, multi-contract deployment |

#### Module 6: Proxy Patterns & Upgradeability

| Exercise | Scaffold | Tests | Concepts |
|----------|----------|-------|----------|
| UUPS Vault | `src/part1/module6/UUPSVault.sol` | `test/part1/module6/UUPSVault.t.sol` | UUPS pattern, V1→V2 upgrade, _authorizeUpgrade, storage persistence, reinitializer |
| Uninitialized Proxy | `src/part1/module6/UninitializedProxy.sol` | `test/part1/module6/UninitializedProxy.t.sol` | Proxy attack vectors, initializer modifier, _disableInitializers, reinitializer(n) |
| Storage Collision | `src/part1/module6/StorageCollision.sol` | `test/part1/module6/StorageCollision.t.sol` | Storage layout compatibility, append-only upgrades, storage gaps, forge inspect |
| Beacon Proxy | `src/part1/module6/BeaconProxy.sol` | `test/part1/module6/BeaconProxy.t.sol` | Beacon pattern, multi-proxy upgrades, Aave aToken pattern, shared implementation |
