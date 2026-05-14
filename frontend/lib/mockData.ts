import type { AddressBook, LiquidationOpportunity, Opportunity, PricePoint, TxUpdate } from "./types";

const placeholderAdapter = "0x1111111111111111111111111111111111111111";
const placeholderTokenA = "0x2222222222222222222222222222222222222222";
const placeholderTokenB = "0x3333333333333333333333333333333333333333";

export function getMockOpportunities(addresses: AddressBook): Opportunity[] {
  return [
    {
      id: "arb-001",
      pair: "mUSDC / mWETH",
      provider: "Aave V3",
      path: "mUSDC -> mWETH -> mUSDC",
      expectedProfit: "42.80 mUSDC",
      gasEstimate: "0.0041 ETH",
      netProfit: "31.20 mUSDC",
      confidence: "High",
      status: addresses.router === "0x0000000000000000000000000000000000000000" ? "Blocked" : "Ready",
      route: {
        amountIn: "1000000000",
        minAmountOut: "1030000000",
        hops: [
          {
            adapter: addresses.dex.dexA === "0x0000000000000000000000000000000000000000" ? placeholderAdapter : addresses.dex.dexA,
            tokenIn: addresses.tokens.mUSDC === "0x0000000000000000000000000000000000000000" ? placeholderTokenA : addresses.tokens.mUSDC,
            tokenOut: addresses.tokens.mWETH === "0x0000000000000000000000000000000000000000" ? placeholderTokenB : addresses.tokens.mWETH
          },
          {
            adapter: addresses.dex.dexB === "0x0000000000000000000000000000000000000000" ? placeholderAdapter : addresses.dex.dexB,
            tokenIn: addresses.tokens.mWETH === "0x0000000000000000000000000000000000000000" ? placeholderTokenB : addresses.tokens.mWETH,
            tokenOut: addresses.tokens.mUSDC === "0x0000000000000000000000000000000000000000" ? placeholderTokenA : addresses.tokens.mUSDC
          }
        ]
      }
    },
    {
      id: "arb-002",
      pair: "mDAI / mUSDC",
      provider: "Balancer V2",
      path: "mDAI -> mUSDC -> mDAI",
      expectedProfit: "18.45 mDAI",
      gasEstimate: "0.0037 ETH",
      netProfit: "9.10 mDAI",
      confidence: "Medium",
      status: "Simulated",
      route: {
        amountIn: "2500000000000000000000",
        minAmountOut: "2511000000000000000000",
        hops: [
          {
            adapter: placeholderAdapter,
            tokenIn: placeholderTokenA,
            tokenOut: placeholderTokenB
          }
        ]
      }
    },
    {
      id: "arb-003",
      pair: "mWETH / mDAI",
      provider: "Aave V3",
      path: "mWETH -> mDAI -> mUSDC -> mWETH",
      expectedProfit: "0.031 mWETH",
      gasEstimate: "0.0058 ETH",
      netProfit: "0.012 mWETH",
      confidence: "Low",
      status: "Simulated",
      route: {
        amountIn: "1000000000000000000",
        minAmountOut: "1012000000000000000",
        hops: [
          { adapter: placeholderAdapter, tokenIn: placeholderTokenA, tokenOut: placeholderTokenB },
          { adapter: placeholderAdapter, tokenIn: placeholderTokenB, tokenOut: placeholderTokenA }
        ]
      }
    }
  ];
}

export const priceSeries: PricePoint[] = [
  { time: "09:00", dexA: 100.1, dexB: 101.0, uniV3: 100.6 },
  { time: "09:05", dexA: 100.2, dexB: 101.3, uniV3: 100.7 },
  { time: "09:10", dexA: 100.4, dexB: 101.5, uniV3: 100.9 },
  { time: "09:15", dexA: 100.3, dexB: 101.7, uniV3: 101.0 },
  { time: "09:20", dexA: 100.6, dexB: 101.9, uniV3: 101.1 },
  { time: "09:25", dexA: 100.8, dexB: 101.6, uniV3: 101.2 }
];

export const txFeed: TxUpdate[] = [
  {
    hash: "0x4c929a2c71bc0f6d5e1e7e3f6a9be9b473a714cfd521b3f54b9f9d3b6ab233c1",
    status: "confirmed",
    label: "CommitRevealExecutor deployed",
    ts: "2h ago"
  },
  {
    hash: "0xa0b4ac0d9f09175ccaf774fe02fbc9e2c6b4ce6c9f74efeb4eb3d4de1f918aaa",
    status: "confirmed",
    label: "Flash-loan adapters deployed",
    ts: "5h ago"
  },
  {
    hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
    status: "pending",
    label: "Router deployment pending",
    ts: "waiting"
  }
];

export const liquidationFeed: LiquidationOpportunity[] = [
  {
    user: "0x91c5D4C2f19701420b77F4fd3B1F9B0B3cA4C242",
    healthFactor: "0.97",
    debtAsset: "mUSDC",
    collateralAsset: "mWETH",
    status: "blocked"
  },
  {
    user: "0xB2a09F338fBfB6C2f0c6B9B5B94b0A7e7A516543",
    healthFactor: "1.04",
    debtAsset: "mDAI",
    collateralAsset: "mWETH",
    status: "watching"
  }
];
