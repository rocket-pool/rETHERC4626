// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interface/IWRETH.sol";

import {Test, console} from "forge-std/Test.sol";

/// @author Kane Wallmann (Rocket Pool)
/// @author Modified from OpenZeppelin Contracts (v5.0.0) (token/ERC20/extensions/ERC4626.sol)
/// @notice An ERC-4626 implementation for rETH which allows 1:1 conversion between rETH and vault shares
contract rETHERC4626 is ERC20, IERC4626 {
    using Math for uint256;

    /// @dev rETH token address
    IERC20 immutable public rETH;

    /// @dev Oracle for rETH price
    PriceOracleInterface immutable public oracle;

    /// @dev To comply with ERC-4626 `asset()` this returns wETH, however deposit and redeems in wETH are not permitted
    address public asset;

    /// @dev Current rETH:ETH exchange rate
    uint256 public rate;

    //
    // Events
    //

    event Rebase(uint256 previousRate, uint256 newRate);
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    //
    // Constructor
    //

    constructor(PriceOracleInterface _oracle, IERC20 _rETH, address _wETH) ERC20("ERC4626-Wrapped rETH", "wrETH") {
        oracle = _oracle;
        rETH = _rETH;
        asset = _wETH;
        // Set initial rate
        rate = oracle.rate();
        require(rate != 0);
    }

    /// @notice Retrieves the current rETH rate from oracle and rebases balances and supply
    function rebase() external {
        uint256 newRate = oracle.rate();
        // Nothing to do
        if (newRate == rate) {
            return;
        }
        require(newRate != 0);
        // Emit event
        emit Rebase(rate, newRate);
        // Update the rate
        rate = newRate;
    }

    //
    // Conversion functions
    //

    /// @notice Accepts rETH as a deposit and mints equivalent shares
    /// @param shares Amount of rETH to deposit and convert to shares
    /// @param receiver Account where the newly minted shares are sent
    function depositReth(uint256 shares, address receiver) public virtual returns (uint256) {
        // Transfer rETH tokens here
        SafeERC20.safeTransferFrom(rETH, msg.sender, address(this), shares);
        // Convert rETH into ETH value
        uint256 assets = previewRedeem(shares);
        // Mint shares
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        // Return number of shares minted
        return shares;
    }

    /// @notice Withdraws rETH
    /// @param assets The value of assets to withdraw denominated in ETH
    /// @param receiver Account where the newly minted shares are sent
    /// @param owner The account which owns the shares
    function withdrawReth(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        // Calculate number of shares to burn
        uint256 shares = previewWithdraw(assets);
        console.log("Withdrawing %d %d", assets, shares);
        // Execute
        _withdrawReth(msg.sender, receiver, owner, assets, shares);
        // Return number of shares withdrawn
        return shares;
    }

    /// @notice Redeems shares for rETH
    /// @param shares The number of shares to redeem
    /// @param receiver The account which receives the redeemed rETH
    /// @param owner The account which owns the shares
    function redeemReth(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        // Calculate number of shares to redeem
        uint256 assets = previewRedeem(shares);
        // Execute
        _withdrawReth(msg.sender, receiver, owner, assets, shares);
        // Return number of assets redeemed
        return assets;
    }

    //
    // ERC-20/4626 views
    //

    function decimals() public view virtual override(IERC20Metadata, ERC20) returns (uint8) {
        return 18;
    }

    function totalAssets() public view virtual returns (uint256) {
        // Total assets is equal to the supply of rETH * the current exchange rate
        return totalSupply().mulDiv(rate, 1 ether);
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return 0;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return 0;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return 0;
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return 0;
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    // All the below ERC-4626 functions revert as this vault does not accept wETH token deposits
    // Users should use `depositReth`, `withdrawReth` and `redeemReth` instead

    /// @notice Use `depositReth` instead, always reverts
    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        revert ERC4626ExceededMaxDeposit(receiver, assets, 0);
    }

    /// @notice Always reverts (minting not permitted)
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        revert ERC4626ExceededMaxMint(receiver, shares, 0);
    }

    /// @notice Use `withdrawReth` instead, always reverts
    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        revert ERC4626ExceededMaxWithdraw(owner, assets, 0);
    }

    /// @notice Use `redeemReth` instead, always reverts
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        revert ERC4626ExceededMaxRedeem(owner, shares, 0);
    }

    //
    // Internals
    //

    /// @dev Burns shares and sends rETH tokens to receiver
    function _withdrawReth(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        // Check allowance
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        // Transfer rETH back to caller
        rETH.transfer(caller, shares);
        // Burn shares
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Returns number of shares for given value of ETH
    function _convertToShares(uint256 assets, Math.Rounding rounding) public view virtual returns (uint256) {
        return assets.mulDiv(1 ether, rate, rounding);
    }

    /// @dev Returns value of ETH for given number of shares
    function _convertToAssets(uint256 shares, Math.Rounding rounding) public view virtual returns (uint256) {
        return shares.mulDiv(rate, 1 ether, rounding);
    }
}
