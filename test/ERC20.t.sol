// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/mock/MockRETH.sol";
import "../src/mock/MockWRETH.sol";
import "../src/mock/MockOracle.sol";

contract ERC20Test is Test {

    address public alice = vm.addr(0x1);
    address public bob = vm.addr(0x2);

    MockRETH public rETH;
    MockWRETH public wrETH;
    MockOracle public oracle;

    function setUp() public {
        oracle = new MockOracle(1 ether);
        rETH = new MockRETH();
        wrETH = new MockWRETH(oracle, rETH);
    }

    function testName() external {
        assertEq("Wrapped Rocket Pool ETH", wrETH.name());
    }

    function testSymbol() external {
        assertEq("wRETH", wrETH.symbol());
    }

    function testMint() public {
        wrETH.mockMint(alice, 2e18);
        assertEq(wrETH.totalSupply(), wrETH.balanceOf(alice));
    }

    function testApprove() public {
        assertTrue(wrETH.approve(alice, 1e18));
        assertEq(wrETH.allowance(address(this),alice), 1e18);
    }

//    function testIncreaseAllowance() external {
//        assertEq(wrETH.allowance(address(this), alice), 0);
//        assertTrue(wrETH.increaseAllowance(alice , 2e18));
//        assertEq(wrETH.allowance(address(this), alice), 2e18);
//    }
//
//    function testDescreaseAllowance() external {
//        testApprove();
//        assertTrue(wrETH.decreaseAllowance(alice, 0.5e18));
//        assertEq(wrETH.allowance(address(this), alice), 0.5e18);
//    }

    function testTransfer() external {
        testMint();
        vm.startPrank(alice);
        wrETH.transfer(bob, 0.5e18);
        assertEq(wrETH.balanceOf(bob), 0.5e18);
        assertEq(wrETH.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        testMint();
        vm.prank(alice);
        wrETH.approve(address(this), 1e18);
        assertTrue(wrETH.transferFrom(alice, bob, 0.7e18));
        assertEq(wrETH.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(wrETH.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(wrETH.balanceOf(bob), 0.7e18);
    }

    function testFailApproveToZeroAddress() external {
        wrETH.approve(address(0), 1e18);
    }

    function testFailApproveFromZeroAddress() external {
        vm.prank(address(0));
        wrETH.approve(alice, 1e18);
    }

    function testFailTransferToZeroAddress() external {
        testMint();
        vm.prank(alice);
        wrETH.transfer(address(0), 1e18);
    }

    function testFailTransferInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        wrETH.transfer(bob , 3e18);
    }

    function testFailTransferFromInsufficientApprove() external {
        testMint();
        vm.prank(alice);
        wrETH.approve(address(this), 1e18);
        wrETH.transferFrom(alice, bob, 2e18);
    }

    function testFailTransferFromInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        wrETH.approve(address(this), type(uint).max);

        wrETH.transferFrom(alice, bob, 3e18);
    }

    /*****************************/
    /*      Fuzz Testing         */
    /*****************************/

    function testFuzzApprove(address to, uint256 amount) external {
        vm.assume(to != address(0));
        assertTrue(wrETH.approve(to,amount));
        assertEq(wrETH.allowance(address(this),to), amount);
    }

    function testFuzzTransfer(address to, uint256 amount) external {
        vm.assume(to != address(0));
        vm.assume(to != address(this));
        wrETH.mockMint(address(this), amount);

        assertTrue(wrETH.transfer(to,amount));
        assertEq(wrETH.balanceOf(address(this)), 0);
        assertEq(wrETH.balanceOf(to), amount);
    }

    function testFuzzTransferFrom(address from, address to,uint256 approval, uint256 amount) external {
        vm.assume(from != address(0));
        vm.assume(to != address(0));

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

    function testFailTransferInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) external {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        wrETH.mockMint(address(this), mintAmount);
        wrETH.transfer(to, sendAmount);
    }

    function testFailFuzzTransferFromInsufficientApprove(address from, address to,uint256 approval, uint256 amount) external {
        amount = bound(amount, approval+1, type(uint256).max);

        wrETH.mockMint(from, amount);
        vm.prank(from);
        wrETH.approve(address(this), approval);
        wrETH.transferFrom(from, to, amount);
    }

    function testFailFuzzTransferFromInsufficientBalance(address from, address to, uint256 mintAmount, uint256 sentAmount) external {
        sentAmount = bound(sentAmount, mintAmount+1, type(uint256).max);

        wrETH.mockMint(from, mintAmount);
        vm.prank(from);
        wrETH.approve(address(this), type(uint256).max);

        wrETH.transferFrom(from, to, sentAmount);
    }

}