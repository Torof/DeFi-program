// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Interface for Vat's gem accounting (used by GemJoin).
interface IVatGem {
    function slip(bytes32 ilk, address usr, int256 wad) external;
}

/// @notice Simplified GemJoin — bridges external ERC-20 collateral ↔ Vat gem balance.
/// @dev Pre-built — students do NOT modify this.
///
///      In MakerDAO, GemJoin.join() locks collateral ERC-20 tokens in the adapter
///      and credits the user's internal `gem` balance in the Vat via `Vat.slip()`.
///      GemJoin.exit() does the reverse: debits gem and returns ERC-20 tokens.
///
///      This simplified version assumes 18-decimal ERC-20 tokens (WAD).
///      Production GemJoin handles different decimal conversions.
contract SimpleGemJoin {
    using SafeERC20 for IERC20;

    IVatGem public immutable vat;
    bytes32 public immutable ilk;
    IERC20 public immutable gem;

    constructor(address vat_, bytes32 ilk_, address gem_) {
        vat = IVatGem(vat_);
        ilk = ilk_;
        gem = IERC20(gem_);
    }

    /// @notice Lock ERC-20 collateral and credit Vat gem balance.
    /// @param usr The address to credit in the Vat.
    /// @param wad The amount of collateral to join (WAD, 18 decimals).
    function join(address usr, uint256 wad) external {
        gem.safeTransferFrom(msg.sender, address(this), wad);
        vat.slip(ilk, usr, int256(wad));
    }

    /// @notice Return ERC-20 collateral and debit Vat gem balance.
    /// @param usr The address to send the ERC-20 tokens to.
    /// @param wad The amount of collateral to exit (WAD, 18 decimals).
    function exit(address usr, uint256 wad) external {
        vat.slip(ilk, msg.sender, -int256(wad));
        gem.safeTransfer(usr, wad);
    }
}
