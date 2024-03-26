// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/WRETH.sol";
import "../src/mock/MockRETH.sol";
import "../src/mock/MockOracle.sol";

contract wrETHTest is Test {
    MockRETH public rETH;
    WRETH public wrETH;
    MockOracle public oracle;

    function setUp() public {
        oracle = new MockOracle(1 ether);
        rETH = new MockRETH();
        wrETH = new WRETH(rETH, oracle);
    }

    function test_WrapAndUnmint() public {
        // Mint some wrETH
        rETH.mint(address(this), 1 ether);
        rETH.approve(address(wrETH), 1 ether);
        wrETH.mint(1 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 1 ether);
        assertEq(rETH.balanceOf(address(this)), 0);
        // Burn the wrETH
        wrETH.burn(1 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(rETH.balanceOf(address(this)), 1 ether);
    }

    function test_Rebase() public {
        // Mint some wrETH
        rETH.mint(address(this), 1 ether);
        rETH.approve(address(wrETH), 1 ether);
        wrETH.mint(1 ether);
        // Increase the rate 100%
        oracle.setRate(2 ether);
        wrETH.rebase();
        // Check balance
        assertEq(wrETH.balanceOf(address(this)), 2 ether);
        // Unmint
        wrETH.burn(2 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(rETH.balanceOf(address(this)), 1 ether);
    }

    function test_WrapAndUnmintWithNewRate() public {
        // Increase the rate 100%
        oracle.setRate(2 ether);
        wrETH.rebase();
        // Mint some wrETH
        rETH.mint(address(this), 1 ether);
        rETH.approve(address(wrETH), 1 ether);
        wrETH.mint(1 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 2 ether);
        assertEq(rETH.balanceOf(address(this)), 0);
        // Increase the rate by another 100 %
        oracle.setRate(4 ether);
        wrETH.rebase();
        // Burn the wrETH
        wrETH.burn(4 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(rETH.balanceOf(address(this)), 1 ether);
    }

    function testFuzz_WrapAndUnmint(uint64[10] calldata rates, uint64[10] calldata amounts) public {
        // Fuzz rate and mint
        for (uint256 i = 0; i < 10; ++i) {
            vm.assume(amounts[i] != 0);

            oracle.setRate(1 ether + uint256(rates[i]));
            wrETH.rebase();

            address caller = vm.addr(10+i);
            uint256 amount = uint256(amounts[i]);

            rETH.mint(caller, amounts[i]);

            vm.prank(caller);
            rETH.approve(address(wrETH), amount);

            vm.prank(caller);
            wrETH.mint(amount);
        }

        // Unmint all balances
        for (uint256 i = 0; i < 10; ++i) {
            address caller = vm.addr(10+i);
            vm.prank(caller);
            wrETH.burnAll();
        }

        // Check balances
        // Due to limited precision of exchange rates, there might be minuscule amounts of dust trapped
        assertApproxEqAbs(rETH.balanceOf(address(wrETH)), 0, 20 wei);
        for (uint256 i = 0; i < 10; ++i) {
            address caller = vm.addr(10+i);
            assertApproxEqAbs(rETH.balanceOf(caller), amounts[i], 20 wei);
            assertApproxEqAbs(wrETH.balanceOf(caller), 0, 20 wei);
        }
    }
}
