// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interface/IWRETH.sol";

/// @author Kane Wallmann (Rocket Pool)
/// @notice An ERC-4626 implementation for wrETH that supports transparent minting/burning of wrETH from rETH
contract RETHERC4626 is ERC4626 {
    using Math for uint256;

    IERC20 immutable public rETH;
    IWRETH immutable public wrETH;

    uint256 public tokenBalance = 0;

    //
    // Constructor
    //

    constructor(IWRETH _wrETH) ERC4626(IERC20(_wrETH)) ERC20("ERC4626-Wrapped wrETH", "wwrETH") {
        rETH = _wrETH.rETH();
        wrETH = _wrETH;
        require(rETH.approve(address(wrETH), type(uint256).max), "Approval failed");
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
        tokenBalance += amountReth;
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
        tokenBalance -= tokens;
        // Transfer rETH back to caller
        require(rETH.transfer(caller, tokens), "Transfer failed");
        // Burn vault tokens
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    //
    // Overrides
    //

    /// @dev Internal conversion function (from assets to shares) with support for rounding direction.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal override view virtual returns (uint256) {
        // The conversion is assets (ETH) -> tokens (rETH) -> shares
        uint256 rate = wrETH.rate();
        uint256 tokens = assets.mulDiv(1 ether, rate, rounding);
        return tokens.mulDiv(totalSupply() + 10 ** _decimalsOffset(), tokenBalance + 1, rounding);
    }

    /// @dev Internal conversion function (from shares to assets) with support for rounding direction.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal override view virtual returns (uint256) {
        // The conversion is shares -> tokens (rETH) -> assets (ETH)
        uint256 tokens = shares.mulDiv(tokenBalance + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
        uint256 rate = wrETH.rate();
        return tokens.mulDiv(rate, 1 ether, rounding);
    }

    /// @dev Override super implementation to include check for 0 shares
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override virtual {
        // Prevent accidental deposit resulting in 0 shares
        require(shares > 0, "Zero shares");
        // Call super implementation
        ERC4626._deposit(caller, receiver, assets, shares);
    }
}
