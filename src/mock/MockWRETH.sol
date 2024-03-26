// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../WRETH.sol";

contract MockWRETH is WRETH {
    constructor(ERC20 rETH, RocketOvmPriceOracleInterface oracle) WRETH(rETH, oracle) {}

    function mockMint(address _to, uint256 _amount) external {
        supplyInTokens += _amount;
        unchecked {
            tokenBalance[_to] += _amount;
        }
    }
}
