import { shortAddress } from "../../lib/addresses";
import type { LiquidationOpportunity } from "../../lib/types";

export function LiquidationWatch({ items }: { items: LiquidationOpportunity[] }) {
  return (
    <section className="panel">
      <div className="panel-heading">
        <div>
          <h2>Liquidation Watch</h2>
          <p>Read-only panel for D&apos;s bonus bot stream.</p>
        </div>
        <span className="pill">Bonus</span>
      </div>
      <div className="liquidation-grid">
        {items.map((item) => (
          <div className="liquidation-card" key={item.user}>
            <div>
              <span className="label">User</span>
              <code>{shortAddress(item.user)}</code>
            </div>
            <div>
              <span className="label">Health factor</span>
              <strong>{item.healthFactor}</strong>
            </div>
            <div>
              <span className="label">Assets</span>
              <strong>
                {item.debtAsset} / {item.collateralAsset}
              </strong>
            </div>
            <span className={`status ${item.status}`}>{item.status}</span>
          </div>
        ))}
      </div>
    </section>
  );
}
