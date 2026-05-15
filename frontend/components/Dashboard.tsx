"use client";

import { useMemo, useState } from "react";
import { getDeploymentItems } from "../lib/addresses";
import { getMockOpportunities, liquidationFeed, priceSeries, txFeed } from "../lib/mockData";
import type { AddressBook, ExecutionMode } from "../lib/types";
import { DeploymentStatusPanel } from "./dashboard/DeploymentStatusPanel";
import { ExecutionPanel } from "./dashboard/ExecutionPanel";
import { LiquidationWatch } from "./dashboard/LiquidationWatch";
import { Metric } from "./dashboard/Metric";
import { OpportunitiesTable } from "./dashboard/OpportunitiesTable";
import { PriceSpreadChart } from "./dashboard/PriceSpreadChart";
import { TransactionFeed } from "./dashboard/TransactionFeed";

export function Dashboard({ addresses }: { addresses: AddressBook }) {
  const opportunities = useMemo(() => getMockOpportunities(addresses), [addresses]);
  const deployments = useMemo(() => getDeploymentItems(addresses), [addresses]);
  const [executionMode, setExecutionMode] = useState<ExecutionMode>("commit");
  const [selectedId, setSelectedId] = useState(opportunities[0]?.id ?? "");

  const selectedOpportunity = opportunities.find((item) => item.id === selectedId) ?? opportunities[0];
  const readyCount = deployments.filter((item) => item.status === "deployed").length;
  const routerReady = deployments.some((item) => item.label === "Router" && item.status === "deployed");
  const executableReady = deployments.some(
    (item) => item.label === "Commit-reveal executor" && item.status === "deployed"
  );
  const executionBlocked = !routerReady || !executableReady;

  return (
    <main className="shell">
      <section className="masthead">
        <div>
          <p className="eyebrow">SC6107 Project 1</p>
          <h1>Flash-Loan Arbitrage Dashboard</h1>
          <p className="lede">
            Monitoring surface for Sepolia deployments, simulated arbitrage opportunities,
            gas-adjusted profit, and commit-reveal execution status.
          </p>
        </div>
        <div className="summary-strip" aria-label="Project status summary">
          <Metric
            label="Contracts ready"
            value={`${readyCount}/${deployments.length}`}
            tone={routerReady ? "good" : "warn"}
          />
          <Metric label="Best net profit" value="31.20 mUSDC" tone="good" />
          <Metric
            label="Execution mode"
            value={executionMode === "commit" ? "Commit reveal" : "Direct"}
            tone="neutral"
          />
        </div>
      </section>

      <section className="grid-two">
        <DeploymentStatusPanel deployments={deployments} routerReady={routerReady} />
        <ExecutionPanel
          executionBlocked={executionBlocked}
          executionMode={executionMode}
          selectedOpportunity={selectedOpportunity}
          onModeChange={setExecutionMode}
        />
      </section>

      <OpportunitiesTable opportunities={opportunities} selectedId={selectedId} onSelect={setSelectedId} />

      <section className="grid-two">
        <PriceSpreadChart data={priceSeries} />
        <TransactionFeed transactions={txFeed} />
      </section>

      <LiquidationWatch items={liquidationFeed} />
    </main>
  );
}
