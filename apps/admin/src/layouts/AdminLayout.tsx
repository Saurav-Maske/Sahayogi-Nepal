import { Outlet } from 'react-router-dom';
import AdminSidebar from '../components/layout/AdminSidebar';
import AdminTopbar from '../components/layout/AdminTopbar';
import { useAuth } from '../context/AuthContext';
import { NotificationsProvider } from '../context/NotificationsContext';

export default function AdminLayout() {
  return <NotificationsProvider><AdminShell /></NotificationsProvider>;
}

function AdminShell() {
  const { profile, session, signOut } = useAuth();

  const role = profile?.role ? profile.role.charAt(0).toUpperCase() + profile.role.slice(1) : 'Admin';

  return (
    <div className="shell">
      <AdminSidebar />
      <div className="shell__main">
        <AdminTopbar
          userEmail={session?.user.email || ''}
          userRole={role}
          onSignOut={signOut}
        />
        <main className="page">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
