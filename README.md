# BITES (BITES)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Property        | Value                                                     |
| --------------- | --------------------------------------------------------- |
| Contract name   | `BITESToken` (`src/BITESToken.sol`)                       |
| Token name      | `BITES`                                                   |
| Token symbol    | `BITES`                                                   |
| Decimals        | 18                                                        |
| Total supply    | 10,000,000 BITES = `10000000000000000000000000` minor units |
| Minting         | Once, in the constructor, all to `msg.sender` (the deployer) |
| Constructor     | No arguments                                              |
| Owner / admin   | None                                                      |
| Compiler        | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |

## What the contract does

`BITESToken` is a self-contained EIP-20 implementation with OpenZeppelin v5 semantics:

- `transfer` and `transferFrom` move exactly the amount requested, return `true`, and revert on a
  zero-address receiver or an insufficient balance. There is no fee, burn, reflection or tax on any
  transfer, so every launch flow (factory to distributor, distributor to claimant, seed into the
  pool, swaps through the PoolManager) arrives whole.
- `approve` overwrites the allowance and reverts on a zero-address spender. An allowance of
  `type(uint256).max` is unlimited and is not decremented by `transferFrom`.
- `totalSupply` is a compile-time constant. Nothing in the contract can mint, so the supply cannot
  grow after deployment. There is no `burn` either; the supply is constant for the life of the token.
- There is no owner, minter, pauser, blocklist, freeze, lock, seize or `burnFrom`. No address has any
  power over another holder's balance except through that holder's own `approve`.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, and the contract is not
  upgradeable. It does not accept ether.

## Assumptions

- The brief asks for a plain fixed-supply token: name, symbol, 10,000,000 supply at 18 decimals,
  minted once to the deployer. No transfer rules, governance, vesting or tax were requested, so none
  were added.
- "Deployer" means whatever address runs the constructor. At an IdentityMD launch that is the
  ProjectFactory, which receives the whole supply and pays it out per the launch manifest. Outside a
  launch, it is whoever sends the creation transaction.
- Allowances follow EIP-20 exactly (overwrite on `approve`). Integrators who care about the
  approve/transferFrom race should set the allowance to zero before changing it, as with any EIP-20.

## Deployment parameters

The constructor takes no arguments, so the launch manifest's `constructorArgs` is empty.

| Manifest field       | Value                        |
| -------------------- | ---------------------------- |
| `token.contract`     | `BITESToken`                 |
| `token.name`         | `BITES`                      |
| `token.symbol`       | `BITES`                      |
| `token.decimals`     | `18`                         |
| `token.constructorArgs` | `[]`                      |
| `token.totalSupply`  | `10000000000000000000000000` |

Launch values fixed by the launch, not by this repository: the pool pairs with IMD
(`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee 12500, tick spacing 60, economics
`{"poolBps":8100,"initialMarketCapWei":"2500000000000000000000","remainderTo":"0x00062e1ce32c7c4130de3c8814e4662207128550"}`.
The manifest step writes `launch.json`; this repository does not contain one.

How the supply is paid out at launch, by the factory (none of this is in the token's code):

| Share | Recipient                                          | Amount (BITES) |
| ----- | -------------------------------------------------- | -------------- |
| 10%   | the launch's MerkleDistributor (swarm)              | 1,000,000      |
| 81%   | single-sided liquidity in the IMD/BITES v4 pool      | 8,100,000      |
| 9%    | `0x00062e1ce32c7c4130de3c8814e4662207128550`        | 900,000        |

No application contracts are deployed with the token (`contracts: []`).

## After launch

There is nothing to configure. The token has no owner-settable values, no setters and no
external dependencies, so there are no post-launch calls to make.

## Operational responsibilities

- **Source verification.** After deployment, verify the source on Etherscan with
  `forge verify-contract <address> src/BITESToken.sol:BITESToken --compiler-version 0.8.26` (same
  optimizer settings as `foundry.toml`). This belongs to the network's deployer, not to this task.
- **Key custody.** The token has no admin keys. The only wallets that matter after launch are the
  ordinary holders, including the remainder recipient above.
- **Liquidity and price.** Price discovery happens in the Uniswap v4 pool the factory opens. The token
  has no mechanism to pause trading or recover tokens sent to the wrong address: transfers to
  contracts that cannot handle ERC-20s are permanent, as with any plain ERC-20.
- **Security review.** Tests passing do not constitute an audit. The launch's independent review step
  should run before release. Slither and Mythril were not run in this task: they are not provided by
  the execution profile.

## Repository layout

```
foundry.toml                 compiler pins and build settings (solc 0.8.26, bytecode_hash none)
remappings.txt               forge-std/ -> lib/forge-std/src/
src/BITESToken.sol           the token
script/DeployBITESToken.s.sol reference deploy script; deploy() is tested directly, run() wraps it
test/BITESToken.t.sol        unit, failure and fuzz tests for the token
test/DeployBITESToken.t.sol  test of the script's deploy() function
lib/forge-std/               vendored forge-std v1.11.0 (plain files, not a submodule)
```

## Building and testing

```
forge build
forge test
forge fmt --check
```

Tests read no environment variables and do not depend on the calling address, so they pass in any
order, in parallel and with an empty environment. The suite includes success paths (exact transfers,
allowances, unlimited allowance, launch-shaped flows), failure paths (over-balance, over-allowance,
zero-address receiver and spender, ether sent to the token, unknown and privileged selectors) and
fuzz tests for supply conservation and allowance accounting.

## Reference deployment outside a launch

`script/DeployBITESToken.s.sol` deploys the token from a broadcasting key with
`forge script script/DeployBITESToken.s.sol --rpc-url <url> --broadcast`. The broadcasting address
becomes the deployer and receives the whole supply. The IdentityMD launch does not use this script;
it deploys the built bytecode through the factory.
