# Person D — Off-Chain Backend Architecture

## Scope

A Node/TypeScript service suite that finds arbitrage and liquidation opportunities in real time and streams them to the frontend via WebSocket.

```
Sepolia RPC (viem)
       │
       ├── Swap events ──► price-watcher ──► in-memory price grid
       │                                            │
       │                                     price-change signal
       │                                            │
       ├── eth_call ──────► profit-sim ◄────────────┘
       │   (bestRoute)           │
       │                   opportunity above threshold
       │                         │
       ├── AccountData poll ──► liq-bot ─────────────────────────┐
       │                           │                             │
       │                    detected HF < 1                      │
       │                           │                             │
       │               build + submit liquidation tx             │
       │                                                         │
       └── tx-queue (nonce mgmt + retry) ◄──────────────────────┘
                │
                ▼
           ws-server ──────► WebSocket clients (Person E frontend)
```

## Service Map

| Service | Role | Trigger |
|---|---|---|
| `price-watcher` | Subscribes to on-chain `Swap` events; maintains live price grid | New swap event |
| `profit-sim` | Calls `Router.bestRoute` via `eth_call`; computes net profit after gas | Price grid update |
| `liq-bot` | Polls Aave V3 user health factors; builds + submits liquidation tx | HF < 1 detected |
| `ws-server` | Fans out all events to connected frontend clients | Any upstream event |
| `tx-queue` | Manages nonces, retry/backoff for submitted txs | liq-bot submission |

## Folder Layout

```
services/
├── price-watcher/
│   ├── index.ts          # entry — starts viem event subscriptions
│   ├── grid.ts           # in-memory PriceGrid + update helpers
│   └── parsers.ts        # decode UniV2 / UniV3 swap events → price
├── profit-sim/
│   ├── index.ts          # listens to grid updates, emits opportunities
│   ├── simulate.ts       # eth_call Router.bestRoute + gas estimate
│   └── math.ts           # profit = expectedOut − amountIn − gasCost
├── liq-bot/
│   ├── index.ts          # polling loop over Aave user set
│   ├── detector.ts       # getUserAccountData → health factor check
│   ├── builder.ts        # build liquidation calldata
│   └── executor.ts       # submit via tx-queue
├── ws-server/
│   ├── index.ts          # ws server, fan-out, heartbeat
│   └── broadcast.ts      # typed send helpers per WsEvent variant
├── tx-queue/
│   ├── index.ts          # nonce manager + submission loop
│   └── retry.ts          # exponential backoff, status tracking
└── shared/
    ├── client.ts         # singleton viem PublicClient + WalletClient
    ├── addresses.ts      # loads addresses.sepolia.json
    ├── abis.ts           # inline ABIs for Router, Executor, Aave Pool
    └── logger.ts         # pino logger wrapper
```

## Data Formats

### In-Memory Price Grid

```ts
type TokenPair = `${string}/${string}`;   // e.g. "mUSDC/mWETH"

type VenuePrice = {
  price: bigint;           // amountOut per 1e18 amountIn (in output token decimals)
  reserveIn: bigint;
  reserveOut: bigint;
  updatedAtBlock: bigint;
  updatedAtTs: number;     // unix ms
};

type PriceGrid = Map<string, Map<TokenPair, VenuePrice>>;
// outer key: venue ("uniV3" | "dexA" | "dexB")
```

### Swap Event (viem decoded)

```ts
// UniV2-style (dexA, dexB)
type UniV2SwapArgs = {
  sender: `0x${string}`;
  amount0In: bigint; amount1In: bigint;
  amount0Out: bigint; amount1Out: bigint;
  to: `0x${string}`;
};

// UniV3-style
type UniV3SwapArgs = {
  sender: `0x${string}`; recipient: `0x${string}`;
  amount0: bigint; amount1: bigint;
  sqrtPriceX96: bigint; liquidity: bigint; tick: number;
};
```

### Profit Simulation

```ts
type SimInput = {
  tokenIn: `0x${string}`;
  tokenOut: `0x${string}`;
  amountIn: bigint;
};

type SimResult = {
  route: Route;             // IRouter Route struct
  expectedOut: bigint;
  expectedProfit: bigint;   // expectedOut − amountIn − gasCostInToken
  gasEstimate: bigint;
  profitable: boolean;
};
```

### Aave Liquidation

```ts
type AaveAccountData = {
  user: `0x${string}`;
  totalCollateralBase: bigint;
  totalDebtBase: bigint;
  availableBorrowsBase: bigint;
  currentLiquidationThreshold: bigint;
  ltv: bigint;
  healthFactor: bigint;     // < 1e18 means undercollateralised
};

type LiquidationParams = {
  collateralAsset: `0x${string}`;
  debtAsset: `0x${string}`;
  user: `0x${string}`;
  debtToCover: bigint;
  receiveAToken: boolean;   // always false — swap underlying
};
```

### WebSocket Events (shared `types/ws.ts`)

```ts
type WsEvent =
  | { type: 'price';       pair: string; venue: string; price: number; ts: number }
  | { type: 'opportunity'; route: Route; expectedProfit: string; gasEstimate: string; ts: number }
  | { type: 'tx';          hash: string; status: 'pending'|'confirmed'|'failed'; ts: number }
  | { type: 'liquidation'; user: string; debtAsset: string; collateralAsset: string; ts: number };
// expectedProfit and gasEstimate are decimal strings — JSON cannot carry bigint
```

### Tx Queue Entry

```ts
type QueuedTx = {
  id: string;
  type: 'liquidation' | 'arb';
  to: `0x${string}`;
  data: `0x${string}`;
  value: bigint;
  nonce: number;
  gasLimit: bigint;
  attempts: number;
  status: 'pending' | 'submitted' | 'confirmed' | 'failed';
  hash?: `0x${string}`;
  submittedAt?: number;
};
```

## Key Dependencies (consumed, not owned)

| Artifact | Owner | How to get it |
|---|---|---|
| `IRouter` ABI + address | Person B | `contracts/out/` + `addresses.sepolia.json` |
| `ArbitrageExecutor` ABI | Person C | same |
| `IFlashLoanProvider` ABI | Person A | same |
| WS event schema | Person D + E | `types/ws.ts` locked Day 1 |
| Mock token addresses | Person B | `addresses.sepolia.json` |

## Development Approach

- All five services start against a **local Sepolia fork** (`anvil --fork-url $SEPOLIA_RPC`).
- Swap in real `addresses.sepolia.json` values as teammates deploy.
- One commit per completed function — no batch commits.
- Each service has its own `*.test.ts` covering the pure math / parsing logic before touching the network.
