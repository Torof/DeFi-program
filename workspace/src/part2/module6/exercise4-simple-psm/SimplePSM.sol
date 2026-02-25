// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  EXERCISE: SimplePSM — Peg Stability Module
// ============================================================================
//
//  Build a simplified version of MakerDAO's PSM — the module that maintains
//  the stablecoin's $1 peg by allowing 1:1 swaps with approved stablecoins.
//
//  What you'll learn:
//    - How the PSM maintains the peg through arbitrage incentives
//    - Decimal conversion between different-precision tokens (USDC 6 → DAI 18)
//    - Fee mechanics: tin (fee in) and tout (fee out)
//    - Why the PSM is controversial (centralization vs peg stability)
//
//  How the PSM works:
//    - If DAI > $1: arbitrageurs swap USDC → DAI at 1:1, sell DAI at premium → profit
//      This increases DAI supply, pushing the price back down to $1.
//    - If DAI < $1: arbitrageurs swap DAI → USDC at 1:1, buy cheap DAI → profit
//      This decreases DAI supply, pushing the price back up to $1.
//
//  The economics:
//    - sellGem: User deposits USDC → receives DAI (minus tin fee)
//    - buyGem: User pays DAI (plus tout fee) → receives USDC
//    - Fees go to vow (protocol surplus) as revenue
//    - The PSM holds USDC reserves to back the minted DAI
//
//  Decimal conversion:
//    USDC uses 6 decimals: 1 USDC = 1,000,000 (1e6)
//    DAI uses 18 decimals:  1 DAI  = 1,000,000,000,000,000,000 (1e18)
//    to18ConversionFactor = 10^(18-6) = 10^12
//    1 USDC (1e6) × 10^12 = 1e18 = 1 DAI ✓
//
//  This exercise is independent — no SimpleVat dependency required.
//
//  Run:
//    forge test --match-contract SimplePSMTest -vvv
//
// ============================================================================

/// @notice Interface for the stablecoin with authorized mint/burn.
interface IStablecoinForPSM {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/// @notice Thrown when a non-authorized address calls a restricted function.
error NotAuthorized();

/// @notice Simplified Peg Stability Module — 1:1 stablecoin swaps with fees.
/// @dev Exercise for Module 6: Stablecoins & CDPs.
///      Students implement: sellGem(), buyGem().
///      Pre-built: state, auth, file, constructor.
contract SimplePSM {
    using SafeERC20 for IERC20;

    uint256 constant WAD = 10 ** 18;

    // ── State ────────────────────────────────────────────────────────

    mapping(address => bool) public wards;

    IERC20 public immutable gem;                    // External stablecoin (e.g., USDC)
    IStablecoinForPSM public immutable dai;         // Minted stablecoin (18 decimals)
    address public immutable vow;                   // Protocol surplus (receives fees)
    uint256 public immutable to18ConversionFactor;  // 10^(18 - gem_decimals)

    uint256 public tin;     // Fee for selling gem (USDC → DAI)  [WAD]  e.g., 0.01e18 = 1%
    uint256 public tout;    // Fee for buying gem  (DAI → USDC)  [WAD]  e.g., 0.01e18 = 1%

    // ── Auth ─────────────────────────────────────────────────────────

    modifier auth() {
        if (!wards[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address gem_, address dai_, address vow_, uint8 gemDecimals_) {
        gem = IERC20(gem_);
        dai = IStablecoinForPSM(dai_);
        vow = vow_;
        to18ConversionFactor = 10 ** (18 - gemDecimals_);
        wards[msg.sender] = true;
    }

    function rely(address usr) external auth {
        wards[usr] = true;
    }

    function deny(address usr) external auth {
        wards[usr] = false;
    }

    // ── Admin: Configure parameters ──────────────────────────────────

    /// @notice Set PSM fee parameters.
    /// @param what The parameter name ("tin" or "tout").
    /// @param data The new fee value [WAD]. 0 = no fee, 0.01e18 = 1%.
    function file(bytes32 what, uint256 data) external auth {
        if (what == "tin") tin = data;
        else if (what == "tout") tout = data;
        else revert("unrecognized param");
    }

    // =============================================================
    //  TODO 1: Implement sellGem — deposit USDC, receive stablecoin
    // =============================================================
    /// @notice Swap external stablecoin (e.g., USDC) for minted stablecoin (DAI).
    /// @dev Anyone can call this. The user must have approved this contract
    ///      to spend their gem tokens (USDC) via gem.approve(address(psm), amount).
    ///
    /// Steps:
    ///   1. Convert gem amount to 18-decimal DAI amount:
    ///      uint256 gemAmt18 = gemAmt * to18ConversionFactor
    ///      → Example: 1000 USDC (1000e6) × 10^12 = 1000e18 (1000 DAI)
    ///
    ///   2. Compute the fee:
    ///      uint256 fee = gemAmt18 * tin / WAD
    ///      → Example: 1000e18 × 0.01e18 / 1e18 = 10e18 (10 DAI fee)
    ///
    ///   3. Transfer gem from the caller to this contract:
    ///      gem.safeTransferFrom(msg.sender, address(this), gemAmt)
    ///      → PSM holds the USDC as reserves backing the minted DAI
    ///
    ///   4. Mint stablecoin to the recipient (minus fee):
    ///      dai.mint(usr, gemAmt18 - fee)
    ///      → User receives: 1000 - 10 = 990 DAI
    ///
    ///   5. If fee > 0, mint fee to vow (protocol revenue):
    ///      if (fee > 0) dai.mint(vow, fee)
    ///      → Total minted = gemAmt18 (split: user + vow)
    ///
    /// See: Module 6 — "Peg Stability Module (PSM)"
    ///
    /// @param usr The address to receive the minted stablecoin.
    /// @param gemAmt The amount of gem to sell (in gem's native decimals, e.g., 6 for USDC).
    function sellGem(address usr, uint256 gemAmt) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement buyGem — pay stablecoin, receive USDC
    // =============================================================
    /// @notice Swap minted stablecoin (DAI) for external stablecoin (e.g., USDC).
    /// @dev Anyone can call this. The PSM burns stablecoin from the caller
    ///      directly (no approval needed — PSM is authorized to burn).
    ///
    /// Steps:
    ///   1. Convert gem amount to 18-decimal DAI amount:
    ///      uint256 gemAmt18 = gemAmt * to18ConversionFactor
    ///      → Example: 1000 USDC (1000e6) × 10^12 = 1000e18 (1000 DAI worth)
    ///
    ///   2. Compute the fee:
    ///      uint256 fee = gemAmt18 * tout / WAD
    ///      → Example: 1000e18 × 0.01e18 / 1e18 = 10e18 (10 DAI fee)
    ///
    ///   3. Burn stablecoin from the caller (base amount + fee):
    ///      dai.burn(msg.sender, gemAmt18 + fee)
    ///      → User pays: 1000 + 10 = 1010 DAI total
    ///      → Net supply change: -1010 + 10 (fee mint) = -1000 (matches USDC leaving)
    ///
    ///   4. If fee > 0, mint fee to vow (protocol revenue):
    ///      if (fee > 0) dai.mint(vow, fee)
    ///
    ///   5. Transfer gem to the recipient:
    ///      gem.safeTransfer(usr, gemAmt)
    ///      → User receives: 1000 USDC
    ///
    /// See: Module 6 — "Peg Stability Module (PSM)"
    ///
    /// @param usr The address to receive the gem tokens (USDC).
    /// @param gemAmt The amount of gem to buy (in gem's native decimals, e.g., 6 for USDC).
    function buyGem(address usr, uint256 gemAmt) external {
        revert("Not implemented");
    }
}
