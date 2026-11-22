import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import { useNotifications } from '../context/NotificationsContext';
import type { Notice } from '../services/notificationsService';
import '../styles/notifications.css';

const TABS = ['All notifications', 'Unread', 'Requests', 'Donations', 'Assignments', 'Inventory'] as const;
const when = (iso: string) => {
  const minutes = Math.max(0, Math.floor((Date.now() - +new Date(iso)) / 60_000));
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hr${hours === 1 ? '' : 's'} ago`;
  return `${Math.floor(hours / 24)} day${hours < 48 ? '' : 's'} ago`;
};

export default function NotificationsPage() {
  const [tab, setTab] = useState<string>('All notifications');
  const { items, readIds, unreadCount, loading, error, reload, markRead, markAllRead } = useNotifications();
  const navigate = useNavigate();
  const filtered = useMemo(() => items.filter((item) =>
    tab === 'All notifications' || (tab === 'Unread' ? !readIds.includes(item.id) : item.category === tab)), [items, readIds, tab]);

  function openNotice(item: Notice) {
    markRead(item.id);
    navigate(item.to);
  }

  return <div className="notifications-page"><header className="page__head"><div><h1>Notification center</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Notifications&nbsp; / &nbsp;All districts</p></div><div className="page__actions">{unreadCount > 0 && <button className="btn btn--ghost" onClick={markAllRead}>Mark all read</button>}<button className="btn btn--ghost" onClick={reload} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button><QuickAction/></div></header>
    <nav className="notification-tabs" aria-label="Notification categories">{TABS.map((name) => <button key={name} className={tab === name ? 'is-active' : ''} onClick={() => setTab(name)}>{name}{name === 'Unread' && <span>{unreadCount}</span>}</button>)}</nav>
    <section className="notification-feed" aria-label="Notifications">
      {error && <div className="empty" role="alert">{error} <button className="btn btn--ghost" onClick={reload}>Try again</button></div>}
      {loading && <p className="empty">Loading notifications…</p>}
      {!loading && !error && filtered.map((item) => {
        const isUnread = !readIds.includes(item.id);
        return <button type="button" className={`notification-item notification-item--${item.kind}${isUnread ? ' is-unread' : ''}`} key={item.id} onClick={() => openNotice(item)}>
          <span className="notification-symbol" aria-hidden="true">{item.kind === 'alert' ? '!' : item.kind === 'success' ? '✓' : ''}</span>
          <span className="notification-copy"><strong>{item.title}</strong><span className="notification-detail">{item.detail} · {when(item.createdAt)}</span></span>
          {isUnread && <span className="notification-unread-dot" aria-label="Unread"/>}
        </button>;
      })}
      {!loading && !error && filtered.length === 0 && <p className="empty notification-empty">You’re all caught up.</p>}
    </section>
  </div>;
}
