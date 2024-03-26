// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interface/RocketOvmPriceOracle.sol";

contract MockOracle is RocketOvmPriceOracleInterface {
    constructor (uint256 _rate) {
        rate = _rate;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }
}
