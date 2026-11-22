import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useNotifications } from '../../context/NotificationsContext';

interface Props {
  userEmail: string;
  userRole: string;
  onSignOut: () => void;
}

export default function AdminTopbar({ userEmail, userRole, onSignOut }: Props) {
  const navigate = useNavigate();
  const [query, setQuery] = useState('');
  const [profileOpen, setProfileOpen] = useState(false);
  const profileRef = useRef<HTMLDivElement>(null);
  const { unreadCount } = useNotifications();

  const today = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

  const onSearch = (e: FormEvent) => {
    e.preventDefault();
    const q = query.trim();
    if (q) navigate(`/requests?q=${encodeURIComponent(q)}`);
  };

  useEffect(() => {
    if (!profileOpen) return;
    const onPointer = (event: PointerEvent) => {
      if (!profileRef.current?.contains(event.target as Node)) setProfileOpen(false);
    };
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') setProfileOpen(false); };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onPointer);
      document.removeEventListener('keydown', onKey);
    };
  }, [profileOpen]);

  const initials = 'A';

  return (
    <header className="topbar">
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
        <Link
          to="/notifications"
          className="topbar__notif"
          aria-label={unreadCount ? `Notifications, ${unreadCount} unread` : 'Notifications'}
          title={unreadCount ? `${unreadCount} unread notifications` : 'Notifications'}
        >
          <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          {unreadCount > 0 && <span className="topbar__notif-count" aria-hidden="true">{unreadCount}</span>}
        </Link>
        <div className="topbar__profile" ref={profileRef}>
          <button className="topbar__profile-trigger" type="button" aria-haspopup="menu" aria-expanded={profileOpen} onClick={() => setProfileOpen((open) => !open)}>
            <span className="topbar__avatar" aria-hidden="true">{initials}</span>
            <span className="topbar__profile-label">Admin</span>
            <svg className="topbar__chevron" viewBox="0 0 12 12" fill="none" aria-hidden="true"><path d="m3 4.5 3 3 3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>
          </button>
          {profileOpen && <div className="topbar__profile-menu" role="menu">
            <div className="topbar__profile-summary">
              <span className="topbar__avatar topbar__avatar--large" aria-hidden="true">{initials}</span>
              <span><strong>{userEmail || 'Admin account'}</strong><small>{userRole}</small></span>
            </div>
            <Link to="/settings" role="menuitem" onClick={() => setProfileOpen(false)}>Settings</Link>
            <button type="button" role="menuitem" onClick={() => { setProfileOpen(false); onSignOut(); }}>Sign out</button>
          </div>}
        </div>
      </div>
    </header>
  );
}
