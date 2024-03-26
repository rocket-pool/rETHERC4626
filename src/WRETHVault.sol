// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interface/IWRETH.sol";

/*

    rETH is a non-rebasing token, it's value is determined by the amount of ETH backing the supply which increases
    as validators earn rewards from the protocol.

    wrETH is a rebasing token. wrETH accepts rETH tokens and mints their equivalent ETH quantity in wrETH. When the
    protocol rate of rETH updates each day, wrETH is rebased to match. In this way, 1 wrETH is always equivalent to
    1 ETH in value. wrETH can be burned to recover the equivalent value in the underlying rETH tokens.

    This ERC-4626 vault uses wrETH as it's underlying token. It further wraps wrETH to provide another non-rebasing
    variant of rETH that is compliant with the ERC-4626 standard (wwrETH). The underlying token is wrETH but because
    wrETH is equivalent in value to ETH, the `asset` values shown can be thought of as ETH.

    rETH cannot itself be an ERC-4626 vault because it cannot accept deposits of the underlying token (ETH) on an L2 due
    to the unknown available deposit limit on the deposit pool on L1. So this abstraction is necessary in order to
    maintain compliance with ERC-4626.

*/

/// @author Kane Wallmann (Rocket Pool)
/// @notice An ERC-4626 implementation for wrETH that supports transparent minting/burning of wrETH from rETH
contract WRETHVault is ERC4626 {
    using Math for uint256;

    IERC20 immutable public rETH;
    IWRETH immutable public wrETH;

    //
    // Constructor
    //

    constructor(IWRETH _wrETH) ERC4626(IERC20(_wrETH)) ERC20("ERC4626-Wrapped wrETH", "wwrETH") {
        rETH = _wrETH.rETH();
        wrETH = _wrETH;
        rETH.approve(address(wrETH), type(uint256).max);
    }

    //
    // ERC-4626 functions for rETH
    //

    /// @notice Accepts rETH as a deposit transparently wrapping it in wrETH first
    /// @param amountReth The amount of rETH to wrap and deposit
    /// @param receiver The account which receives the resulting shares
    function depositReth(uint256 amountReth, address receiver) public virtual returns (uint256) {
        // Transfer rETH tokens here
        SafeERC20.safeTransferFrom(rETH, msg.sender, address(this), amountReth);
        // Compute how much wrETH (assets) we will get for the given rETH
        uint256 assets = wrETH.wrethForTokens(amountReth);
        // Check deposit limit
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }
        // Calculate number of shares to give (must happen before minting the wrETH for correct exchange rate)
        uint256 shares = previewDeposit(assets);
        // Wrap the rETH in wrETH, sending the wrETH here
        assert(wrETH.mint(amountReth) == assets);
        // Mint vault tokens
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        // Return number of shares minted
        return shares;
    }

    /// @notice Withdraws rETH transparently unwrapping it from wrETH
    /// @param assets The number of assets to withdraw denominated in wrETH
    /// @param receiver The account which receives the resulting shares
    /// @param owner The account which owns the shares
    function withdrawReth(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        // Check max withdraw
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        // Calculate number of shares to burn
        uint256 shares = previewWithdraw(assets);
        // Execute
        _withdrawReth(msg.sender, receiver, owner, assets, shares);
        // Return number of shares withdrawn
        return shares;
    }

    /// @notice Redeems rETH transparently unwrapping it from wrETH
    /// @param shares The number of shares to redeem denominated in wrETH
    /// @param receiver The account which receives the resulting shares
    /// @param owner The account which owns the shares
    function redeemReth(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        // Check max redeem
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        // Calculate number of shares to redeem
        uint256 assets = previewRedeem(shares);
        // Execute
        _withdrawReth(msg.sender, receiver, owner, assets, shares);
        // Return number of assets redeemed
        return assets;
    }

    //
    // Internals
    //

    function _withdrawReth(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        // Check allowance
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        // Burn wrETH back to rETH
        uint256 tokens = wrETH.burn(assets);
        // Transfer rETH back to caller
        rETH.transfer(caller, tokens);
        // Burn vault tokens
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    //
    // Overrides
    //

    /// @dev Internal conversion function (from assets to shares) with support for rounding direction.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal override view virtual returns (uint256) {
        // By doing the calculation in this order instead of the default way we gain some precision
        uint256 totalAssets = wrETH.tokenBalanceOf(address(this));
        uint256 ownedTokens = assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets + 1, rounding);
        return wrETH.tokensForWreth(ownedTokens);
    }

    /// @dev Internal conversion function (from shares to assets) with support for rounding direction.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal override view virtual returns (uint256) {
        // By doing the calculation in this order instead of the default way we gain some precision
        uint256 totalAssets = wrETH.tokenBalanceOf(address(this));
        uint256 ownedTokens = shares.mulDiv(totalAssets + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
        return wrETH.wrethForTokens(ownedTokens);
    }
}
