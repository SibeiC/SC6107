# Module C — Arbitrage Executor + MEV Protection + Gas Pass

The middle layer of the SC6107 platform: glue between Person A's
flash-loan adapters and Person B's DEX router, plus a commit-reveal
MEV-protection wrapper, gas optimization, and a security writeup.
Everything in `contracts/src/executor/` and the matching tests under
`contracts/test/`.

See `document/A_README.md` for the flash-loan adapter layer we sit on
top of.

## What's in here

```
contracts/src/
├── interfaces/
│   ├── IDexAdapter.sol           locked Day-1 interface (Person B implements)
│   └── IRouter.sol               locked Day-1 interface + Hop / Route structs at file scope
└── executor/
    ├── ArbitrageExecutor.sol     flash-loan + router glue, transient beneficiary, profit ledger
    └── CommitRevealExecutor.sol  MEV-resistant subclass with tunable minRevealDelay

contracts/test/
├── ArbitrageExecutor.t.sol            24 cases — unit + fuzz
├── CommitRevealExecutor.t.sol         19 cases — commit / reveal / cancel / cleanup / params
├── Integration.t.sol                  7 cases — Aave × Balancer × profit/break-even/loss
├── ArbitrageExecutor.invariant.t.sol  3 invariants × 256 runs each
└── helpers/MockRouter.sol             controllable IRouter for tests

contracts/script/
└── DeployArbitrageExecutor.s.sol      writes .executor + .directExecutor to addresses.sepolia.json

scripts/
└── deploy-executor.sh                 bash wrapper, mirrors deploy-flash-loan.sh

docs/
├── gas-report.md                       before/after numbers + design rationale
└── security-analysis.md                manual review + Slither preemptive items
```

## Lifecycle of a profitable arbitrage

```mermaid
sequenceDiagram
    autonumber
    actor Bot as user / bot
    participant Exec as ArbitrageExecutor
    participant Adp as AaveV3FlashAdapter
    participant Pool as Aave V3 Pool
    participant Router
    participant DEX

    Note over Bot,DEX: Phase 1 — atomic arbitrage (single tx)
    Bot->>Exec: requestArb(adapter, asset, amount, route, minProfit)
    Note right of Exec: tstore(beneficiary, msg.sender)
    Exec->>Adp: _flashLoan(asset, amount, data)
    Adp->>Pool: flashLoanSimple(receiver=adapter, asset, amount)
    Pool-->>Adp: transfer(amount)
    Adp->>Exec: forward asset, onFlashLoan(asset, amount, fee, data)
    Note right of Exec: tload(beneficiary)<br/>balBefore = balanceOf - amount
    Exec->>Exec: forceApprove(router, amount)
    Exec->>Router: execute(route)
    Router->>DEX: swap hop(s)
    DEX-->>Router: amountOut
    Router-->>Exec: amountOut
    Exec->>Exec: forceApprove(router, 0)
    Note right of Exec: profit = balanceOf - balBefore - owed<br/>profitWithdrawable[bene][asset] += profit
    Exec-->>Adp: callback returns; approve (amount + fee)
    Adp->>Pool: pool pulls (amount + fee)
    Note right of Exec: tstore(beneficiary, 0)

    Note over Bot,DEX: Phase 2 — pull profit (separate tx)
    Bot->>Exec: withdraw(asset, to, amount)
    Exec-->>Bot: safeTransfer(amount) → to
```

The commit-reveal lifecycle replaces step 1 (`requestArb`) with
`commit(hash)` → wait ≥ `minRevealDelay` blocks → `reveal(...)` (same
args as `requestArb` plus the salt that hashes the commit). Everything
from `_flashLoan` onwards is identical.

## Key design choices

1. **EIP-1153 transient storage for the beneficiary.** Saves ~20 000
   gas per call vs a cold SSTORE + clear, auto-clears at tx end, and
   keeps the beneficiary out of the flash-loan payload so the adapter
   can never forward or log it.
2. **Pull-payment ledger.** Profits credit a
   `profitWithdrawable[beneficiary][asset]` mapping; the beneficiary
   pulls them in a separate tx. Push-payment inside the callback
   would have reintroduced a reentry vector for contract
   beneficiaries.
3. **Commit hash binds the beneficiary.** A front-runner who learns
   the preimage in flight cannot reveal — their `msg.sender` would
   change the hash and `NoSuchCommit` fires.
4. **`minRevealDelay` is a constructor argument** (the contract has no
   built-in default; the deploy script in
   `script/DeployArbitrageExecutor.s.sol` picks `1` as its
   `DEFAULT_MIN_REVEAL_DELAY`). At delay = 1 the contract behaves as a
   pure single-block timelock. The brief accepts commit-reveal as a
   Flashbots substitute on Sepolia.
5. **`nonReentrant` on `withdraw`, NOT on `requestArb`.** The
   inherited callback's guard already protects the swap path; adding
   a second guard to `requestArb` would deadlock the legitimate
   adapter callback (same OZ `_status` slot).
6. **Allowance reset to zero after every swap.** ~5 000 gas accepted.
   A swappable router is too sharp an edge to leave a stale allowance
   against.
7. **Pre-loan balance snapshot.** Profit attribution uses
   `balanceOf - balBefore - owed` (i.e. round-trip surplus only,
   where `owed = amount + fee` and
   `balBefore = balanceOf - amount` taken at the start of
   `_executeOperation`), not the naive `balanceOf - owed`. Without
   the `balBefore` subtraction, a user with prior unwithdrawn profit
   would inflate the next caller's credit (a real bug caught by the
   invariant suite — see `docs/security-analysis.md` §3.1).

## How downstream modules consume this

| Consumer                  | What they import                                                            |
| ------------------------- | --------------------------------------------------------------------------- |
| Person B (router)         | `IDexAdapter`, `IRouter`, `Route`, `Hop` ABIs                              |
| Person D (off-chain bot)  | `ArbitrageExecutor` / `CommitRevealExecutor` ABI + `addresses.sepolia.json` `.executor` / `.directExecutor`        |
| Person E (frontend)       | Same — calls `commit` then `reveal` (or `requestArb` for the no-MEV path)  |

The Day-1 interfaces (`IDexAdapter`, `IRouter`) are locked; Person B's
production router will plug in via `executor.setRouter(...)` once it
ships.

## Deploy

```bash
cd SC6107
cp .env.example .env       # then fill in PRIVATE_KEY + SEPOLIA_RPC_URL
# Order matters: adapters first, executor second.
./scripts/deploy-flash-loan.sh                    # Person A
./scripts/deploy-executor.sh --dry                # simulate
./scripts/deploy-executor.sh                      # broadcast + patch addresses.sepolia.json

# Once Person B's router is live, owner must call setRouter on BOTH
# executors (the canonical MEV-protected one and the direct sibling),
# otherwise the un-wired one will revert with RouterNotSet on first use:
# cast send <executor>       "setRouter(address)" <router> --private-key $PRIVATE_KEY ...
# cast send <directExecutor> "setRouter(address)" <router> --private-key $PRIVATE_KEY ...
```

The script writes only `.executor` (= `CommitRevealExecutor`, the
canonical MEV-protected entry point) and `.directExecutor`
(= `ArbitrageExecutor`, additive sibling for the rare no-MEV demo
path); everything else in the JSON is untouched.

## Tests

```bash
cd SC6107/contracts
forge test -vv
forge coverage --ir-minimum --no-match-coverage "(test|mocks|script)/"
forge test --gas-report
```

Current test counts:

| File                                | Tests                         | Status |
|-------------------------------------|------------------------------:|--------|
| `ArbitrageExecutor.t.sol`           | 24 (unit + fuzz)              | green  |
| `CommitRevealExecutor.t.sol`        | 19                            | green  |
| `Integration.t.sol`                 | 7                             | green  |
| `ArbitrageExecutor.invariant.t.sol` | 3 invariants × 256 runs       | green  |
| Person A's suite (unchanged)        | 35                            | green  |
| **Total**                           | **88**                        |        |

## Security

See `docs/security-analysis.md` for the full writeup. TL;DR: one
HIGH-severity bug was caught and fixed by the invariant suite during
development (profit attribution included prior beneficiary's
unwithdrawn balance); all other items are accepted-and-mitigated
slither-likely flags. Slither itself was not run locally — the
environment did not have it installed; run command is documented.

## AI tool usage

Per the project's academic-integrity policy (Development Project doc,
§AI Tool Usage), AI assistance (Claude) was used during Module C
development for scaffolding, NatSpec drafting, test case generation,
and design documentation. The HIGH-severity profit-attribution bug
referenced in `docs/security-analysis.md` §3.1 was caught by the
invariant suite (which was itself the artifact that proved the bug)
and fixed by the contributor; the fix was reviewed and verified
across the full test matrix before merge. All committed code has
been reviewed, modified, and is understood by the contributor whose
GitHub account authored it.
