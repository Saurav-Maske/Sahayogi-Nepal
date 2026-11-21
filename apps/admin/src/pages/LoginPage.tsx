import { FormEvent, useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import '../styles/login.css';

export default function LoginPage() {
  const { session, isAdmin, loading, signIn, devBypassAvailable, enterDevMode } = useAuth();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from ?? '/';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (!loading && session && isAdmin) return <Navigate to={from} replace />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    const message = await signIn(email, password);
    if (message) setError(message);
    setSubmitting(false);
  };

  return (
    <div className="login">
      <section className="login__brand">
        <h2>SAHAYOGI NEPAL</h2>
        <p className="login__console">OPERATIONS CONSOLE</p>
        <p className="login__tagline">Support that reaches further.</p>
      </section>

      <section className="login__panel">
        <form className="auth-card" onSubmit={onSubmit} noValidate>
          <h1>Sign in</h1>
          <p className="auth-muted">Use your administrator account to open the console.</p>

          <label className="field">
            <span>Email</span>
            <input type="email" autoComplete="username" value={email}
              onChange={(e) => setEmail(e.target.value)} required autoFocus />
          </label>

          <label className="field">
            <span>Password</span>
            <input type="password" autoComplete="current-password" value={password}
              onChange={(e) => setPassword(e.target.value)} required />
          </label>

          {error && <p className="auth-error" role="alert">{error}</p>}

          <button className="btn auth-submit auth-submit--primary" type="submit"
            disabled={submitting || !email || !password}>
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>

          {devBypassAvailable && (
            <button type="button" className="btn auth-submit" onClick={enterDevMode}>
              Continue as Dev Admin (dev only)
            </button>
          )}
        </form>
      </section>
    </div>
  );
}