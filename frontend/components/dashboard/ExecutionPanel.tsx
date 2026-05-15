import type { ExecutionMode, Opportunity } from "../../lib/types";

export function ExecutionPanel({
  executionBlocked,
  executionMode,
  selectedOpportunity,
  onModeChange
}: {
  executionBlocked: boolean;
  executionMode: ExecutionMode;
  selectedOpportunity?: Opportunity;
  onModeChange: (mode: ExecutionMode) => void;
}) {
  return (
    <div className="panel">
      <div className="panel-heading">
        <div>
          <h2>Execution Panel</h2>
          <p>Prepared for C&apos;s executor ABI; actions stay mocked until router and route data are live.</p>
        </div>
        <span className={executionBlocked ? "pill warning" : "pill success"}>
          {executionBlocked ? "Mock mode" : "Ready"}
        </span>
      </div>
      <div className="segmented" role="tablist" aria-label="Execution mode">
        <button className={executionMode === "commit" ? "active" : ""} onClick={() => onModeChange("commit")}>
          Commit reveal
        </button>
        <button className={executionMode === "direct" ? "active" : ""} onClick={() => onModeChange("direct")}>
          Direct
        </button>
      </div>
      <div className="execution-card">
        <div>
          <span className="label">Selected opportunity</span>
          <strong>{selectedOpportunity?.pair ?? "No opportunity"}</strong>
        </div>
        <div>
          <span className="label">Provider</span>
          <strong>{selectedOpportunity?.provider ?? "-"}</strong>
        </div>
        <div>
          <span className="label">Route</span>
          <strong>{selectedOpportunity?.path ?? "-"}</strong>
        </div>
      </div>
      <div className="button-row">
        {executionMode === "commit" ? (
          <>
            <button disabled={executionBlocked}>Commit trade</button>
            <button disabled={executionBlocked}>Reveal after delay</button>
          </>
        ) : (
          <button disabled={executionBlocked}>Execute direct arb</button>
        )}
      </div>
    </div>
  );
}
