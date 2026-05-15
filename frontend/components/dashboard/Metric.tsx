type MetricTone = "good" | "warn" | "neutral";

export function Metric({ label, value, tone }: { label: string; value: string; tone: MetricTone }) {
  return (
    <div className={`metric ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
