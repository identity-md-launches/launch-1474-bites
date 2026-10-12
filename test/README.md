# BITES tests

Run from the repository root:

```sh
forge build
forge test
```

The suite uses the project's existing vendored forge-std, with no forks, downloads,
environment changes, or additional dependencies.

- `BITESToken.t.sol` and `DeployBITESToken.t.sol` retain the existing metadata,
  constructor allocation, event, transfer, deployment, and launch-shaped flow tests.
- `BITESToken.Properties.t.sol` adds boundary and failure tests, plus seven fuzz
  properties with 1,000 runs each. Rejected calls must return the expected error and
  preserve all four actors' balances and all sixteen allowance pairs. Explicit
  cases cover zero, one wei, the whole supply, `uint256.max - 1`, `uint256.max`,
  repeated spending, revocation, and overlapping sender/spender/recipient roles.
- `BITESToken.Invariant.t.sol` runs 256 sequences of 128 calls using
  `handlers/BITESTokenHandler.sol`. Its inline configuration treats unexpected
  handler reverts as failures. Deliberately invalid token calls are caught and
  checked inside the handler.

The invariant handler deploys the actual token, distributes constructor-minted
funds among four tracked actors, and targets only ten explicitly selected actions.
Actions mix approvals, transfers, delegated spending, full-balance transfers,
revocations, and rejected calls. Transfers stay within this actor set so summing
their balances accounts for every minted token. One actor starts empty. Separate
approval-and-spend actions make successful delegated transfers reachable while
standalone actions exercise approvals across multiple transactions.

After every action, the invariants check the fixed supply, aggregate balances,
each holder's cumulative authorized receipts and payments, and each ordered
owner/spender pair's latest grant minus successful spending. Unlimited allowances
remain unlimited until explicitly replaced. Ghost values come from requested
operations, never from copying observed post-call balances or allowances. Failed
calls leave these values unchanged. At each sequence's end, every holder must be
able to send its full balance back to the original deployer.

These are local token tests. The launch-shaped flow test does not constitute an
integration test against a deployed factory or Uniswap pool manager.
