// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import "../src/WRETH.sol";
import "../src/mock/MockRETH.sol";
import "../src/mock/MockOracle.sol";
import "../src/WRETHVault.sol";

/// @dev Tests for the ERC-4626 vault
contract VaultTest is Test {
    MockRETH public rETH;
    WRETH public wrETH;
    MockOracle public oracle;
    WRETHVault public vault;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        oracle = new MockOracle(1 ether);
        rETH = new MockRETH();
        wrETH = new WRETH(IERC20(address(rETH)), oracle);
        vault = new WRETHVault(wrETH);
    }

    //
    // Helpers
    //

    function mintAndDepositReth(address to, uint256 amount) internal {
        // Mint rETH
        rETH.mint(to, amount);
        // Approve vault to spend rETH
        vm.prank(to);
        rETH.approve(address(vault), amount);
        // Deposit rETH into vault
        vm.prank(to);
        vault.depositReth(amount, to);
    }

    function redeemReth(address to, uint256 amount) internal {
        vm.prank(to);
        vault.redeemReth(amount, to, to);
    }

    function withdrawReth(address to, uint256 amount) internal {
        vm.prank(to);
        vault.withdrawReth(amount, to, to);
    }

    function mintWreth(address to, uint256 amountTokens) internal {
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

    //
    // rETH deposits and withdrawals
    //

    function test_DepositAndRedeem() public {
        // Mint and deposit
        mintAndDepositReth(alice, 1 ether);
        // Check balances
        assertEq(1 ether, wrETH.balanceOf(address(vault)));
        assertEq(1 ether, vault.balanceOf(alice));
        // Redeem shares
        redeemReth(alice, 1 ether);
        // Check balances
        assertEq(0, wrETH.balanceOf(address(vault)));
        assertEq(0, vault.balanceOf(alice));
        assertEq(1 ether, rETH.balanceOf(alice));
    }

    function test_DepositAndWithdraw() public {
        // Mint and deposit
        mintAndDepositReth(alice, 1 ether);
        // Check balances
        assertEq(1 ether, wrETH.balanceOf(address(vault)));
        assertEq(1 ether, vault.balanceOf(alice));
        // Redeem shares
        withdrawReth(alice, 1 ether);
        // Check balances
        assertEq(0, wrETH.balanceOf(address(vault)));
        assertEq(0, vault.balanceOf(alice));
        assertEq(1 ether, rETH.balanceOf(alice));
    }

    function test_DepositAndRedeemWithNewRate() public {
        // Mint and deposit
        mintAndDepositReth(alice, 1 ether);
        // Check balances
        assertEq(1 ether, wrETH.balanceOf(address(vault)));
        assertEq(1 ether, vault.balanceOf(alice));
        // Update rate
        newRate(2 ether);
        // Check balances
        assertEq(2 ether, vault.convertToAssets(vault.balanceOf(alice)));
        // Redeem shares
        redeemReth(alice, 1 ether);
        // Check balances
        assertEq(0, wrETH.balanceOf(address(vault)));
        assertEq(0, vault.balanceOf(alice));
        assertEq(1 ether, rETH.balanceOf(alice));
    }

    function test_DepositAndWithdrawWithNewRate() public {
        // Mint and deposit
        mintAndDepositReth(alice, 1 ether);
        // Check balances
        assertEq(1 ether, wrETH.balanceOf(address(vault)));
        assertEq(1 ether, vault.balanceOf(alice));
        // Update rate
        newRate(2 ether);
        // Check balances
        uint256 assetBalance = vault.convertToAssets(vault.balanceOf(alice));
        assertEq(2 ether, assetBalance);
        // Redeem shares
        withdrawReth(alice, assetBalance);
        // Check balances
        assertEq(0, wrETH.balanceOf(address(vault)));
        assertEq(0, vault.balanceOf(alice));
        assertEq(1 ether, rETH.balanceOf(alice));
    }

    function testFuzz_DepositAndWithdrawAfterRateChange(uint256 rate) public {
        vm.assume(rate > 0 && rate < 1000000 ether);
        // Mint and deposit 1 rETH worth
        mintAndDepositReth(alice, 1 ether);
        mintAndDepositReth(bob, 2 ether);
        // Update rate
        newRate(rate);
        // Vault balance should match rate
        uint256 aliceBalance = vault.convertToAssets(vault.balanceOf(alice));
        uint256 bobBalance = vault.convertToAssets(vault.balanceOf(bob));
        assertEq(rate, aliceBalance);
        assertEq(rate * 2, bobBalance);
        // Redeem shares
        withdrawReth(alice, aliceBalance);
        withdrawReth(bob, bobBalance);
        // Check balances
        assertEq(0, wrETH.balanceOf(address(vault)));
        assertEq(0, vault.balanceOf(alice));
        assertEq(0, vault.balanceOf(bob));
        assertEq(1 ether, rETH.balanceOf(alice));
        assertEq(2 ether, rETH.balanceOf(bob));
    }

    function testFuzz_DepositAfterRateChange(uint256 rate) public {
        vm.assume(rate > 0 && rate < 1000000 ether);
        // Update rate
        newRate(rate);
        // Mint and deposit 1 rETH worth
        mintAndDepositReth(alice, 1 ether);
        // Vault balance should match rate
        uint256 aliceBalance = vault.convertToAssets(vault.balanceOf(alice));
        assertEq(1 ether, vault.balanceOf(alice));
        // Redeem shares
        withdrawReth(alice, aliceBalance);
        // Check balances
        assertEq(0, wrETH.balanceOf(address(vault)));
        assertEq(0, vault.balanceOf(alice));
        assertEq(1 ether, rETH.balanceOf(alice));
    }
}
