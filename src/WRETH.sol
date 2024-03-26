// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../lib/solmate/src/tokens/ERC20.sol";
import "./interface/RocketOvmPriceOracle.sol";

import {Test, console} from "forge-std/Test.sol";

/// NOTE: Due to precision loss caused by the fixed point exchange rate, insignificant amounts of rETH will be trapped in
/// this contract permanently. The value of these tokens will be so low that the gas cost to keep track of them greatly
/// exceeds their worth.

/// @author Kane Wallmann (Rocket Pool)
/// @author ERC20 modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
contract WRETH {
    ERC20 immutable public rETH;
    RocketOvmPriceOracleInterface immutable public oracle;

    uint256 constant public decimals = 18;
    string constant public name = "Wrapped Rocket Pool ETH";
    string constant public symbol = "wrETH";

    uint256 public rate;

    // Balances denominated in rETH
    uint256 internal supplyInTokens;
    mapping(address => uint256) internal tokenBalance;

    // Allowances denominated in wrETH
    mapping(address => mapping(address => uint256)) public allowance;

    // EIP-2612 permit
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    //
    // Events
    //

    event Rebase(uint256 previousRate, uint256 newRate);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    //
    // Constructor
    //

    constructor(ERC20 _rETH, RocketOvmPriceOracleInterface _oracle) {
        rETH = _rETH;
        oracle = _oracle;
        // Record the initial rate
        rate = oracle.rate();
        // Domain separator
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    //
    // Rebasing functions
    //

    /// @notice Retrieves the current rETH rate from oracle and rebases balances and supply
    function rebase() external {
        uint256 newRate = oracle.rate();
        // Nothing to do
        if (newRate == rate) {
            return;
        }
        // Emit event
        emit Rebase(rate, newRate);
        // Update the rate
        rate = newRate;
    }

    /// @notice Transfers rETH from the caller and mints wrETH
    function mint(uint256 _amountTokens) external {
        // Calculate the value denominated in ETH
        uint256 amountEth = ethForTokens(_amountTokens);
        // Transfer that number of token to this contract
        require(rETH.transferFrom(msg.sender, address(this), _amountTokens), "Transfer failed");
        // Mint wrETH
        supplyInTokens += _amountTokens;
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            tokenBalance[msg.sender] += _amountTokens;
        }
        // Emit event
        emit Transfer(address(0), msg.sender, amountEth);
    }

    /// @notice Burns wrETH and returns the appropriate amount of rETH to the caller
    function burn(uint256 _amountEth) public {
        // Calculate the value denominated in rETH
        uint256 amountTokens = tokensForEth(_amountEth);
        // Transfer that number of token to this contract
        require(rETH.transfer(msg.sender, amountTokens), "Transfer failed");
        // Burn wrETH
        supplyInTokens -= amountTokens;
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            tokenBalance[msg.sender] -= amountTokens;
        }
        // Emit event
        emit Transfer(msg.sender, address(0), _amountEth);
    }

    /// @notice Burns the caller's full balance of wrETH and returns rETH
    function burnAll() external {
        burn(balanceOf(msg.sender));
    }

    //
    // ERC20 logic
    //

    /// @notice Allows an owner to permit another account to transfer tokens
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens to another account
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        uint256 amountTokens = tokensForEth(amount);
        tokenBalance[msg.sender] -= amountTokens;
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            tokenBalance[to] += amountTokens;
        }
        emit Transfer(msg.sender, to, ethForTokens(amountTokens));
        return true;
    }

    /// @notice Transfers tokens from one account to another
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        uint256 amountTokens = tokensForEth(amount);
        tokenBalance[from] -= amountTokens;
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            tokenBalance[to] += amountTokens;
        }
        emit Transfer(from, to, ethForTokens(amountTokens));
        return true;
    }

    //
    // EIP-2612 logic
    //

    /// @notice Sets approval for another account based on EIP-2612 permit signature
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");
            allowance[recoveredAddress][spender] = value;
        }
        emit Approval(owner, spender, value);
    }

    /// @notice Returns the EIP-712 domain separator for this token
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    //
    // ERC20 views
    //

    /// @notice Returns the balance of the given account
    function balanceOf(address _owner) public view returns (uint256) {
        return ethForTokens(tokenBalance[_owner]);
    }

    /// @notice Returns the total supply of this token
    function totalSupply() external view returns (uint256) {
        return ethForTokens(supplyInTokens);
    }

    //
    // Internals
    //

    /// @dev Calculates the amount of rETH the supplied value of ETH is worth
    function tokensForEth(uint256 _eth) internal view returns (uint256) {
        return _eth * 1 ether / rate;
    }

    /// @dev Calculates the amount of ETH the supplied value of rETH is worth
    function ethForTokens(uint256 _tokens) internal view returns (uint256) {
        return _tokens * rate / 1 ether;
    }

    /// @dev Computes and returns the EIP-712 domain separator
    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
