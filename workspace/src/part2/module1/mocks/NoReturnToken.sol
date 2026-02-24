// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice ERC-20 that does NOT return a bool from transfer/transferFrom/approve.
/// @dev Mimics USDT (Tether) behavior. Calling `require(token.transfer(...))` on this
///      token will revert because there is no return data to decode as bool.
///      SafeERC20 handles this correctly by checking returndata length.
contract NoReturnToken {
    string public constant name = "NoReturnToken";
    string public constant symbol = "NRT";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // NOTE: no return value — this is the whole point of the mock
    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    // NOTE: no return value
    function transferFrom(address from, address to, uint256 amount) external {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    // NOTE: no return value
    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }
}
