import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import AdminSidebar from '../components/layout/AdminSidebar';
import AdminTopbar from '../components/layout/AdminTopbar';

export default function AdminLayout() {
  const [navOpen, setNavOpen] = useState(false);

  // TODO: replace with the signed-in admin from Supabase Auth + unread notifications count
  const user = { name: 'Anisha K.', role: 'Admin' };
  const unread = 3;

  return (
    <div className="shell">
      <AdminSidebar open={navOpen} onNavigate={() => setNavOpen(false)} />
      {navOpen && <div className="shell__scrim" onClick={() => setNavOpen(false)} />}
      <div className="shell__main">
        <AdminTopbar
          notificationCount={unread}
          userName={user.name}
          userRole={user.role}
          onMenuClick={() => setNavOpen(true)}
        />
        <main className="page">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
