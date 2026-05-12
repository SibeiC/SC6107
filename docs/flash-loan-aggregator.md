# Flash-Loan Aggregator (Module A)

Provider-agnostic flash-loan layer for the SC6107 arbitrage platform. Wraps
Aave V3 and Balancer V2 behind a single locked interface
(`IFlashLoanProvider`) so the executor, router, and off-chain bot don't have
to know which protocol is funding any given loan.

## What's in here

```
contracts/src/
├── interfaces/
│   ├── IFlashLoanProvider.sol     locked Day-1 entrypoint (single + multi-asset)
│   ├── IFlashLoanCallback.sol     borrower-side callback (onFlashLoan / Multi)
│   ├── IAaveV3Pool.sol            minimal external view of the Aave V3 Pool
│   └── IBalancerVault.sol         minimal external view of the Balancer V2 Vault
├── adapters/
│   ├── AaveV3FlashAdapter.sol     wraps `Pool.flashLoanSimple`
│   └── BalancerV2FlashAdapter.sol wraps `Vault.flashLoan` (single + multi-asset)
├── base/
│   └── FlashLoanReceiverBase.sol  abstract base for borrowers (Person C uses this)
└── mocks/                         test doubles for the Aave Pool / Balancer Vault
```

## Lifecycle of a flash loan

```text
borrower (ArbitrageExecutor)         AaveV3FlashAdapter          Aave V3 Pool
        │                                   │                          │
   1. flashLoan(asset, amount, data) ──────▶│                          │
        │                                   │                          │
        │                       pool.flashLoanSimple(this, …, params)──▶
        │                                   │                          │
        │                                   │  transfer(amount) ───────│
        │                                   │◀─────────────────────────│
        │                                   │  executeOperation(…) ────│
        │                                   │◀─────────────────────────│
        │   onFlashLoan(asset, amount, fee, initiator, data) ◀─────────│ (decoded from params)
        │                                   │                          │
        │   ── do business logic ──         │                          │
        │   ── transfer amount+fee back ───▶│                          │
        │                                   │  forceApprove(pool, amount+fee)
        │                                   │  return true ────────────▶
        │                                   │  pool.transferFrom(…) ◀──│
        │                                   │                          │
```

Balancer's flow is identical except the Vault pulls funds back from the
adapter via direct transfer (the adapter does the transfer itself, not the
Vault's `transferFrom`), and the multi-asset path lights up the array
machinery in `BalancerV2FlashAdapter`.

## Key design choices

1. **Stateless adapters.** Both adapters tunnel `(borrower, data)` through
   the underlying protocol's user-data field, so no transient or persistent
   storage is needed between the outbound call and the callback. This
   removes a class of re-entrancy bugs and keeps gas low.
2. **Locked single-asset interface.** `IFlashLoanProvider.flashLoan(asset,
   amount, data)` matches the Day-1 spec exactly. Multi-asset is a
   separate `IFlashLoanProviderMulti` extension implemented only by
   Balancer.
3. **Borrower trust model.** `FlashLoanReceiverBase` keeps an
   owner-controlled whitelist of adapters. The callback rejects calls from
   any non-whitelisted address, so a random contract impersonating Aave
   cannot drain the receiver.
4. **Fee math is on-chain.** The adapter quotes the live premium so we
   keep working if Aave/Balancer flip the fee toggle. `quotePremium` on
   the Aave adapter matches Aave's own `_calculateFlashLoanFee` ceiling.
5. **ReentrancyGuard on both adapters.** Defence in depth: even though the
   stateless design means re-entry can't corrupt state, a nested
   `flashLoan` would forward the wrong borrower address through the
   callback. The guard makes that impossible.

## How downstream modules consume this

```solidity
// Person C's ArbitrageExecutor:
contract ArbitrageExecutor is FlashLoanReceiverBase {
    constructor(address owner, address aaveAdapter, address balancerAdapter)
        FlashLoanReceiverBase(owner)
    {
        // trust both providers at deployment
        // (owner can later flip these via setAdapter)
    }

    function requestArb(address provider, address asset, uint256 amount, bytes calldata route) external {
        _flashLoan(provider, asset, amount, route);
    }

    function _executeOperation(address asset, uint256 amount, uint256 fee, bytes calldata route) internal override {
        // run the route through Person B's Router, ensure profit > 0,
        // leave (amount + fee) of `asset` on this contract before returning.
    }
}
```

Person D's off-chain bot reads only the ABI of `IFlashLoanProvider` plus the
deployed addresses in `addresses.sepolia.json`. No source-level coupling
between the modules.

## Sepolia addresses we ship against

| Protocol     | Address                                      | Notes                                  |
|--------------|----------------------------------------------|----------------------------------------|
| Aave V3 Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` | The pool is `Pool` (not `PoolProxy`).  |
| Balancer V2  | `0xBA12222222228d8Ba445958a75a0704d566BF2C8` | Same address on every Balancer chain.  |

Override either via the `AAVE_V3_POOL` / `BALANCER_VAULT` env vars before
running the deploy script.

## Deployment

```bash
cd SC6107
cp .env.example .env       # then edit PRIVATE_KEY + SEPOLIA_RPC_URL
./scripts/deploy-flash-loan.sh --dry   # simulate
./scripts/deploy-flash-loan.sh         # broadcast + patch addresses.sepolia.json
```

The script only writes to the `aaveAdapter` and `balancerAdapter` JSON keys —
everything else (router, executor, dex, tokens) is owned by other modules
and is left untouched.

## Tests

```bash
cd SC6107/contracts
forge test -vv
forge coverage --ir-minimum --no-match-coverage "(test|mocks|script)/"
```

Current coverage for the three production files:

| File                                | Lines  | Statements | Functions |
|-------------------------------------|--------|------------|-----------|
| `AaveV3FlashAdapter.sol`            | 100%   | 100%       | 100%      |
| `BalancerV2FlashAdapter.sol`        | 100%   | 96%        | 100%      |
| `FlashLoanReceiverBase.sol`         | 93%    | 92%        | 83%       |
| **module total**                    | **98%**| **96%**    | **93%**   |

Exceeds the 90% gate from the task-division spec.

## Security notes

- `executeOperation` (Aave callback) and `receiveFlashLoan` (Balancer
  callback) both reject any caller that is not the configured pool/vault.
- The borrower's `onFlashLoan` is rejected unless `msg.sender` is on its
  trusted-adapter whitelist AND `initiator == address(this)`. This
  prevents a malicious adapter from yanking the contract into a callback
  it didn't initiate.
- The Aave adapter uses `forceApprove`, not `approve`, to be safe against
  USDT-style "approve to non-zero from non-zero reverts" ERC-20s.
- All ERC-20 movements use `SafeERC20`.
- Both adapters carry `ReentrancyGuard`. The borrower base uses one too.
- Slither pass: see `docs/security-analysis.md` (Person C consolidates
  module-level results).
