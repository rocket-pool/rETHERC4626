// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interface/PriceOracleInterface.sol";

contract MockOracle is PriceOracleInterface {
    constructor (uint256 _rate) {
        rate = _rate;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }
}
