# Module E - Frontend Dashboard, Documentation, and CI

Module E owns the visible project dashboard and the delivery documentation
that ties the contract and backend modules together for the final demo.

## Current scope

The frontend is intentionally mock-first. It can run before Person B's
router and Person D's WebSocket service are fully merged, while still
matching the current contract shape from Modules A and C.

Implemented in this module:

- `frontend/` Next.js + TypeScript app scaffold.
- Deployment status panel driven by `addresses.sepolia.json`.
- Mock arbitrage opportunity table using the shared `Route` shape.
- Gas-vs-profit and price-spread dashboard panels.
- Commit-reveal and direct-execution UI states for Person C's executor.
- Recent transaction and liquidation watch panels for the demo surface.

Wallet and contract-write dependencies are intentionally not installed in
this first frontend slice. `wagmi`, `viem`, and related providers should be
added together with the real wallet integration so this mock dashboard stays
small and easy to audit.

## Integration assumptions

### Contract addresses

The frontend reads the shared root-level `addresses.sepolia.json` file.
At the time this module was started:

| Artifact | Status |
|---|---|
| Aave V3 flash-loan adapter | Deployed |
| Balancer V2 flash-loan adapter | Deployed |
| CommitRevealExecutor | Deployed |
| Direct ArbitrageExecutor | Deployed |
| Router | Pending |
| DEX venues and mock tokens | Pending |

The UI treats zero addresses as `Pending` and disables execution actions
when the router is not available.

### Executor flow

The UI supports two paths:

1. MEV-protected path through `CommitRevealExecutor`:
   - `commit(bytes32 commitHash)`
   - wait at least one block
   - `reveal(provider, asset, amount, route, minProfit, salt)`
2. Direct demo path through `ArbitrageExecutor`:
   - `requestArb(provider, asset, amount, route, minProfit)`

The current buttons are mocked until the router and live route data are
available.

### WebSocket data

The dashboard data model mirrors Person D's draft `WsEvent` shape from the
`off-chain-backend` branch:

- `price`
- `opportunity`
- `tx`
- `liquidation`

Once D's branch is rebased and merged, the mock data layer can be replaced
with a WebSocket client without rewriting the dashboard components.

## Run locally

```bash
cd frontend
npm install
npm run dev
```

Then open the local Next.js URL printed by the dev server.

Verified locally:

```bash
npm run lint
npm run typecheck
npm run build
npm audit --audit-level=moderate
```

The frontend currently uses Next.js 16 with ESLint 9. A package lock is
committed so teammates and markers install the same dependency graph.
GitHub Actions also runs these frontend checks on pull requests and pushes
that touch the dashboard, shared deployment addresses, or this module doc.

## Files

```text
frontend/
├── app/
│   ├── globals.css
│   ├── layout.tsx
│   ├── not-found.tsx
│   └── page.tsx
├── components/
│   ├── Dashboard.tsx
│   └── dashboard/
│       ├── DeploymentStatusPanel.tsx
│       ├── ExecutionPanel.tsx
│       ├── LiquidationWatch.tsx
│       ├── Metric.tsx
│       ├── OpportunitiesTable.tsx
│       ├── PriceSpreadChart.tsx
│       └── TransactionFeed.tsx
├── lib/
│   ├── addresses.ts
│   ├── mockData.ts
│   └── types.ts
├── eslint.config.mjs
├── next.config.mjs
├── package-lock.json
├── package.json
└── tsconfig.json
```

## Maintainability notes

- `Dashboard.tsx` only owns page-level state and layout composition.
- Each dashboard panel lives in `frontend/components/dashboard/`, so
  future changes remain localized.
- Shared UI/data types live in `frontend/lib/types.ts`.
- Address parsing and deployment-status helpers live in
  `frontend/lib/addresses.ts`.
- Mock feeds live in `frontend/lib/mockData.ts`; replacing them with
  Person D's WebSocket stream should not require rewriting the panel
  components.
- The execution panel is isolated in `ExecutionPanel.tsx` so wallet
  connection and contract writes can be added there later without
  touching price charts or deployment status.

## Suggested commit / push checkpoints

Use small, reviewable commits that each leave the frontend in a coherent
state:

1. `chore(frontend): scaffold module E Next dashboard`
2. `feat(frontend): add deployment status and mock opportunity panels`
3. `refactor(frontend): split dashboard into maintainable panels`
4. `docs(frontend): document module E scope and integration plan`
5. `ci(frontend): add frontend typecheck and build workflow`

Do not use empty commits just to inflate the history. The course rubric
asks for meaningful contribution over time, so each commit should map to
a real user-visible or maintainability improvement.

## Next steps

- Replace mock opportunity data with Person D's WebSocket stream.
- Add wallet connection with wagmi / viem once live execution is ready.
- Generate commit hashes from the selected route and user wallet address.
- Keep frontend CI green as integration code replaces mock data.
- Capture final demo screenshots and add them to the presentation deck.

## AI tool usage

AI assistance (OpenAI Codex) was used for frontend scaffolding, mock-data
design, and documentation drafting. The contributor should review and
understand all code before submission, especially before wiring real wallet
transactions.
