// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import "../src/mock/MockRETH.sol";
import "../src/mock/MockWRETH.sol";
import "../src/mock/MockOracle.sol";

/// @dev Tests basic ERC20 functionality
contract ERC20Test is Test {
    MockRETH public rETH;
    MockWRETH public wrETH;
    MockOracle public oracle;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        oracle = new MockOracle(1 ether);
        rETH = new MockRETH();
        wrETH = new MockWRETH(IERC20(address(rETH)), oracle);
    }

    //
    // Basics
    //

    function test_Name() external {
        assertEq("Wrapped Rocket Pool ETH", wrETH.name());
    }

    function test_Symbol() external {
        assertEq("wrETH", wrETH.symbol());
    }

    function test_Decimals() external {
        assertEq(18, wrETH.decimals());
    }

    function test_TotalSupply() public {
        wrETH.mockMint(alice, 2 ether);
        wrETH.mockMint(bob, 2 ether);
        assertEq(wrETH.totalSupply(), wrETH.balanceOf(alice) + wrETH.balanceOf(bob));
        assertEq(wrETH.totalSupply(), 4 ether);
    }

    function test_Approve() public {
        assertTrue(wrETH.approve(alice, 1 ether));
        assertEq(wrETH.allowance(address(this),alice), 1 ether);
        assertTrue(wrETH.approve(alice, 2 ether));
        assertEq(wrETH.allowance(address(this),alice), 2 ether);
    }

    function test_Transfer() external {
        wrETH.mockMint(alice, 2 ether);
        vm.startPrank(alice);
        wrETH.transfer(bob, 0.5 ether);
        assertEq(wrETH.balanceOf(bob), 0.5 ether);
        assertEq(wrETH.balanceOf(alice), 1.5 ether);
        vm.stopPrank();
    }

    function test_TransferFrom() external {
        wrETH.mockMint(alice, 2 ether);
        vm.prank(alice);
        wrETH.approve(address(this), 1 ether);
        assertTrue(wrETH.transferFrom(alice, bob, 0.7 ether));
        assertEq(wrETH.allowance(alice, address(this)), 1 ether - 0.7 ether);
        assertEq(wrETH.balanceOf(alice), 2 ether - 0.7 ether);
        assertEq(wrETH.balanceOf(bob), 0.7 ether);
    }

    //
    // Zero address reverts
    //

    function testFail_ApproveToZeroAddress() external {
        wrETH.approve(address(0), 1 ether);
    }

    function testFail_TransferToZeroAddress() external {
        wrETH.mockMint(alice, 1 ether);
        vm.prank(alice);
        wrETH.transfer(address(0), 1 ether);
    }

    //
    // Insufficient balances
    //

    function testFail_TransferInsufficientBalance() external {
        wrETH.mockMint(alice, 2 ether);
        vm.prank(alice);
        wrETH.transfer(bob , 3 ether);
    }

    function testFail_TransferFromInsufficientApprove() external {
        wrETH.mockMint(alice, 2 ether);
        vm.prank(alice);
        wrETH.approve(address(this), 1 ether);
        wrETH.transferFrom(alice, bob, 2 ether);
    }

    function testFail_TransferFromInsufficientBalance() external {
        wrETH.mockMint(alice, 2 ether);
        vm.prank(alice);
        wrETH.approve(address(this), type(uint).max);
        wrETH.transferFrom(alice, bob, 3 ether);
    }

    //
    // Fuzzing
    //

    function testFuzz_Approve(address to, uint256 amount) external {
        vm.assume(to != address(0));
        assertTrue(wrETH.approve(to,amount));
        assertEq(wrETH.allowance(address(this),to), amount);
    }

    function testFuzz_Transfer(address to, uint256 amount) external {
        vm.assume(to != address(0));
        vm.assume(to != address(this));
        vm.assume(amount < 10000000 ether);
        wrETH.mockMint(address(this), amount);

        assertTrue(wrETH.transfer(to,amount));
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(wrETH.balanceOf(to), amount);
    }

    function testFuzz_TransferFrom(address from, address to,uint256 approval, uint256 amount) external {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(amount < 10000000 ether);

        amount = bound(amount, 0, approval);
        wrETH.mockMint(from, amount);

        vm.prank(from);
        assertTrue(wrETH.approve(address(this), approval));

        assertTrue(wrETH.transferFrom(from, to, amount));
        assertEq(wrETH.totalSupply(), amount);

        if (approval == type(uint256).max){
            assertEq(wrETH.allowance(from, address(this)), approval);
        }
        else {
            assertEq(wrETH.allowance(from,address(this)), approval - amount);
        }

        if (from == to) {
            assertEq(wrETH.balanceOf(from), amount);
        } else {
            assertEq(wrETH.balanceOf(from), 0);
            assertEq(wrETH.balanceOf(to), amount);
        }
    }

    function testFail_TransferInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) external {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        wrETH.mockMint(address(this), mintAmount);
        wrETH.transfer(to, sendAmount);
    }

    function testFailFuzz_TransferFromInsufficientApprove(address from, address to,uint256 approval, uint256 amount) external {
        amount = bound(amount, approval+1, type(uint256).max);

        wrETH.mockMint(from, amount);
        vm.prank(from);
        wrETH.approve(address(this), approval);
        wrETH.transferFrom(from, to, amount);
    }

    function testFailFuzz_TransferFromInsufficientBalance(address from, address to, uint256 mintAmount, uint256 sentAmount) external {
        sentAmount = bound(sentAmount, mintAmount+1, type(uint256).max);

        wrETH.mockMint(from, mintAmount);
        vm.prank(from);
        wrETH.approve(address(this), type(uint256).max);

        wrETH.transferFrom(from, to, sentAmount);
    }
}