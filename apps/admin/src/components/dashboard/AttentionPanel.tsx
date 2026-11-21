import { useNavigate } from 'react-router-dom';
import type { DashboardData } from '../../types/dashboard';

export default function AttentionPanel({ attention }: { attention: DashboardData['attention'] }) {
  const navigate = useNavigate();
  const { quantityDiscrepancies: n, lowStock } = attention;
  const allClear = n === 0 && !lowStock;

  return (
    <section className="card attention">
      <h2 className="card__title">Needs your attention</h2>

      {allClear && <p className="empty">All clear. No discrepancies or low stock right now.</p>}

      {n > 0 && (
        <div className="attention__item">
          <p className="attention__alert">
            {n} quantity {n === 1 ? 'discrepancy' : 'discrepancies'}
          </p>
          <p className="card__sub">Review delivery records before closing an incident.</p>
        </div>
      )}

      {lowStock && (
        <div className="attention__item">
          <p className="attention__stock">{lowStock.item} stock is low</p>
          <p className="card__sub">
            {lowStock.available} {lowStock.unit} available · Threshold {lowStock.threshold}
          </p>
        </div>
      )}

      <button className="btn" onClick={() => navigate('/incidents')}>
        Review incidents
      </button>
    </section>
  );
}