# Module C — Arbitrage Executor + MEV Protection + Gas Pass

The middle layer of the SC6107 platform: glue between Person A's
flash-loan adapters and Person B's DEX router, plus a commit-reveal
MEV-protection wrapper, gas optimisation, and a security writeup.
Everything in `contracts/src/executor/` and the matching tests under
`contracts/test/`.

See `../Project1_TaskDivision.md` for the team split and
`document/A_README.md` for the flash-loan adapter layer we sit on top
of.

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
└── security-analysis.md                manual review + Slither pre-emptive items
```

## Lifecycle of a profitable arbitrage

```text
user / bot          ArbitrageExecutor           AaveV3FlashAdapter        Aave V3 Pool       Router       DEX
    │                     │                            │                        │              │           │
1. requestArb(...) ──────▶│ (tstore beneficiary)       │                        │              │           │
    │                     │ _flashLoan(...) ──────────▶│                        │              │           │
    │                     │                            │ flashLoanSimple ──────▶│              │           │
    │                     │                            │  transfer(amount) ─────│              │           │
    │                     │                            │ ◀──────────────────────│              │           │
    │                     │ onFlashLoan(...) ◀─────────│                        │              │           │
    │                     │   (tload beneficiary)      │                        │              │           │
    │                     │   forceApprove(router, amt)│                        │              │           │
    │                     │   router.execute(route) ─────────────────────────────────────────▶│           │
    │                     │                            │                        │              │ swap ────▶│
    │                     │                            │                        │              │ ◀────swap│
    │                     │   amountOut received ◀───────────────────────────────────────────│             │
    │                     │   forceApprove(router, 0)  │                        │              │           │
    │                     │   profitWithdrawable[bene] += amountOut - amount - fee             │           │
    │                     │   transfer(amount + fee) ▶ │                        │              │           │
    │                     │                            │ pool.transferFrom ────▶│              │           │
    │                     │ (tstore beneficiary, 0)    │                        │              │           │
2. withdraw(...) ────────▶│ safeTransfer(profit) ▶ user                                                    │
```

The commit-reveal lifecycle replaces step 1 with `commit(hash)` →
wait ≥ `minRevealDelay` blocks → `reveal(...)` (same args as
`requestArb` plus the salt that hashes the commit).

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
4. **`minRevealDelay` tunable, default 1.** At delay = 1 the contract
   behaves as a pure single-block timelock. The brief accepts
   commit-reveal as a Flashbots substitute on Sepolia.
5. **`nonReentrant` on `withdraw`, NOT on `requestArb`.** The
   inherited callback's guard already protects the swap path; adding
   a second guard to `requestArb` would deadlock the legitimate
   adapter callback (same OZ `_status` slot).
6. **Allowance reset to zero after every swap.** ~5 000 gas accepted.
   A swappable router is too sharp an edge to leave a stale allowance
   against.
7. **Pre-loan balance snapshot.** Profit attribution uses
   `balanceOf - amount - balBefore`, not `balanceOf - owed`, so a
   user with prior unwithdrawn profit cannot inflate a fresh
   caller's credit (a real bug caught by the invariant suite — see
   `docs/security-analysis.md` §3.1).

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

# Once Person B's router is live:
# (owner-only)
# cast send <executor> "setRouter(address)" <router> --private-key $PRIVATE_KEY ...
```

The script writes only `.executor` (= `CommitRevealExecutor`) and
`.directExecutor` (= `ArbitrageExecutor`); everything else in the JSON
is untouched.

## Tests

```bash
cd SC6107/contracts
forge test -vv
forge coverage --ir-minimum --no-match-coverage "(test|mocks|script)/"
forge test --gas-report
```

Current line counts:

| File                        | Tests | Status |
|-----------------------------|------:|--------|
| `ArbitrageExecutor.t.sol`   |    24 | green  |
| `CommitRevealExecutor.t.sol`|    19 | green  |
| `Integration.t.sol`         |     7 | green  |
| `ArbitrageExecutor.invariant.t.sol` | 3 invariants × 256 runs | green |
| Person A's suite (unchanged) | 35   | green  |
| **Total**                   | **88**|       |

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
invariant suite (which was itself the artefact that proved the bug)
and fixed by the contributor; the fix was reviewed and verified
across the full test matrix before merge. All committed code has
been reviewed, modified, and is understood by the contributor whose
GitHub account authored it.
