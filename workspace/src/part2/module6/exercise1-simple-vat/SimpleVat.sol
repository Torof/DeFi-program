// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: SimpleVat — The Core CDP Accounting Engine
// ============================================================================
//
//  Build a simplified version of MakerDAO's Vat — the heart of the CDP system.
//  The Vat is a single-contract ledger that tracks ALL collateral, debt, and
//  stablecoin balances. Every operation in MakerDAO ultimately reads or writes
//  the Vat.
//
//  What you'll learn:
//    - The normalized debt pattern: actual_debt = art × rate
//    - The vault safety check: ink × spot ≥ art × rate
//    - How frob() atomically modifies collateral + debt with signed deltas
//    - Why grab() exists separately from frob() (liquidation bypasses safety checks)
//    - How fold() updates rates globally without touching individual vaults
//
//  MakerDAO naming glossary:
//    ilk  = collateral type (e.g., "ETH-A")
//    urn  = individual vault (per user, per ilk)
//    ink  = locked collateral (WAD)
//    art  = normalized debt (WAD) — multiply by rate to get actual debt
//    gem  = unlocked collateral (WAD) — deposited but not locked in a vault
//    dai  = internal stablecoin balance (RAD)
//    sin  = system bad debt (RAD) — created during liquidation
//    rate = stability fee accumulator (RAY) — grows over time via Jug.drip()
//    spot = price with safety margin (RAY) — oracle_price / liquidation_ratio
//    line = per-ilk debt ceiling (RAD)
//    Line = global debt ceiling (RAD)
//    dust = minimum vault debt (RAD)
//    dink = delta ink (int256) — positive = lock, negative = unlock
//    dart = delta art (int256) — positive = borrow, negative = repay
//
//  Precision scales:
//    WAD = 10^18  (token amounts, ink, art)
//    RAY = 10^27  (rates, ratios — rate, spot)
//    RAD = 10^45  (internal DAI accounting — WAD × RAY = RAD)
//
//  Run:
//    forge test --match-contract SimpleVatTest -vvv
//
// ============================================================================

import {VatMath} from "../shared/VatMath.sol";

/// @notice Thrown when a non-authorized address calls a restricted function.
error NotAuthorized();

/// @notice Thrown when the vault is unsafe after a frob operation.
error VaultUnsafe();

/// @notice Thrown when the per-ilk debt ceiling would be exceeded.
error CeilingExceeded();

/// @notice Thrown when the global debt ceiling would be exceeded.
error GlobalCeilingExceeded();

/// @notice Thrown when the vault debt is below the dust threshold (and not zero).
error DustViolation();

/// @notice Simplified MakerDAO Vat — the core CDP accounting engine.
/// @dev Exercise for Module 6: Stablecoins & CDPs.
///      Students implement: frob(), fold(), grab().
///      Pre-built: structs, state, auth, init, file, slip, move, heal.
contract SimpleVat {
    using VatMath for uint256;

    // ── Precision constants ──────────────────────────────────────────
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    // ── Data structures ──────────────────────────────────────────────

    /// @notice Collateral type parameters.
    struct Ilk {
        uint256 Art;    // Total normalized debt                  [WAD]
        uint256 rate;   // Stability fee accumulator              [RAY]
        uint256 spot;   // Price with safety margin (price / LR)  [RAY]
        uint256 line;   // Per-ilk debt ceiling                   [RAD]
        uint256 dust;   // Minimum vault debt                     [RAD]
    }

    /// @notice Individual vault state.
    struct Urn {
        uint256 ink;    // Locked collateral  [WAD]
        uint256 art;    // Normalized debt     [WAD]
    }

    // ── State ────────────────────────────────────────────────────────

    mapping(address => bool) public wards;                              // authorized addresses
    mapping(bytes32 => Ilk) public ilks;                                // collateral types
    mapping(bytes32 => mapping(address => Urn)) public urns;            // vaults
    mapping(bytes32 => mapping(address => uint256)) public gem;         // unlocked collateral [WAD]
    mapping(address => uint256) public dai;                             // internal stablecoin  [RAD]
    mapping(address => uint256) public sin;                             // system bad debt      [RAD]
    uint256 public debt;                                                // total system debt    [RAD]
    uint256 public vice;                                                // total system sin     [RAD]
    uint256 public Line;                                                // global debt ceiling  [RAD]
    mapping(address => mapping(address => bool)) public can;            // transfer permissions

    // ── Auth ─────────────────────────────────────────────────────────

    modifier auth() {
        if (!wards[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor() {
        wards[msg.sender] = true;
    }

    /// @notice Grant authorization.
    function rely(address usr) external auth {
        wards[usr] = true;
    }

    /// @notice Revoke authorization.
    function deny(address usr) external auth {
        wards[usr] = false;
    }

    /// @notice Allow another address to move your dai/gem.
    function hope(address usr) external {
        can[msg.sender][usr] = true;
    }

    /// @notice Revoke transfer permission.
    function nope(address usr) external {
        can[msg.sender][usr] = false;
    }

    /// @notice Check if `bit` can act on behalf of `usr`.
    function wish(address usr, address bit) internal view returns (bool) {
        return usr == bit || can[usr][bit];
    }

    // ── Admin: Configure parameters ──────────────────────────────────

    /// @notice Initialize a new collateral type with rate = 1 RAY.
    function init(bytes32 ilk) external auth {
        require(ilks[ilk].rate == 0, "already initialized");
        ilks[ilk].rate = RAY;
    }

    /// @notice Set a per-ilk parameter (spot, line, dust).
    /// @param ilk The collateral type.
    /// @param what The parameter name ("spot", "line", or "dust").
    /// @param data The new value.
    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "spot") ilks[ilk].spot = data;
        else if (what == "line") ilks[ilk].line = data;
        else if (what == "dust") ilks[ilk].dust = data;
        else revert("unrecognized param");
    }

    /// @notice Set the global debt ceiling.
    function file(bytes32 what, uint256 data) external auth {
        if (what == "Line") Line = data;
        else revert("unrecognized param");
    }

    // ── Pre-built helpers ────────────────────────────────────────────

    /// @notice Modify a user's unlocked collateral balance.
    /// @dev Called by GemJoin when collateral is deposited/withdrawn.
    function slip(bytes32 ilk, address usr, int256 wad) external auth {
        gem[ilk][usr] = gem[ilk][usr]._add(wad);
    }

    /// @notice Transfer internal dai between addresses.
    /// @dev Called by DaiJoin to convert internal dai ↔ external stablecoin.
    function move(address src, address dst, uint256 rad) external {
        require(wish(src, msg.sender), "not allowed");
        dai[src] -= rad;
        dai[dst] += rad;
    }

    /// @notice Cancel equal amounts of dai and sin (system surplus vs bad debt).
    /// @dev Called after auctions recover DAI to clear the sin created by grab().
    function heal(uint256 rad) external {
        dai[msg.sender] -= rad;
        sin[msg.sender] -= rad;
        debt -= rad;
        vice -= rad;
    }

    // =============================================================
    //  TODO 1: Implement frob — the fundamental vault operation
    // =============================================================
    /// @notice Lock/unlock collateral and generate/repay stablecoins.
    /// @dev This is THE core CDP function. It atomically modifies both the
    ///      collateral (ink) and debt (art) of the caller's vault.
    ///
    /// Steps:
    ///   1. Load the Ilk and Urn structs (storage pointers for gas efficiency)
    ///   2. Require that ilk.rate != 0 (ilk must be initialized via init())
    ///
    ///   --- Update vault state ---
    ///   3. Update urn.ink: urn.ink = urn.ink._add(dink)
    ///   4. Update urn.art: urn.art = urn.art._add(dart)
    ///   5. Update ilk.Art: ilk.Art = ilk.Art._add(dart)
    ///
    ///   --- Compute dai delta ---
    ///   6. Compute dtab (the RAD amount of dai generated/repaid):
    ///      int256 dtab = VatMath._mul(ilk.rate, dart)
    ///      This is: rate (RAY) × dart (WAD) = dtab (RAD)
    ///
    ///   --- Update global balances ---
    ///   7. Update dai[msg.sender]:
    ///      dai[msg.sender] = dai[msg.sender]._add(dtab)
    ///   8. Update total system debt:
    ///      debt = debt._add(dtab)
    ///
    ///   --- Move collateral ---
    ///   9. If dink > 0: debit gem (user locks collateral from their gem balance)
    ///      gem[ilk][msg.sender] -= uint256(dink)
    ///   10. If dink < 0: credit gem (user unlocks collateral back to gem balance)
    ///       gem[ilk][msg.sender] += uint256(-dink)
    ///
    ///   --- Safety checks (only when increasing risk) ---
    ///   11. bool riskier = (dart > 0 || dink < 0)
    ///       Only check safety when the vault is becoming riskier
    ///       (adding debt or removing collateral)
    ///
    ///   12. If riskier:
    ///       a. Vault safety: require urn.ink * ilk.spot >= urn.art * ilk.rate
    ///          (revert VaultUnsafe if not)
    ///       b. Per-ilk ceiling: require ilk.Art * ilk.rate <= ilk.line
    ///          (revert CeilingExceeded if not)
    ///       c. Global ceiling: require debt <= Line
    ///          (revert GlobalCeilingExceeded if not)
    ///
    ///   --- Dust check ---
    ///   13. If urn.art > 0: require urn.art * ilk.rate >= ilk.dust
    ///       (revert DustViolation if vault has debt below minimum)
    ///       Note: art == 0 is always OK (fully repaid vault)
    ///
    /// Hint: Use storage pointers for Ilk and Urn to avoid redundant SLOADs:
    ///   Ilk storage i = ilks[ilk];
    ///   Urn storage u = urns[ilk][msg.sender];
    /// See: Module 6 — "MakerDAO Contract Architecture" (frob walkthrough)
    ///
    /// @param ilk The collateral type identifier.
    /// @param dink Delta collateral: positive = lock, negative = unlock.
    /// @param dart Delta normalized debt: positive = borrow, negative = repay.
    function frob(bytes32 ilk, int256 dink, int256 dart) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement fold — update the stability fee accumulator
    // =============================================================
    /// @notice Update the rate accumulator for a collateral type.
    /// @dev Called by SimpleJug.drip() to apply accrued stability fees.
    ///      This function updates the rate for an ilk and distributes the
    ///      accrued interest as new dai to a designated recipient (typically
    ///      a protocol surplus address).
    ///
    /// Steps:
    ///   1. Load the Ilk storage pointer
    ///   2. Update the rate: ilk.rate = ilk.rate._add(drate)
    ///   3. Compute the dai delta for the rate change:
    ///      int256 drad = VatMath._mul(ilk.Art, drate)
    ///      This is: Art (total normalized debt, WAD) × drate (RAY) = drad (RAD)
    ///      Meaning: the rate increase generates new dai proportional to total debt.
    ///   4. Credit the new dai to the recipient:
    ///      dai[u] = dai[u]._add(drad)
    ///   5. Update total system debt:
    ///      debt = debt._add(drad)
    ///
    /// Key insight: fold() doesn't touch any individual vault. By increasing
    /// the global `rate`, every vault's actual debt (art × rate) automatically
    /// increases. The new dai goes to `u` (protocol surplus) as revenue.
    /// See: Module 6 — "Stability Fee Per-Second Rate" and "rpow()"
    ///
    /// @param ilk The collateral type.
    /// @param u The recipient of the newly generated dai (protocol surplus).
    /// @param drate The rate delta (RAY). Positive = fees accrued.
    function fold(bytes32 ilk, address u, int256 drate) external auth {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement grab — seize collateral for liquidation
    // =============================================================
    /// @notice Forcefully seize collateral and debt from an unsafe vault.
    /// @dev Called by SimpleDog.bark() during liquidation. Unlike frob(),
    ///      grab() bypasses all safety checks — the vault IS unsafe, that's
    ///      why it's being liquidated. It creates `sin` (bad debt) that must
    ///      be recovered via auction.
    ///
    /// Steps:
    ///   1. Load the Ilk and Urn storage pointers
    ///      Urn storage urn = urns[ilk][u];
    ///      Ilk storage i = ilks[ilk];
    ///   2. Update urn.ink: urn.ink = urn.ink._add(dink)
    ///      (dink is negative — collateral is being seized)
    ///   3. Update urn.art: urn.art = urn.art._add(dart)
    ///      (dart is negative — debt is being removed from the vault)
    ///   4. Update ilk.Art: i.Art = i.Art._add(dart)
    ///
    ///   --- Move seized collateral ---
    ///   5. Credit the seized collateral to `v` (the liquidation module):
    ///      gem[ilk][v] += uint256(-dink)
    ///      (dink is negative, so -dink is positive)
    ///
    ///   --- Create system bad debt ---
    ///   6. Compute dtab: int256 dtab = VatMath._mul(i.rate, dart)
    ///      (rate × dart = RAD amount of debt being moved)
    ///   7. Credit sin to `w` (the protocol surplus/debt address):
    ///      sin[w] = sin[w]._add(-dtab)
    ///      (dtab is negative since dart < 0, so -dtab is positive)
    ///   8. Update vice: vice = vice._add(-dtab)
    ///      (total system sin increases)
    ///
    /// Key insight: grab() creates sin (bad debt) equal to the seized debt.
    /// The auction will recover dai; when dai is recovered, heal() cancels
    /// equal amounts of dai and sin. If the auction doesn't recover enough,
    /// the remaining sin is protocol-level bad debt.
    /// See: Module 6 — "Liquidation 2.0: Dutch Auctions"
    ///
    /// @param ilk The collateral type.
    /// @param u The vault owner (whose collateral/debt is being seized).
    /// @param v The recipient of seized collateral (liquidation module).
    /// @param w The recipient of sin / bad debt (protocol surplus address).
    /// @param dink Delta collateral (negative — collateral being seized).
    /// @param dart Delta normalized debt (negative — debt being removed).
    function grab(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) external auth {
        revert("Not implemented");
    }
}
