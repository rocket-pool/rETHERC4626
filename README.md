## ERC4626-Wrapped rETH

This project comprises two components: wrETH and rETHERC4626.

rETH (the native liquid staking token of the Rocket Pool Protocol) is a non-rebasing token, it's value is determined 
by the amount of ETH backing the supply which increases as validators earn rewards from the protocol.

wrETH is a rebasing token. wrETH accepts rETH tokens and mints their equivalent ETH quantity in wrETH. When the
protocol rate of rETH updates each day, wrETH is rebased to match. In this way, 1 wrETH is always equivalent to
1 ETH in value. wrETH can be burned to recover the equivalent value in the underlying rETH tokens.

This ERC-4626 vault uses wrETH as it's underlying token. It further wraps wrETH to provide another non-rebasing
variant of rETH that is compliant with the ERC-4626 standard (wwrETH). The underlying token is wrETH but because
wrETH is equivalent in value to ETH, the `asset` values shown can be thought of as ETH.

rETH cannot itself be an ERC-4626 vault because it cannot accept deposits of the underlying token (ETH) on an L2 due
to the unknown available deposit limit on the deposit pool on L1. So this abstraction is necessary in order to
maintain compliance with ERC-4626.

### Test

```shell
$ forge test
```
