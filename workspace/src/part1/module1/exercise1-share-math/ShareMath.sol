// SPDX-License-Identifier: MIT
// Note: Uses ^0.8.19 because custom operators were introduced in 0.8.19.
// TransientGuard (Exercise 2) uses ^0.8.28 for the `transient` keyword.
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ============================================================================
// EXERCISE: Vault Share Calculator
//
// The exact math that underpins every ERC-4626 vault, lending pool, and LP
// token in DeFi. Fill in the TODOs to make all tests pass.
//
// Concepts exercised:
//   - User-Defined Value Types (UDVTs)
//   - Custom operators via free functions + `using for global`
//   - Checked/unchecked arithmetic
//   - Custom errors
//   - abi.encodeCall (tested in ShareMath.t.sol)
//
// Run: forge test --match-contract ShareMathTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroAssets();
error ZeroShares();
error ZeroTotalSupply();
error ZeroTotalAssets();

// --- User-Defined Value Types ---
type Assets is uint256;
type Shares is uint256;

// --- Operator registrations ---
// These bind the free functions below as operators on the UDVTs.
// The functions need your implementation to work correctly.
using {addAssets as +, subAssets as -} for Assets global;
using {addShares as +, subShares as -} for Shares global;

// =============================================================
//  TODO 1: Implement Assets arithmetic operators
// =============================================================
// Hint: Assets.unwrap(a) gives you the raw uint256,
//       Assets.wrap(x) creates an Assets from a uint256.
// See: Module 1 > User-Defined Value Types (#user-defined-value-types)

function addAssets(Assets a, Assets b) pure returns (Assets) {
    return Assets.wrap(Assets.unwrap(a) + Assets.unwrap(b));
}

function subAssets(Assets a, Assets b) pure returns (Assets) {
    return Assets.wrap(Assets.unwrap(a) - Assets.unwrap(b));
}

// =============================================================
//  TODO 2: Implement Shares arithmetic operators
// =============================================================
// See: Module 1 > User-Defined Value Types (#user-defined-value-types)

function addShares(Shares a, Shares b) pure returns (Shares) {
    return Shares.wrap( Shares.unwrap(a) + Shares.unwrap(b));
}

function subShares(Shares a, Shares b) pure returns (Shares) {
    return Shares.wrap( Shares.unwrap(a) - Shares.unwrap(b));
}

// =============================================================
//  TODO 3: Implement toShares conversion
// =============================================================
/// @notice Convert an asset amount to shares.
/// @dev Formula: shares = (assets * totalSupply) / totalAssets
///      On first deposit (totalSupply == 0), shares = assets (1:1)
///      Rounding: round DOWN (favors the vault, not the depositor)
// See: Module 1 > Checked Arithmetic (#checked-arithmetic)
function toShares(
    Assets assets,
    Assets totalAssets,
    Shares totalSupply
) pure returns (Shares) {
    // Steps:
    // 1. Revert with ZeroAssets() if assets is zero
    // 2. If totalSupply is zero (first deposit): return assets as shares (1:1)
    // 3. Revert with ZeroTotalAssets() if totalAssets is zero
    //    (shares exist but no assets = broken vault state, division by zero)
    // 4. shares = (assets * totalSupply) / totalAssets
    //    - Solidity integer division already rounds down
    require( Assets.unwrap(assets) > 0, ZeroAssets());
    if(Shares.unwrap(totalSupply) == 0) return Shares.wrap(Assets.unwrap(assets));
    require(Assets.unwrap(totalAssets) > 0, ZeroTotalAssets());

    return Shares.wrap(Math.mulDiv(Assets.unwrap(assets), Shares.unwrap(totalSupply), Assets.unwrap(totalAssets)));
    // return Shares.wrap((Assets.unwrap(assets) * Shares.unwrap(totalSupply)) / Assets.unwrap(totalAssets));
}

// =============================================================
//  TODO 4: Implement toAssets conversion
// =============================================================
/// @notice Convert a share amount to assets.
/// @dev Formula: assets = (shares * totalAssets) / totalSupply
///      Rounding: round DOWN (favors the vault, not the withdrawer)
// See: Module 1 > Checked Arithmetic (#checked-arithmetic)
function toAssets(
    Shares shares,
    Assets totalAssets,
    Shares totalSupply
) pure returns (Assets) {
    // Steps:
    // 1. Revert with ZeroShares() if shares is zero
    // 2. Revert with ZeroTotalSupply() if totalSupply is zero
    // 3. assets = (shares * totalAssets) / totalSupply
    require(Shares.unwrap(shares) > 0, ZeroShares());
    require( Shares.unwrap(totalSupply) > 0, ZeroTotalSupply());

    return Assets.wrap(Math.mulDiv(Shares.unwrap(shares), Assets.unwrap(totalAssets), Shares.unwrap(totalSupply)));
    // return Assets.wrap((Shares.unwrap(shares) * Assets.unwrap(totalAssets)) / Shares.unwrap(totalSupply));
}

// =============================================================
//  TODO 5: Complete the ShareCalculator wrapper
// =============================================================
/// @notice Wraps free functions as external calls (needed for abi.encodeCall tests)
// See: Module 1 > abi.encodeCall (#abi-encodecall)
contract ShareCalculator {
    function convertToShares(
        Assets assets,
        Assets totalAssets,
        Shares totalSupply
    ) external pure returns (Shares) {
        // TODO: Call the toShares free function and return the result
        return toShares(assets, totalAssets, totalSupply);
    }

    function convertToAssets(
        Shares shares,
        Assets totalAssets,
        Shares totalSupply
    ) external pure returns (Assets) {
        // TODO: Call the toAssets free function and return the result
        return toAssets(shares, totalAssets, totalSupply);
    }
}
