import { isDeployed, shortAddress } from "../../lib/addresses";
import type { TxUpdate } from "../../lib/types";

const sepoliaTxBase = "https://sepolia.etherscan.io/tx/";

export function TransactionFeed({ transactions }: { transactions: TxUpdate[] }) {
  return (
    <div className="panel">
      <div className="panel-heading">
        <div>
          <h2>Recent Transactions</h2>
          <p>Demo feed prepared for pending, confirmed, and failed tx events.</p>
        </div>
      </div>
      <div className="feed">
        {transactions.map((tx) => (
          <a
            className="feed-item"
            href={isDeployed(tx.hash) ? `${sepoliaTxBase}${tx.hash}` : "#"}
            key={tx.hash + tx.label}
            rel="noreferrer"
            target="_blank"
          >
            <span className={`status ${tx.status}`}>{tx.status}</span>
            <strong>{tx.label}</strong>
            <code>{shortAddress(tx.hash)}</code>
            <small>{tx.ts}</small>
          </a>
        ))}
      </div>
    </div>
  );
}
