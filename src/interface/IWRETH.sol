// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "./PriceOracleInterface.sol";

interface IWRETH is IERC20 {
    function rETH() external view returns (IERC20);
    function oracle() external view returns (PriceOracleInterface);
    function rate() external view returns (uint256);
    function tokenTotalSupply() external view returns (uint256);
    function tokenBalanceOf(address) external view returns (uint256);
    function rebase() external;
    function mint(uint256 _amountTokens) external returns (uint256);
    function burn(uint256 _amountWreth) external returns (uint256);
    function burnTokens(uint256 _amountTokens) external returns (uint256);
    function burnAll() external;
    function tokensForWreth(uint256 _eth) external view returns (uint256);
    function wrethForTokens(uint256 _tokens) external view returns (uint256);
}
