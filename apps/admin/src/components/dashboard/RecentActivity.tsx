import { Link } from 'react-router-dom';
import type { ActivityItem } from '../../types/dashboard';

export default function RecentActivity({ items }: { items: ActivityItem[] }) {
  return (
    <section className="card activity">
      <h2 className="card__title">Recent activity</h2>
      <p className="card__sub">The latest updates across your operations</p>
      {items.length === 0 ? (
        <p className="empty">Nothing yet today. New requests and donations will appear here.</p>
      ) : (
        <ul className="activity__list">
          {items.map((a) => (
            <li key={a.id}>
              <time>{a.time}</time>
              <Link to={a.href}>{a.text}</Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
