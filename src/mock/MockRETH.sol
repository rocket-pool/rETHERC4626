// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../lib/solmate/src/tokens/ERC20.sol";

contract MockRETH is ERC20 {
    constructor() ERC20("Rocket Pool ETH", "rETH", 18) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
