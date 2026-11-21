import type { ChartPoint } from '../../types/dashboard';

interface Props {
  title: string;
  caption: string;
  points: ChartPoint[];
}

const CHART_HEIGHT = 130;

export default function BarChart({ title, caption, points }: Props) {
  const max = Math.max(1, ...points.map((p) => p.value));
  const top = points.reduce((m, p) => (p.value > m.value ? p : m), points[0] ?? { label: '', value: 0 });

  return (
    <section className="card chart" aria-label={title}>
      <h2 className="card__title">{title}</h2>
      {points.length === 0 ? (
        <p className="empty">No data for this period yet.</p>
      ) : (
        <div className="chart__plot" role="img" aria-label={`${title}. Highest: ${top.label} with ${top.value}.`}>
          {points.map((p, i) => (
            <div className="chart__col" key={p.label}>
              <div
                className={`chart__bar ${i % 2 === 0 ? 'chart__bar--navy' : 'chart__bar--teal'}`}
                style={{ height: Math.max(26, (p.value / max) * CHART_HEIGHT) }}
                title={`${p.label}: ${p.value}`}
              >
                {p.value}
              </div>
              <span className="chart__label">{p.label}</span>
            </div>
          ))}
        </div>
      )}
      <p className="card__caption">{caption}</p>
    </section>
  );
}