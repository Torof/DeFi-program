// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built naive vault, intentionally VULNERABLE.
//  This contract exists so the InflationAttack tests can demonstrate the
//  first-depositor attack. Study it, then implement DefendedVault.sol.
// ============================================================================

/// @notice Minimal vault with NO inflation protection.
/// @dev Uses balanceOf for totalAssets and has no virtual shares.
///      Vulnerable to the inflation (donation / first-depositor) attack.
contract NaiveVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        asset = asset_;
    }

    /// @notice Total assets = actual token balance. THE VULNERABILITY.
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Deposit assets, receive shares. First deposit is 1:1.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        uint256 supply = totalSupply();
        shares = supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets());
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// @notice Redeem shares for assets.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner, "NaiveVault: not owner");
        assets = Math.mulDiv(shares, totalAssets(), totalSupply());
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);
    }
}
