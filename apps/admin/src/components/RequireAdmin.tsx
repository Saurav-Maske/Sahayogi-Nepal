import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import '../styles/login.css';

export default function RequireAdmin() {
  const { session, isAdmin, loading, profileError, signOut } = useAuth();
  const location = useLocation();

  if (loading) {
    return <div className="auth-screen" aria-busy="true"><p className="auth-muted">Loading…</p></div>;
  }

  if (!session) return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />;

  if (!isAdmin) {
    return (
      <div className="auth-screen">
        <div className="auth-card">
          <h1>No admin access</h1>
          <p className="auth-muted">
            {profileError
              ? `We couldn't read your profile: ${profileError}`
              : "This account isn't an administrator. Sign in with an admin account to continue."}
          </p>
          <button className="btn auth-submit" onClick={signOut}>Sign out</button>
        </div>
      </div>
    );
  }

  return <Outlet />;
}