import type { Opportunity } from "../../lib/types";

export function OpportunitiesTable({
  opportunities,
  selectedId,
  onSelect
}: {
  opportunities: Opportunity[];
  selectedId: string;
  onSelect: (id: string) => void;
}) {
  return (
    <section className="panel">
      <div className="panel-heading">
        <div>
          <h2>Arbitrage Opportunities</h2>
          <p>Mocked from D&apos;s proposed WebSocket event shape and C&apos;s Route struct.</p>
        </div>
        <span className="pill">WS mock</span>
      </div>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Pair</th>
              <th>Provider</th>
              <th>Route</th>
              <th>Expected</th>
              <th>Gas</th>
              <th>Net</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {opportunities.map((item) => (
              <tr
                className={selectedId === item.id ? "selected" : ""}
                key={item.id}
                onClick={() => onSelect(item.id)}
              >
                <td>{item.pair}</td>
                <td>{item.provider}</td>
                <td>{item.path}</td>
                <td>{item.expectedProfit}</td>
                <td>{item.gasEstimate}</td>
                <td>
                  <strong>{item.netProfit}</strong>
                </td>
                <td>
                  <span className={`status ${item.status.toLowerCase()}`}>{item.status}</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
