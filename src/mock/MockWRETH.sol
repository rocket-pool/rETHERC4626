// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../WRETH.sol";
import "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract MockWRETH is WRETH {
    constructor(IERC20 rETH, RocketOvmPriceOracleInterface oracle) WRETH(rETH, oracle) {}

    function mockMint(address _to, uint256 _amount) external {
        tokenTotalSupply += _amount;
        unchecked {
            tokenBalanceOf[_to] += _amount;
        }
    }
}
