// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: SimpleJug — Stability Fee Accumulator
// ============================================================================
//
//  Build a simplified version of MakerDAO's Jug — the module that compounds
//  stability fees over time and updates the Vat's rate accumulator.
//
//  What you'll learn:
//    - rpow(): exponentiation by squaring in assembly — O(log n) algorithm
//    - Per-second rate compounding for continuous fee accrual
//    - How fold() distributes accrued fees as new dai (protocol revenue)
//    - The connection between per-second rates and annual percentages
//    - Why this exact pattern appears in every DeFi rate accumulator
//
//  How stability fees work:
//    - Governance sets a per-second rate `duty` (e.g., 1.000000001547... RAY for 5% annual)
//    - Anyone can call drip(ilk) at any time
//    - drip() computes: duty ^ seconds_elapsed → rate multiplier
//    - New rate = old_rate × multiplier → calls Vat.fold() with the delta
//    - Every vault's actual debt (art × rate) automatically increases
//    - The new dai goes to `vow` (protocol surplus) as revenue
//
//  The math:
//    5% annual → per_second_rate = 1.05 ^ (1/31,557,600) ≈ 1.000000001547...
//    After 1 year: rpow(duty, 31557600, RAY) ≈ 1.05 RAY
//    After 2 years: rpow(duty, 63115200, RAY) ≈ 1.1025 RAY (compounds!)
//
//  Prerequisites: SimpleVat (Exercise 1) must be implemented first.
//                 The Jug calls Vat.fold() to update rates.
//
//  Run:
//    forge test --match-contract SimpleJugTest -vvv
//
// ============================================================================

/// @notice Interface for reading Vat ilk state and updating rates.
interface IVatForJug {
    function ilks(bytes32) external view returns (
        uint256 Art,
        uint256 rate,
        uint256 spot,
        uint256 line,
        uint256 dust
    );
    function fold(bytes32 ilk, address u, int256 rate) external;
}

/// @notice Thrown when a non-authorized address calls a restricted function.
error NotAuthorized();

/// @notice Simplified MakerDAO Jug — stability fee accumulator.
/// @dev Exercise for Module 6: Stablecoins & CDPs.
///      Students implement: rpow(), drip().
///      Pre-built: struct, state, auth, init, file.
contract SimpleJug {
    uint256 constant RAY = 10 ** 27;

    // ── Data structures ──────────────────────────────────────────────

    /// @notice Per-ilk stability fee configuration.
    struct IlkData {
        uint256 duty;   // Per-second stability fee rate  [RAY]
        uint256 rho;    // Timestamp of last drip
    }

    // ── State ────────────────────────────────────────────────────────

    mapping(address => bool) public wards;
    mapping(bytes32 => IlkData) public ilks;

    IVatForJug public immutable vat;
    address public immutable vow;

    // ── Auth ─────────────────────────────────────────────────────────

    modifier auth() {
        if (!wards[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address vat_, address vow_) {
        vat = IVatForJug(vat_);
        vow = vow_;
        wards[msg.sender] = true;
    }

    function rely(address usr) external auth {
        wards[usr] = true;
    }

    function deny(address usr) external auth {
        wards[usr] = false;
    }

    // ── Admin: Configure parameters ──────────────────────────────────

    /// @notice Initialize a collateral type in the Jug.
    /// @dev Sets rho to current timestamp and duty to RAY (1.0 = no fees).
    ///      Must be called before drip(). Separate from Vat.init().
    function init(bytes32 ilk) external auth {
        require(ilks[ilk].rho == 0, "already initialized");
        ilks[ilk].duty = RAY;
        ilks[ilk].rho = block.timestamp;
    }

    /// @notice Set the per-second stability fee rate for a collateral type.
    /// @param ilk The collateral type.
    /// @param what The parameter name (only "duty" is supported).
    /// @param data The new value (per-second rate in RAY).
    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "duty") ilks[ilk].duty = data;
        else revert("unrecognized param");
    }

    // =============================================================
    //  TODO 1: Implement rpow — exponentiation by squaring
    // =============================================================
    /// @notice Compute x^n in fixed-point arithmetic with base b.
    /// @dev This is THE key algorithm for per-second rate compounding.
    ///      Instead of multiplying x by itself n times (O(n) — millions of
    ///      gas for weeks of elapsed time), it uses binary decomposition
    ///      of the exponent to compute the result in O(log n) steps.
    ///
    ///      The insight: x^10 = x^8 × x^2 (use binary repr of exponent)
    ///        10 in binary = 1010
    ///        x^10 = x^(8+2) = x^8 × x^2
    ///        Only need to compute: x, x², x⁴, x⁸ (repeated squaring)
    ///        Then multiply together the powers where the bit is 1.
    ///
    ///      For MakerDAO: rpow(duty, seconds_elapsed, RAY)
    ///        duty ≈ 1.000000001547... RAY (5% annual per-second rate)
    ///        seconds_elapsed = 31,557,600 (one year)
    ///        log2(31,557,600) ≈ 25 iterations (instead of 31 million!)
    ///
    /// Implementation (assembly for gas efficiency):
    ///
    ///   1. Handle x = 0 edge case:
    ///      switch x
    ///      case 0 { z := mul(b, iszero(n)) }
    ///      → 0^0 = b (representing 1.0), 0^n = 0 for n > 0
    ///
    ///   2. For x > 0, enter the default block:
    ///      z := b               // result = 1.0 in fixed-point (base)
    ///
    ///   3. Loop while n > 0:
    ///      for {} n {} {
    ///
    ///        a. If n is odd (lowest bit is 1):
    ///           if mod(n, 2) { z := div(mul(z, x), b) }
    ///           → Multiply result by current x (fixed-point: z*x/b)
    ///
    ///        b. Square x for the next power:
    ///           x := div(mul(x, x), b)
    ///           → x = x² in fixed-point (x*x/b)
    ///
    ///        c. Shift exponent right (divide by 2):
    ///           n := div(n, 2)
    ///      }
    ///
    /// Example trace: rpow(2 RAY, 10, RAY) = 1024 RAY
    ///   z = RAY.  n=10(1010₂)
    ///   bit 0: n=10 even, skip.   x = 4 RAY.   n=5
    ///   bit 1: n=5 odd,  z=4 RAY. x = 16 RAY.  n=2
    ///   bit 2: n=2 even, skip.    x = 256 RAY.  n=1
    ///   bit 3: n=1 odd,  z=4×256/RAY = 1024 RAY.  n=0. Done!
    ///
    /// See: Module 6 — "rpow() — Exponentiation by Squaring"
    ///
    /// @param x The base (in fixed-point with precision b).
    /// @param n The exponent (unsigned integer, not fixed-point).
    /// @param b The fixed-point base (e.g., RAY = 10^27).
    /// @return z The result x^n in fixed-point with precision b.
    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement drip — compound stability fees
    // =============================================================
    /// @notice Compound accrued stability fees for a collateral type.
    /// @dev Anyone can call this (no auth). Accruing fees is always safe —
    ///      it only increases protocol revenue. Keepers or users typically
    ///      call drip() before interacting with a vault to ensure the rate
    ///      is up-to-date.
    ///
    /// Steps:
    ///   1. Load the IlkData (duty, rho) for this ilk
    ///   2. Read the current rate from the Vat:
    ///      (, uint256 prev,,,) = vat.ilks(ilk)
    ///
    ///   3. Compute the rate multiplier:
    ///      uint256 mul_ = rpow(duty, block.timestamp - rho, RAY)
    ///      → duty^elapsed_seconds (how much the rate grew)
    ///
    ///   4. Compute the new rate:
    ///      rate = mul_ * prev / RAY
    ///      → Apply the multiplier to the current rate
    ///      (this is RAY × RAY / RAY = RAY, preserving precision)
    ///
    ///   5. Compute the rate delta:
    ///      int256 drate = int256(rate) - int256(prev)
    ///      → How much the rate increased (positive)
    ///
    ///   6. Call vat.fold(ilk, vow, drate)
    ///      → Update the Vat's rate and generate new dai to vow
    ///
    ///   7. Update the timestamp:
    ///      ilks[ilk].rho = block.timestamp
    ///
    ///   8. Return the new rate
    ///
    /// Key insight: drip() doesn't touch any individual vault. It updates
    /// the global rate, which automatically increases every vault's actual
    /// debt (art × rate). The new dai goes to the protocol surplus (vow).
    ///
    /// Hint: `mul_ * prev / RAY` is the RAY multiplication pattern you'll
    ///       see everywhere in MakerDAO. It's equivalent to _rmul(mul_, prev).
    /// See: Module 6 — "Stability Fee Per-Second Rate"
    ///
    /// @param ilk The collateral type to drip.
    /// @return rate The new rate after compounding.
    function drip(bytes32 ilk) external returns (uint256 rate) {
        revert("Not implemented");
    }
}
