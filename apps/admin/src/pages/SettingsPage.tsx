import { useEffect, useState } from 'react';
import QuickAction from '../components/dashboard/QuickAction';
import FeedbackNotice from '../components/feedback/FeedbackNotice';
import { useAuth } from '../context/AuthContext';
import { hasSession } from '../services/session';
import { supabase } from '../supabase';
import '../styles/settings.css';

type DistrictConfig = {
  name?: string;
  center?: { lat?: number; lng?: number };
  zoom?: number;
};

export default function SettingsPage() {
  const { profile, profileError, session } = useAuth();
  const [district, setDistrict] = useState<DistrictConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    void (async () => {
      if (!(await hasSession())) {
        if (active) setError('Sign in as an administrator to load backend settings.');
        if (active) setLoading(false);
        return;
      }
      const { data, error: queryError } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'district')
        .maybeSingle();
      if (!active) return;
      if (queryError) setError(queryError.message);
      else if (!data?.value) setError('The backend has no district configuration.');
      else setDistrict(data.value as DistrictConfig);
      setLoading(false);
    })();
    return () => { active = false; };
  }, []);

  const center = district?.center;

  return <div className="settings-page">
    <header className="page__head">
      <div>
        <h1>Settings &amp; access</h1>
        <p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Settings&nbsp; / &nbsp;Backend configuration</p>
      </div>
      <div className="page__actions"><QuickAction/></div>
    </header>
    <div className="settings-grid">
      <section className="card access-card">
        <h2 className="card__title">Signed-in account</h2>
        <dl className="access-list">
          <div><dt>Name</dt><dd>{profile?.full_name || 'Not set in backend profile'}</dd></div>
          <div><dt>Email</dt><dd>{session?.user.email || 'Unavailable'}</dd></div>
          <div><dt>Role</dt><dd>{profile?.role || (profileError ? 'Profile unavailable' : 'Loading…')}</dd></div>
        </dl>
        {profileError && <FeedbackNotice variant="validation" title="Could not load account profile">{profileError}</FeedbackNotice>}
        <FeedbackNotice variant="info" title="Permission details are not available here">
          Sign-in role comes from the backend profile. The backend does not expose a settings screen for changing access permissions or location-retention policy.
        </FeedbackNotice>
      </section>
      <section className="card preference-card">
        <h2 className="card__title">Backend configuration</h2>
        {loading && <p className="empty">Loading settings…</p>}
        {error && <FeedbackNotice variant="validation" title="Backend settings unavailable">{error}</FeedbackNotice>}
        {district && <>
          <dl className="access-list settings-config-list">
            <div><dt>Configured district</dt><dd>{district.name || 'Unnamed district'}</dd></div>
            {center && <div><dt>Map center</dt><dd>{typeof center.lat === 'number' && typeof center.lng === 'number' ? `${center.lat.toFixed(4)}, ${center.lng.toFixed(4)}` : 'Not configured'}</dd></div>}
            <div><dt>Map zoom</dt><dd>{typeof district.zoom === 'number' ? district.zoom : 'Not configured'}</dd></div>
          </dl>
        </>}
        <FeedbackNotice variant="info" title="Notification preferences are not backend-backed">
          There is no backend setting or API for reading or saving notification preferences. The page does not save these choices locally.
        </FeedbackNotice>
      </section>
    </div>
  </div>;
}
