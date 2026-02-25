// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Simplified DAI-like stablecoin with authorized mint/burn.
/// @dev Pre-built — students do NOT modify this.
///
///      In MakerDAO, Dai.sol is the external ERC-20 representation of the
///      Vat's internal `dai` balance. DaiJoin converts between the two.
///      This simplified version uses a wards (authorized minters) pattern.
contract SimpleStablecoin is ERC20 {
    mapping(address => bool) public wards;

    error NotAuthorized();

    modifier auth() {
        if (!wards[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        wards[msg.sender] = true;
    }

    /// @notice Grant mint/burn authorization.
    function rely(address usr) external auth {
        wards[usr] = true;
    }

    /// @notice Revoke mint/burn authorization.
    function deny(address usr) external auth {
        wards[usr] = false;
    }

    function mint(address to, uint256 amount) external auth {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external auth {
        _burn(from, amount);
    }
}
