import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import AdminSidebar from '../components/layout/AdminSidebar';
import AdminTopbar from '../components/layout/AdminTopbar';
import { useAuth } from '../context/AuthContext';

export default function AdminLayout() {
  const [navOpen, setNavOpen] = useState(false);
  const { profile, session, signOut } = useAuth();

  // TODO: replace with the real unread count once a notifications table exists
  const unread = 3;

  const name = profile?.full_name || session?.user.email || 'Admin';
  const role = profile?.role ? profile.role.charAt(0).toUpperCase() + profile.role.slice(1) : 'Admin';

  return (
    <div className="shell">
      <AdminSidebar open={navOpen} onNavigate={() => setNavOpen(false)} />
      {navOpen && <div className="shell__scrim" onClick={() => setNavOpen(false)} />}
      <div className="shell__main">
        <AdminTopbar
          notificationCount={unread}
          userName={name}
          userRole={role}
          onMenuClick={() => setNavOpen(true)}
          onSignOut={signOut}
        />
        <main className="page">
          <Outlet />
        </main>
      </div>
    </div>
  );
}