// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import "../src/WRETH.sol";
import "../src/mock/MockRETH.sol";
import "../src/mock/MockOracle.sol";

/// @dev Tests rebasing logic
contract wrETHTest is Test {
    MockRETH public rETH;
    WRETH public wrETH;
    MockOracle public oracle;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        oracle = new MockOracle(1 ether);
        rETH = new MockRETH();
        wrETH = new WRETH(IERC20(address(rETH)), oracle);
    }

    //
    // Helpers
    //

    function mint(address to, uint256 amountTokens) internal {
        rETH.mint(to, amountTokens);
        vm.prank(to);
        rETH.approve(address(wrETH), amountTokens);
        vm.prank(to);
        wrETH.mint(amountTokens);
    }

    function newRate(uint256 rate) internal {
        oracle.setRate(rate);
        wrETH.rebase();
    }

    function transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        wrETH.transfer(to, amount);
    }

    //
    // Rebasing logic
    //

    function testFail_MintZero() public {
        wrETH.mint(0);
    }

    function testFail_BurnZero() public {
        wrETH.burn(0);
    }

    function test_MintAndBurn() public {
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

    function test_RebaseUp() public {
        // Mint some wrETH
        rETH.mint(address(this), 1 ether);
        rETH.approve(address(wrETH), 1 ether);
        wrETH.mint(1 ether);
        // Increase the rate 100%
        newRate(2 ether);
        // Check balance
        assertEq(wrETH.balanceOf(address(this)), 2 ether);
        // Burn
        wrETH.burn(2 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(rETH.balanceOf(address(this)), 1 ether);
    }

    function test_RebaseDown() public {
        // Mint some wrETH
        rETH.mint(address(this), 1 ether);
        rETH.approve(address(wrETH), 1 ether);
        wrETH.mint(1 ether);
        // Decrease the rate 50%
        newRate(0.5 ether);
        // Check balance
        assertEq(wrETH.balanceOf(address(this)), 0.5 ether);
        // Burn
        wrETH.burn(0.5 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(rETH.balanceOf(address(this)), 1 ether);
    }

    function test_MintAndBurnWithNewRate() public {
        // Increase the rate 100%
        newRate(2 ether);
        // Mint some wrETH
        rETH.mint(address(this), 1 ether);
        rETH.approve(address(wrETH), 1 ether);
        wrETH.mint(1 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 2 ether);
        assertEq(rETH.balanceOf(address(this)), 0);
        // Increase the rate by another 100 %
        newRate(4 ether);
        // Burn the wrETH
        wrETH.burn(4 ether);
        // Check balances
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(rETH.balanceOf(address(this)), 1 ether);
    }

    //
    // Transfers
    //

    function test_TransferWithNewRate() public {
        mint(alice, 1 ether);
        newRate(2 ether);
        mint(bob, 1 ether);
        assertEq(2 ether, wrETH.balanceOf(alice));
        assertEq(2 ether, wrETH.balanceOf(bob));
        // Transfer half of bob's tokens to alice
        vm.prank(bob);
        wrETH.transfer(alice, 1 ether);
        // Check balances
        assertEq(3 ether, wrETH.balanceOf(alice));
        assertEq(1 ether, wrETH.balanceOf(bob));
        // Rerate
        newRate(4 ether);
        // Check balances
        assertEq(6 ether, wrETH.balanceOf(alice));
        assertEq(2 ether, wrETH.balanceOf(bob));
        // Transfer all of alice's tokens to bob
        vm.prank(alice);
        wrETH.transfer(bob, 6 ether);
        // Check balances
        assertEq(0 ether, wrETH.balanceOf(alice));
        assertEq(8 ether, wrETH.balanceOf(bob));
        // Burn
        vm.prank(bob);
        wrETH.burnAll();
        // Check balances
        assertEq(0 ether, wrETH.balanceOf(alice));
        assertEq(0 ether, wrETH.balanceOf(bob));
        assertEq(2 ether, rETH.balanceOf(bob));
    }

    //
    // Fuzz
    //

    function testFuzz_WrapAndBurn(uint64[10] calldata rates, uint64[10] calldata amounts) public {
        for (uint256 i = 0; i < 10; ++i) {
            vm.assume(amounts[i] != 0);

            address caller = vm.addr(10+i);
            uint256 amount = uint256(amounts[i]);
            uint256 rate = 0.5 ether + uint256(rates[i]);

            newRate(rate);

            rETH.mint(caller, amounts[i]);

            vm.prank(caller);
            rETH.approve(address(wrETH), amount);

            vm.prank(caller);
            wrETH.mint(amount);
        }

        // Burn all
        for (uint256 i = 0; i < 10; ++i) {
            address caller = vm.addr(10+i);
            vm.prank(caller);
            wrETH.burnAll();
        }

        // Check balances
        assertEq(rETH.balanceOf(address(wrETH)), 0);
        for (uint256 i = 0; i < 10; ++i) {
            address caller = vm.addr(10+i);
            assertEq(rETH.balanceOf(caller), amounts[i]);
            assertEq(wrETH.balanceOf(caller), 0);
        }
    }

    function testFuzz_MintTransferAndBurn(uint64[10] calldata rates, uint64[10] calldata amounts, bool[10] calldata directions) public {
        mint(alice, 10000 ether);
        mint(bob, 10000 ether);

        for (uint256 i = 0; i < 10; ++i) {
            vm.assume(amounts[i] != 0);

            uint256 amount = amounts[i];
            uint256 rate = 0.5 ether + uint256(rates[i]);
            bool direction = directions[i];

            newRate(rate);

            uint256 aliceBalanceBefore = wrETH.balanceOf(alice);
            uint256 bobBalanceBefore = wrETH.balanceOf(bob);

            if (direction) {
                transfer(alice, bob, amount);
            } else {
                transfer(bob, alice, amount);
            }

            uint256 aliceBalanceAfter = wrETH.balanceOf(alice);
            uint256 bobBalanceAfter = wrETH.balanceOf(bob);

            if (direction) {
                assertApproxEqAbs(aliceBalanceBefore - aliceBalanceAfter, amount, 20 wei);
                assertApproxEqAbs(bobBalanceAfter - bobBalanceBefore, amount, 20 wei);
            } else {
                assertApproxEqAbs(aliceBalanceAfter - aliceBalanceBefore, amount, 20 wei);
                assertApproxEqAbs(bobBalanceBefore - bobBalanceAfter, amount, 20 wei);
            }
        }

        // Burn all
        vm.prank(alice);
        wrETH.burnAll();
        vm.prank(bob);
        wrETH.burnAll();

        // Check balances
        assertEq(rETH.balanceOf(address(wrETH)), 0);
        assertEq(wrETH.balanceOf(alice), 0);
        assertEq(wrETH.balanceOf(bob), 0);
    }
}
