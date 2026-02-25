// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Interface for Vat's dai accounting (used by DaiJoin).
interface IVatDai {
    function move(address src, address dst, uint256 rad) external;
}

/// @notice Interface for the stablecoin ERC-20 (mint/burn).
interface IStablecoin {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/// @notice Simplified DaiJoin — converts internal Vat dai ↔ external stablecoin ERC-20.
/// @dev Pre-built — students do NOT modify this.
///
///      In MakerDAO, DaiJoin converts between internal dai (RAD precision in the Vat)
///      and external DAI (WAD precision ERC-20). Users call DaiJoin.exit() after
///      generating dai via frob to get actual DAI tokens.
///
///      Precision conversion: Vat dai is in RAD (10^45), ERC-20 is in WAD (10^18).
///      exit: pull RAD from user's Vat balance, mint WAD to user's ERC-20 balance.
///      join: burn WAD from user's ERC-20 balance, credit RAD to user's Vat balance.
contract SimpleDaiJoin {
    uint256 constant RAY = 10 ** 27;

    IVatDai public immutable vat;
    IStablecoin public immutable dai;

    constructor(address vat_, address dai_) {
        vat = IVatDai(vat_);
        dai = IStablecoin(dai_);
    }

    /// @notice Convert external stablecoin → internal Vat dai.
    /// @dev Burns WAD stablecoin from msg.sender, credits RAD to usr in Vat.
    /// @param usr The address to credit in the Vat.
    /// @param wad The amount of stablecoin to join (WAD, 18 decimals).
    function join(address usr, uint256 wad) external {
        dai.burn(msg.sender, wad);
        vat.move(address(this), usr, wad * RAY);
    }

    /// @notice Convert internal Vat dai → external stablecoin.
    /// @dev Pulls RAD from msg.sender's Vat balance, mints WAD to usr.
    /// @param usr The address to receive the stablecoin ERC-20 tokens.
    /// @param wad The amount of stablecoin to exit (WAD, 18 decimals).
    function exit(address usr, uint256 wad) external {
        vat.move(msg.sender, address(this), wad * RAY);
        dai.mint(usr, wad);
    }
}
