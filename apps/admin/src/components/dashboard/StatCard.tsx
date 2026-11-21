import { Link } from 'react-router-dom';

interface Props {
  label: string;
  value: number | string;
  note: string;
  tone?: 'good' | 'warn' | 'bad';
  to: string;
}

export default function StatCard({ label, value, note, tone = 'good', to }: Props) {
  return (
    <Link to={to} className="card stat">
      <span className="stat__label">{label}</span>
      <span className="stat__value">{typeof value === 'number' ? value.toLocaleString('en-US') : value}</span>
      <span className={`stat__note stat__note--${tone}`}>{note}</span>
    </Link>
  );
}
