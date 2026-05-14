import { shortAddress } from "../../lib/addresses";
import type { DeploymentItem } from "../../lib/types";

export function DeploymentStatusPanel({
  deployments,
  routerReady
}: {
  deployments: DeploymentItem[];
  routerReady: boolean;
}) {
  return (
    <div className="panel">
      <div className="panel-heading">
        <div>
          <h2>Deployment Status</h2>
          <p>A and C are live; B router and DEX venues are still pending integration.</p>
        </div>
        <span className={routerReady ? "pill success" : "pill warning"}>
          {routerReady ? "Executable" : "Router pending"}
        </span>
      </div>
      <div className="deployment-list">
        {deployments.map((item) => (
          <div className="deployment-row" key={item.label}>
            <div>
              <strong>{item.label}</strong>
              <span>Owner {item.owner}</span>
            </div>
            <code>{shortAddress(item.address)}</code>
            <span className={item.status === "deployed" ? "dot ok" : "dot waiting"}>
              {item.status === "deployed" ? "Deployed" : "Pending"}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
