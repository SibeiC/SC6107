# SC6107 Project 1 — Flash-Loan Arbitrage & MEV Platform

A 5-person team build of an atomic flash-loan arbitrage platform on Sepolia
(Aave V3 + Balancer V2 → Uniswap V3 + two self-deployed V2 pools), with
MEV protection, a monitoring dashboard, and a liquidation bot.

See `../Project1_TaskDivision.md` for the team split and the locked Day-1
interfaces.

## Repo layout

```
SC6107/
├── contracts/               Foundry workspace
│   ├── src/                 Production contracts
│   ├── test/                Unit + fuzz tests
│   ├── script/              forge-script deploys
│   └── foundry.toml
├── docs/                    Per-module design docs
├── document/                Per-person READMEs
├── scripts/                 Bash wrappers around forge-script
├── addresses.sepolia.json   Shared deployed-addresses file
├── .env.example
└── README.md
```

## Per-module docs

| Module | Owner | README |
|---|---|---|
| A — Flash-Loan Aggregator | Person A | [document/A_README.md](document/A_README.md) |
| B — DEX Adapters & Routing | Person B | [document/B_README.md](document/B_README.md) |
| C — Arbitrage Executor + MEV + Gas | Person C | [document/C_README.md](document/C_README.md) |
| D — Off-chain Backend + Liquidation Bot | Person D | _coming_ |
| E — Frontend + Docs + CI | Person E | _coming_ |

## Quick start

```bash
# Fetch foundry-managed dependencies (one time per clone)
( cd contracts && forge install foundry-rs/forge-std --no-commit \
                 && forge install OpenZeppelin/openzeppelin-contracts --no-commit )

# Build + test
cd contracts
forge build
forge test -vv
```

## AI tool usage

Per the project's academic-integrity policy (Development Project doc, §AI
Tool Usage), AI assistance (Claude) has been used by contributors during
Module A development for scaffolding, NatSpec drafting, and test case
generation. Each module's README documents the scope of AI assistance for
that module. All committed code has been reviewed, modified, and is
understood by the contributor whose GitHub account authored it.
