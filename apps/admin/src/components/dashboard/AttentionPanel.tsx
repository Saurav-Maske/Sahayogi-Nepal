import { useNavigate } from 'react-router-dom';
import type { DashboardData } from '../../types/dashboard';

export default function AttentionPanel({ attention }: { attention: DashboardData['attention'] }) {
  const navigate = useNavigate();
  const { quantityDiscrepancies: n } = attention;

  return (
    <section className="card attention">
      <h2 className="card__title">Needs your attention</h2>

      {n === 0 && <p className="empty">No open quantity discrepancies were returned by the backend.</p>}

      {n > 0 && (
        <div className="attention__item">
          <p className="attention__alert">
            {n} quantity {n === 1 ? 'discrepancy' : 'discrepancies'}
          </p>
          <p className="card__sub">Review delivery records before closing an incident.</p>
        </div>
      )}

      <p className="card__sub attention__availability-note">Low stock alerts are unavailable because the backend has no configured reorder threshold.</p>

      <button className="btn" onClick={() => navigate('/incidents')}>
        Review incidents
      </button>
    </section>
  );
}
