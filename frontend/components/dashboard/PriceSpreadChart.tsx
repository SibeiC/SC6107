import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from "recharts";
import type { PricePoint } from "../../lib/types";

export function PriceSpreadChart({ data }: { data: PricePoint[] }) {
  return (
    <div className="panel chart-panel">
      <div className="panel-heading">
        <div>
          <h2>Price Spread</h2>
          <p>Venue prices over the latest mock watcher window.</p>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={270}>
        <AreaChart data={data} margin={{ top: 12, right: 16, bottom: 0, left: 0 }}>
          <defs>
            <linearGradient id="dexA" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#0d9488" stopOpacity={0.32} />
              <stop offset="95%" stopColor="#0d9488" stopOpacity={0.02} />
            </linearGradient>
            <linearGradient id="dexB" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#2563eb" stopOpacity={0.28} />
              <stop offset="95%" stopColor="#2563eb" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#d9e1eb" />
          <XAxis dataKey="time" tickLine={false} axisLine={false} />
          <YAxis tickLine={false} axisLine={false} width={42} domain={[99.8, 102.2]} />
          <Tooltip />
          <Legend />
          <Area type="monotone" dataKey="dexA" stroke="#0d9488" fill="url(#dexA)" />
          <Area type="monotone" dataKey="dexB" stroke="#2563eb" fill="url(#dexB)" />
          <Area type="monotone" dataKey="uniV3" stroke="#7c3aed" fill="transparent" />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
