interface CriteriaBarProps {
  label: string;
  value: number;
}

export function CriteriaBar({ label, value }: CriteriaBarProps) {
  const pct = Math.max(0, Math.min(100, (value / 5) * 100));
  return (
    <div className="criteria-row">
      <span style={{ fontSize: 14, color: 'var(--ink-primary)' }}>{label}</span>
      <div className="criteria-track">
        <div className="criteria-fill" style={{ width: `${pct}%` }} />
      </div>
      <span style={{ fontSize: 13.5, fontWeight: 600, textAlign: 'right' }}>
        {value.toFixed(1)}
      </span>
    </div>
  );
}
