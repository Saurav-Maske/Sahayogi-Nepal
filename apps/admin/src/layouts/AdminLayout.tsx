import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import AdminSidebar from '../components/layout/AdminSidebar';
import AdminTopbar from '../components/layout/AdminTopbar';
import { useAuth } from '../context/AuthContext';
import { NotificationsProvider } from '../context/NotificationsContext';

export default function AdminLayout() {
  return <NotificationsProvider><AdminShell /></NotificationsProvider>;
}

function AdminShell() {
  const [navOpen, setNavOpen] = useState(false);
  const { profile, session, signOut } = useAuth();

  const name = profile?.full_name || session?.user.email || 'Admin';
  const role = profile?.role ? profile.role.charAt(0).toUpperCase() + profile.role.slice(1) : 'Admin';

  return (
    <div className="shell">
      <AdminSidebar open={navOpen} onNavigate={() => setNavOpen(false)} />
      {navOpen && <div className="shell__scrim" onClick={() => setNavOpen(false)} />}
      <div className="shell__main">
        <AdminTopbar
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
