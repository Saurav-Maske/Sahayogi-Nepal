import { FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';

interface Props {
  notificationCount: number;
  userName: string;
  userRole: string;
  onMenuClick: () => void;
}

export default function AdminTopbar({ notificationCount, userName, userRole, onMenuClick }: Props) {
  const navigate = useNavigate();
  const [query, setQuery] = useState('');

  const today = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

  const onSearch = (e: FormEvent) => {
    e.preventDefault();
    const q = query.trim();
    if (q) navigate(`/requests?q=${encodeURIComponent(q)}`);
  };

  return (
    <header className="topbar">
      <button className="topbar__menu" onClick={onMenuClick} aria-label="Open navigation">
        <span /><span /><span />
      </button>

      <form className="topbar__search" onSubmit={onSearch} role="search">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <circle cx="7" cy="7" r="5" stroke="currentColor" strokeWidth="1.5" />
          <path d="M11 11l3.5 3.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search requests, people, inventory"
          aria-label="Search requests, people, inventory"
        />
      </form>

      <div className="topbar__meta">
        <span className="topbar__date">{today}</span>
        <Link to="/notifications" className="topbar__notif">
          Notifications
          {notificationCount > 0 && <span className="topbar__badge">{notificationCount}</span>}
        </Link>
        <span className="topbar__user">
          <strong>{userName}</strong> / {userRole}
        </span>
      </div>
    </header>
  );
}
