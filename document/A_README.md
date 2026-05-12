# SC6107 Project 1 — Flash-Loan Arbitrage & MEV Platform

A dApp + smart-contract suite that, in a single atomic transaction, borrows
ERC-20 from a flash-loan provider (Aave V3 or Balancer V2), routes the
borrowed asset through 2–3 DEX hops to capture an arbitrage spread, repays
the flash loan + fee, and keeps the profit. Ships with MEV protection
(commit-reveal + time-lock), gas optimization, a real-time monitoring
dashboard, and a liquidation bot.

See `../Project1_TaskDivision.md` for the team split and the locked Day-1
interfaces.

## Repo layout

```
SC6107/
├── contracts/                Foundry workspace (Module A so far)
│   ├── src/
│   │   ├── interfaces/       Locked cross-module interfaces
│   │   ├── adapters/         AaveV3FlashAdapter, BalancerV2FlashAdapter
│   │   ├── base/             FlashLoanReceiverBase (consumed by Person C)
│   │   └── mocks/            Mock Aave Pool / Balancer Vault / ERC-20
│   ├── test/                 Foundry tests + helpers
│   ├── script/               forge-script deploy
│   ├── foundry.toml
│   └── lib/                  forge-std, OpenZeppelin
├── frontend/                 Person E
├── docs/
│   └── flash-loan-aggregator.md   Module A design + lifecycle
├── scripts/
│   └── deploy-flash-loan.sh  thin bash wrapper around forge script
├── addresses.sepolia.json    shared deployed-addresses file (Module A writes the flash-loan keys)
├── .env.example
└── README.md
```

## Module A — Flash-Loan Aggregator (this branch)

See [docs/flash-loan-aggregator.md](../docs/flash-loan-aggregator.md) for
the full design and sequence diagrams. Quick start:

```bash
# First time only — fetch forge-std and OpenZeppelin into contracts/lib/
( cd contracts && forge install foundry-rs/forge-std --no-commit \
                 && forge install OpenZeppelin/openzeppelin-contracts --no-commit )

cd contracts
forge build
forge test -vv
forge coverage --ir-minimum --no-match-coverage "(test|mocks|script)/"
```

Deploy to Sepolia:

```bash
cp .env.example .env       # fill in PRIVATE_KEY + SEPOLIA_RPC_URL
./scripts/deploy-flash-loan.sh --dry    # simulate
./scripts/deploy-flash-loan.sh          # broadcast and patch addresses.sepolia.json
```

## What other modules consume from us

| Consumer                           | What they import                                                      |
| ---------------------------------- | --------------------------------------------------------------------- |
| Person B (router) / Person D (bot) | `IFlashLoanProvider` ABI                                            |
| Person C (executor)                | `FlashLoanReceiverBase` (inherits)                                  |
| Person E (frontend)                | `addresses.sepolia.json` → `.aaveAdapter` / `.balancerAdapter` |

The Day-1 interfaces are locked. Anything below them is implementation detail
and can change without breaking other modules.

## AI tool usage

Per the project's academic-integrity policy (Development Project doc, §AI
Tool Usage), AI assistance (Claude) was used during Module A development
for scaffolding, NatSpec drafting, and test case generation. All code has
been reviewed, modified, and is understood by the contributor.
