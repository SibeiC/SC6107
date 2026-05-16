# Security Analysis — Module C (Arbitrage Executor + Commit-Reveal)

This document is the security writeup for the contracts in
`contracts/src/executor/` (`ArbitrageExecutor`, `CommitRevealExecutor`)
and the supporting interfaces in `contracts/src/interfaces/`. Coverage
spans Slither static analysis, a manual review across the OWASP-for-
Solidity / smart-contract-weakness-classifications most relevant to a
flash-loan executor, and the regression net (unit + integration +
invariant tests) that backs every claim below.

## 1. Methodology

| Pass                          | Status                                                                                                                                                                       |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Manual review (design + code) | Complete — findings in §3.                                                                                                                                                   |
| Unit / integration suite      | 88 tests, all green. See `forge test`.                                                                                                                                       |
| Invariant suite               | 3 invariants × 256 runs × ~500 calls each, zero reverts. See `test/ArbitrageExecutor.invariant.t.sol`.                                                                       |
| Fuzz                          | `testFuzz_profitable_iff_returnCoversFee` (256 runs) drives the executor across the profitable / unprofitable boundary.                                                      |
| Slither static analysis       | **Not run locally** — the developer's environment did not have `slither` installed and the project did not want a one-off CI image added. Run command + expected items below. |

To run Slither yourself:

```bash
pip install slither-analyzer
cd contracts
slither . \
  --solc-remaps "@openzeppelin/=lib/openzeppelin-contracts/ forge-std/=lib/forge-std/src/" \
  --filter-paths "lib|test|mocks|script"
```

## 2. Threat model

The `ArbitrageExecutor` is a holder of transient flash-loan balances and
a long-lived profit ledger. The attackers we explicitly defended
against:

1. **Untrusted-adapter callback.** A random contract calling
   `onFlashLoan` directly, hoping to bypass the trust check and steal a
   loan-shaped transfer of tokens.
2. **Confused-deputy adapter callback.** A trusted adapter being tricked
   into delivering a callback that was not initiated by us.
3. **Front-running / sandwich attacks** on a profitable arbitrage,
   substituting an attacker as the recipient.
4. **Reentrancy** via a malicious router during the swap (calling back
   into `requestArb`, `withdraw`, or the callback itself).
5. **Profit-attribution confusion** — a beneficiary being credited for
   funds that belong to another beneficiary (caught by the invariant
   suite — see §3.1).
6. **Lingering allowances** to a swappable router after the swap.
7. **Stale commit slots** — a committer locking a reveal slot
   indefinitely with no recourse.

## 3. Findings

### 3.1 [HIGH — FIXED] Profit attribution included prior beneficiary's unwithdrawn balance

**Where:** `ArbitrageExecutor._executeOperation` (pre-fix at commit
`fe6ac0a`).

**Mechanism:** `bal - owed` was used to compute the profit to credit
the current beneficiary, but `bal` includes any previously-credited
profit still parked in the contract. With user A holding 10 USDC of
unwithdrawn profit, user B's next profitable arb of N USDC would
credit B for `10 + N`, and B could then withdraw 10 USDC of A's
balance.

**Fix:** snapshot `balanceOf(this) - amount` at the start of
`_executeOperation` as `balBefore`, and credit only
`bal_after - balBefore - owed`. Floor is also adjusted to
`balBefore + owed + minProfit + bpsFloor`.

**Caught by:** `invariant_noStrandedFunds` and
`invariant_ledgerAccountsForEveryProfit` in
`test/ArbitrageExecutor.invariant.t.sol`. Fix shipped in commit
`ceb53f6`.

### 3.2 [Slither — likely flag] `reentrancy-events`: external call before event emit in `_executeOperation`

**Status:** Accepted, mitigated.

The router call happens before `ArbExecuted` is emitted. Slither's
`reentrancy-events` detector typically flags this pattern.
Mitigations:

- The callback is `nonReentrant` (inherited via `FlashLoanReceiverBase`'s
  OZ guard, which uses the same `_status` slot as a re-entered
  `withdraw` would).
- The profit credit is a pure accounting update against a mapping —
  there is no external interaction between the router call and the
  ledger update other than ERC-20 reads.
- The ERC-20 in question is the borrowed asset, controlled by the
  adapter, and is not allowed to be re-entered via the executor's
  callback (the base guard would catch it).

### 3.3 [Slither — likely flag] `assembly` block in `_doArb` / `_executeOperation`

**Status:** Accepted, justified by the design.

Inline assembly is used solely for `tstore` / `tload` against a
namespaced transient slot. Solidity 0.8.24 does not yet expose native
transient storage syntax (added in 0.8.28+). The blocks are
`memory-safe`-tagged, single-instruction, and operate on a slot
constant defined at file scope. Inline-disable comments will be added
above each block to silence the noise if it shows up in CI.

### 3.4 [Slither — likely flag] `solc-version`: 0.8.24

**Status:** Accepted.

Mirrors Person A's pinned version (set in `foundry.toml`). 0.8.24 is
post-Cancun, has no critical advisories for the patterns we use, and
unlocks EIP-1153 transient storage which is core to this module's gas
profile. Bumping for the project as a whole is a coordination point
across Persons A/B/C/D/E, not a Module C decision.

### 3.5 [Manual] Beneficiary-bound commit hash prevents reveal-phase MEV

The commit hash is `keccak256(provider, asset, amount, route,
minProfit, salt, beneficiary)`. An adversary that learns the preimage
in the public mempool cannot reveal on their own behalf — their
`msg.sender` would produce a different hash, the lookup would miss,
and `NoSuchCommit` fires. This is the load-bearing MEV protection on
Sepolia (Flashbots private mempool isn't available there).

### 3.6 [Manual] Lingering router allowance

`_executeOperation` calls `forceApprove(router, 0)` immediately after
the swap, eating ~5 000 gas per arb. Accepted: a swappable router is
already a meaningful surface (owner can set it post-deploy), and a
stale allowance to such a contract is a sharper edge than the cost.

### 3.7 [Manual] Stale commit slots survive a failed reveal

By design. `delete commits[h]` runs **before** `_doArb`, so a
profitable reveal frees the slot cheaply. But a non-profitable reveal
reverts the entire transaction, which rolls back the delete — the
slot is still there. The committer can either `cancel` the slot (one
extra tx) or wait for `maxRevealWindow` to expire. This is documented
in the test
`test_reveal_unprofitable_revertsAndCommitSurvives`.

### 3.8 [Manual] Pull-payment over push-payment

Profit is credited to a ledger; the beneficiary calls `withdraw` in a
separate transaction. Slither's `arbitrary-send-erc20` would not
trigger because `safeTransfer` is to `msg.sender`-supplied `to`, not
to a free address. Push-payment inside the callback would have
reintroduced a reentry vector for contract beneficiaries — explicitly
avoided.

### 3.9 [LOW — MITIGATED] Spam commits cause unbounded state growth

**Surface:** `CommitRevealExecutor.commit(bytes32)` writes a new
mapping slot for any hash. A griefer can publish arbitrary random
hashes whose preimages they alone know (or know nothing about). The
beneficiary-bound preimage in `cancel()` means a third party cannot
clear those slots, so without intervention they persist forever.

**Mitigation:** `cleanup(bytes32 commitHash)` lets *anyone* prune a
slot once `block.number > committedAt + maxRevealWindow`. By that
point the commit is dead (`reveal` can no longer succeed) so removing
it costs no security. State growth is bounded in steady-state by the
spam rate × `maxRevealWindow`.

**Residual risk:** during the window itself, spam is unprunable — a
determined attacker can buy `maxRevealWindow` blocks worth of
storage growth at the cost of a `SSTORE` per commit. Accepted as a
bounded cost rather than introduce a per-commit stake / fee that
would also tax legitimate users. Owner can shrink `maxRevealWindow`
via `setRevealParams` if abuse becomes load-bearing.

**Tests:** `test_cleanup_afterWindow_anyoneCanPrune`,
`test_cleanup_inWindow_revertsCommitStillLive`,
`test_cleanup_unknownHash_revertsNoSuchCommit`.

## 4. Properties verified by tests

| Property                                                          | Test                                                                          |
|-------------------------------------------------------------------|-------------------------------------------------------------------------------|
| Trust-checked callback (only whitelisted adapters can drive it)   | `test_callback_revertsOnUntrustedAdapter`                                     |
| Initiator pinned to executor itself                               | Inherited from `FlashLoanReceiverBase` — covered in Person A's suite          |
| Profitable iff router return ≥ loan + fee + minProfit + bpsFloor  | `testFuzz_profitable_iff_returnCoversFee` (256 runs)                          |
| No stranded funds in the executor                                 | `invariant_noStrandedFunds` (256 runs × ~500 calls)                           |
| Off-chain accumulator matches on-chain ledger                     | `invariant_ledgerAccountsForEveryProfit`                                      |
| Transient beneficiary slot is empty between top-level calls       | `invariant_transientBeneficiaryAlwaysCleared`                                 |
| Reentry via router into `requestArb` reverts                      | `test_reentry_routerCallsRequestArb_reverts`                                  |
| Reentry via router into `withdraw` reverts                        | `test_reentry_routerCallsWithdraw_reverts`                                    |
| Front-runner with preimage cannot reveal on victim's behalf       | `test_reveal_wrongBeneficiary_revertsNoSuchCommit`                            |
| Reveal cannot fire before `minRevealDelay` blocks                 | `test_reveal_tooEarly_reverts`                                                |
| Stale commit (past `maxRevealWindow`) cannot be revealed          | `test_reveal_expired_reverts`                                                 |
| Withdraw is CEI + ledger-checked                                  | `test_withdraw_*` set                                                         |

## 5. Open items

- Slither pass against a populated `lib/`. Preemptive items above
  cover the patterns we'd expect — no surprises anticipated.
- Once Person B's real `Router` lands, re-run integration tests
  against it (the MockRouter is intentionally permissive about
  routes; the real router may impose additional checks).
- Consider exposing a view that returns the **profit-after-fees** that
  a route would yield without executing it (for the off-chain bot to
  pre-flight before paying gas). Out of scope for Module C; flagged
  for a future enhancement.

## 6. Disclosure

AI assistance (Claude) was used during Module C development for
scaffolding, NatSpec drafting, test case generation, and this
writeup. All committed code has been reviewed, modified, and is
understood by the contributor whose GitHub account authored it.
