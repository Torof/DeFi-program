// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: SimpleDog — Liquidation Trigger + Dutch Auction
// ============================================================================
//
//  Build a simplified version of MakerDAO's Dog + Clipper — the liquidation
//  system that seizes unsafe vaults and sells collateral via Dutch auction.
//
//  What you'll learn:
//    - How Dog.bark() triggers liquidation by checking vault safety
//    - The grab() call that seizes collateral and creates system bad debt (sin)
//    - Liquidation penalty (chop) that protects the protocol
//    - Dutch auction mechanics: price starts high, decreases over time
//    - How take() lets liquidators buy collateral at the current price
//    - Partial fills and collateral refunds to vault owners
//
//  How liquidation works:
//    1. Keeper calls bark(ilk, usr) on an unsafe vault
//    2. Dog checks: ink × spot < art × rate (vault is undercollateralized)
//    3. Dog calls Vat.grab() to seize all collateral → creates sin at vow
//    4. Dutch auction starts: price begins at spot × buf, decreases linearly
//    5. Liquidator calls take(id, amt, max) to buy collateral at current price
//    6. Liquidator pays DAI (via Vat.move) and receives collateral (via Vat.slip)
//    7. When tab is fully covered, remaining collateral is refunded to vault owner
//
//  The economics:
//    - tab = art × rate × chop / WAD (total debt + liquidation penalty)
//    - The chop (e.g., 8%) protects the protocol from undercollateralization
//    - Auction starts above market → price decreases → liquidators buy when profitable
//    - Competition between liquidators ensures fair prices
//
//  Prerequisites: SimpleVat (Exercise 1) must be implemented first.
//                 bark() calls Vat.grab(), take() calls Vat.move() and Vat.slip().
//
//  Run:
//    forge test --match-contract SimpleDogTest -vvv
//
// ============================================================================

/// @notice Interface for Vat functions used by the Dog.
interface IVatForDog {
    function ilks(bytes32) external view returns (
        uint256 Art,
        uint256 rate,
        uint256 spot,
        uint256 line,
        uint256 dust
    );
    function urns(bytes32, address) external view returns (
        uint256 ink,
        uint256 art
    );
    function grab(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) external;
    function move(address src, address dst, uint256 rad) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
}

/// @notice Thrown when a non-authorized address calls a restricted function.
error NotAuthorized();

/// @notice Thrown when trying to liquidate a vault that is still safe.
error VaultIsSafe();

/// @notice Thrown when the auction has expired (price reached zero).
error AuctionExpired();

/// @notice Thrown when the current auction price exceeds the liquidator's max.
error PriceTooHigh();

/// @notice Thrown when referencing a non-existent auction.
error AuctionNotFound();

/// @notice Simplified Dog + Clipper — liquidation trigger and Dutch auction.
/// @dev Exercise for Module 6: Stablecoins & CDPs.
///      Students implement: bark(), take().
///      Pre-built: structs, state, auth, file, price().
contract SimpleDog {
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    // ── Data structures ──────────────────────────────────────────────

    /// @notice Per-ilk liquidation configuration.
    struct IlkConfig {
        uint256 chop;   // Liquidation penalty  [WAD] e.g., 1.08e18 = 8%
        uint256 buf;    // Starting price buffer [RAY] e.g., 2e27 = 2× spot
    }

    /// @notice Active Dutch auction state.
    struct Sale {
        bytes32 ilk;    // Collateral type being auctioned
        uint256 tab;    // DAI to recover (debt + penalty)        [RAD]
        uint256 lot;    // Collateral remaining in auction        [WAD]
        address usr;    // Vault owner (for collateral refund)
        uint256 tic;    // Auction start timestamp
        uint256 top;    // Starting price (spot × buf / RAY)      [RAY]
    }

    // ── State ────────────────────────────────────────────────────────

    mapping(address => bool) public wards;
    mapping(bytes32 => IlkConfig) public ilks;
    mapping(uint256 => Sale) public sales;
    uint256 public kicks;   // Total auctions started (auction ID counter)
    uint256 public tail;    // Auction duration in seconds

    IVatForDog public immutable vat;
    address public immutable vow;

    // ── Auth ─────────────────────────────────────────────────────────

    modifier auth() {
        if (!wards[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address vat_, address vow_) {
        vat = IVatForDog(vat_);
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

    /// @notice Set per-ilk liquidation parameters.
    /// @param ilk The collateral type.
    /// @param what The parameter name ("chop" or "buf").
    /// @param data The new value.
    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "chop") ilks[ilk].chop = data;
        else if (what == "buf") ilks[ilk].buf = data;
        else revert("unrecognized param");
    }

    /// @notice Set global liquidation parameters.
    /// @param what The parameter name ("tail").
    /// @param data The new value.
    function file(bytes32 what, uint256 data) external auth {
        if (what == "tail") tail = data;
        else revert("unrecognized param");
    }

    // ── Pre-built: Linear price decrease ─────────────────────────────

    /// @notice Compute the current auction price (linear decrease).
    /// @dev Price starts at `top` and decreases linearly to 0 over `tail` seconds.
    ///      This is a simplified version of MakerDAO's Abacus (LinearDecrease).
    ///
    ///      price = top × (tail - elapsed) / tail
    ///
    ///      Example with top = 1800 RAY, tail = 3600s:
    ///        t=0:    1800 RAY (starting price)
    ///        t=900:  1350 RAY (25% elapsed)
    ///        t=1800:  900 RAY (50% elapsed)
    ///        t=3600:    0 RAY (expired)
    ///
    /// @param top The starting auction price [RAY].
    /// @param tic The auction start timestamp.
    /// @return The current price [RAY], or 0 if expired.
    function price(uint256 top, uint256 tic) public view returns (uint256) {
        uint256 elapsed = block.timestamp - tic;
        if (elapsed >= tail) return 0;
        return top * (tail - elapsed) / tail;
    }

    // =============================================================
    //  TODO 1: Implement bark — trigger liquidation of an unsafe vault
    // =============================================================
    /// @notice Liquidate an unsafe vault by seizing its collateral.
    /// @dev Anyone can call this (no auth) — liquidating unsafe vaults is
    ///      always beneficial for system health. Keepers monitor vaults and
    ///      call bark() when they detect undercollateralization.
    ///
    /// Steps:
    ///   1. Read the vault state from the Vat:
    ///      (uint256 ink, uint256 art) = vat.urns(ilk, usr)
    ///
    ///   2. Read the ilk parameters from the Vat:
    ///      (, uint256 rate, uint256 spot,,) = vat.ilks(ilk)
    ///
    ///   3. Check that the vault is unsafe:
    ///      if (ink * spot >= art * rate) revert VaultIsSafe()
    ///      Both sides are in RAD: WAD × RAY = RAD
    ///
    ///   4. Load the liquidation config:
    ///      IlkConfig memory config = ilks[ilk]
    ///
    ///   5. Compute the tab (total DAI to recover, including penalty):
    ///      uint256 tab_ = art * rate * config.chop / WAD
    ///      → art × rate = actual debt [RAD], × chop / WAD applies the penalty
    ///      Example: 10,000 DAI debt × 1.08 chop = 10,800 DAI to recover
    ///
    ///   6. Call Vat.grab() to seize the vault:
    ///      vat.grab(ilk, usr, address(this), vow, -int256(ink), -int256(art))
    ///      → usr:           vault owner (collateral/debt seized from)
    ///      → address(this): Dog receives the seized collateral (gem)
    ///      → vow:           receives the sin (bad debt)
    ///      → -ink:          all collateral removed
    ///      → -art:          all debt removed
    ///
    ///   7. Create the auction:
    ///      id = ++kicks;
    ///      sales[id] = Sale({
    ///          ilk:  ilk,
    ///          tab:  tab_,
    ///          lot:  ink,
    ///          usr:  usr,
    ///          tic:  block.timestamp,
    ///          top:  spot * config.buf / RAY
    ///      });
    ///
    ///   8. Return the auction id
    ///
    /// See: Module 6 — "Liquidation 2.0: Dutch Auctions"
    ///
    /// @param ilk The collateral type.
    /// @param usr The vault owner to liquidate.
    /// @return id The auction ID.
    function bark(bytes32 ilk, address usr) external returns (uint256 id) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement take — buy collateral from a Dutch auction
    // =============================================================
    /// @notice Buy collateral from an active auction at the current price.
    /// @dev Liquidators call this to purchase seized collateral. The price
    ///      decreases over time (Dutch auction), so liquidators wait until
    ///      the price is attractive enough for them.
    ///
    /// Steps:
    ///   1. Load the Sale storage pointer:
    ///      Sale storage sale = sales[id]
    ///
    ///   2. Verify auction exists:
    ///      if (sale.tic == 0) revert AuctionNotFound()
    ///
    ///   3. Compute the current price:
    ///      uint256 price_ = price(sale.top, sale.tic)
    ///      if (price_ == 0) revert AuctionExpired()
    ///      if (price_ > max) revert PriceTooHigh()
    ///
    ///   4. Compute the collateral slice and DAI owed:
    ///      uint256 slice = amt < sale.lot ? amt : sale.lot
    ///      uint256 owe = slice * price_     // WAD × RAY = RAD
    ///
    ///   5. If owe exceeds the remaining tab, cap it:
    ///      if (owe > sale.tab) {
    ///          owe = sale.tab;
    ///          slice = owe / price_;          // RAD / RAY = WAD
    ///      }
    ///
    ///   6. Update auction state:
    ///      sale.tab -= owe
    ///      sale.lot -= slice
    ///
    ///   7. Collect DAI from the liquidator:
    ///      vat.move(msg.sender, vow, owe)
    ///      → Transfers internal dai from liquidator to vow
    ///      → Liquidator must have called vat.hope(address(dog)) first
    ///
    ///   8. Transfer collateral to the liquidator:
    ///      vat.slip(sale.ilk, address(this), -int256(slice))  // debit Dog
    ///      vat.slip(sale.ilk, msg.sender, int256(slice))      // credit liquidator
    ///
    ///   9. If auction is complete (tab == 0 or lot == 0):
    ///      a. Refund any remaining collateral to vault owner:
    ///         if (sale.lot > 0) {
    ///             vat.slip(sale.ilk, address(this), -int256(sale.lot))
    ///             vat.slip(sale.ilk, sale.usr, int256(sale.lot))
    ///         }
    ///      b. Delete the auction: delete sales[id]
    ///
    /// Key insight: The liquidator buys collateral below market price.
    /// The protocol recovers DAI to cover the bad debt (sin) from bark().
    /// Any excess collateral goes back to the vault owner — liquidation
    /// doesn't mean losing everything.
    ///
    /// See: Module 6 — "Dutch Auction Walkthrough"
    ///
    /// @param id The auction ID.
    /// @param amt Maximum collateral to buy [WAD].
    /// @param max Maximum price willing to pay [RAY] (slippage protection).
    function take(uint256 id, uint256 amt, uint256 max) external {
        revert("Not implemented");
    }
}
