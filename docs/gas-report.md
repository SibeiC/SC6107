# Gas Report — Module C (Arbitrage Executor + Commit-Reveal)

Numbers are pulled from `forge test --gas-report` against the unit
suite. All measurements use `solc 0.8.24`, `via_ir = true`,
`optimizer_runs = 200` — the project defaults Person A pinned in
`contracts/foundry.toml`. Sepolia is Cancun-enabled, so EIP-1153
transient storage is in play.

## ArbitrageExecutor — function-level

| Function          | Before (avg) | After (avg) | Δ      | Notes                                       |
|-------------------|--------------|-------------|--------|---------------------------------------------|
| `requestArb`      | 216 227      | 215 675     | −552   | bps short-circuit when `minProfitBps == 0`. |
| `onFlashLoan`     | 32 166       | 32 163      | −3     | unchanged hot path; one fewer ADD.          |
| `withdraw`        | 37 308       | 37 308      | 0      | Already minimal; CEI + one transfer.        |
| `setRouter`       | 26 109       | 26 109      | 0      |                                             |
| `setMinProfitBps` | 39 198       | 39 198      | 0      |                                             |
| `setAdapter`      | 47 611       | 47 611      | 0      | Inherited from `FlashLoanReceiverBase`.     |

`requestArb` median dropped from **209 507 → 209 403 gas (−104)** for
the common profitable single-hop case with `minProfitBps == 0`. The
small absolute number is expected — the heavy cost is the flash-loan
round trip and the router swap, both of which we cannot squeeze
further from this side of the call.

## Deployment cost

| Contract                | Before    | After     | Δ    |
|-------------------------|-----------|-----------|------|
| `ArbitrageExecutor`     | 1 292 324 | 1 293 008 | +684 | Short-circuit adds an extra branch.        |
| `CommitRevealExecutor`  | —         | 1 538 922 |  —   | First measurement.                         |

The short-circuit pays for itself after **~7 profitable arbs** with
`minProfitBps == 0`. Once the bps floor is enabled (e.g. owner sets
`minProfitBps = 50` for a 0.5% global floor), the short-circuit costs
~3 gas per call (one comparison) and the multiplication runs as before
— a wash.

## Design choices that were already gas-minded before the pass

| Choice                                                | Saving vs naive |
|-------------------------------------------------------|------------------|
| EIP-1153 transient storage for the beneficiary slot   | ~20 000 gas/call vs a cold SSTORE + clear |
| `calldata Route` in `requestArb` (no memory copy)     | ~3 000 gas       |
| `unchecked` increment for `hopsLen - 1`               | ~30 gas          |
| Custom errors (no revert strings)                     | ~50–150 gas/revert |
| Single `SLOAD` of `router` into a local `IRouter r`   | ~2 100 gas       |
| Cached `route.hops.length` into `hopsLen`             | ~30 gas          |

These were baked in at the first commit, so they don't show up as a
"before / after" delta — but they are the bulk of the gas budget
versus a straightforward implementation.

## Deliberate gas costs we kept

| Cost                                                                 | Why kept                                                                                          |
|----------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `forceApprove(router, 0)` after the swap (~5 000 gas)                | Guarantees no lingering allowance to a swappable router — the trade-off is documented and tiny.   |
| Pull-payment ledger (`profitWithdrawable`) instead of push-on-callback| Avoids reentry surface for contract beneficiaries; payer eats the second tx's gas, not the executor. |
| Outer `nonReentrant` on `withdraw`                                   | Defence-in-depth in case the user's beneficiary contract re-enters mid-router-swap.                |

## How to reproduce

```bash
cd contracts
forge build
forge test --gas-report > /tmp/gas.txt
grep -E 'requestArb|onFlashLoan|withdraw|setRouter|setMinProfitBps|setAdapter' /tmp/gas.txt
```

Numbers will differ in the third or fourth digit between machines and
forge versions — the row-to-row deltas (the "Δ" column above) are what
matters for tracking regressions.
