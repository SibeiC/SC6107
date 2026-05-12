// Shared between Person D (ws-server) and Person E (frontend).
// Lock this on Day 1 — both sides depend on it.

export type Hop = {
  adapter:  `0x${string}`;
  tokenIn:  `0x${string}`;
  tokenOut: `0x${string}`;
};

export type Route = {
  hops:         Hop[];
  amountIn:     string;   // bigint serialised as decimal string
  minAmountOut: string;
};

export type WsEvent =
  | {
      type:  'price';
      pair:  string;   // e.g. "mUSDC/mWETH"
      venue: string;   // "uniV3" | "dexA" | "dexB"
      price: number;
      ts:    number;   // unix ms
    }
  | {
      type:           'opportunity';
      route:          Route;
      expectedProfit: string;  // bigint as decimal string
      gasEstimate:    string;
      ts:             number;
    }
  | {
      type:   'tx';
      hash:   string;
      status: 'pending' | 'confirmed' | 'failed';
      ts:     number;
    }
  | {
      type:            'liquidation';
      user:            string;
      debtAsset:       string;
      collateralAsset: string;
      ts:              number;
    };
