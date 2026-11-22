import { useEffect, useState } from 'react';
import QuickAction from '../components/dashboard/QuickAction';
import { supabase } from '../supabase';
import { hasSession } from '../services/session';
import '../styles/settings.css';

const PREFS_KEY = 'sahayogi-admin-notification-preferences';
const DISTRICT_KEY = 'sahayogi-admin-default-district';
const DEFAULT_PREFS = { shortage: true, requests: true, volunteers: true, inventory: true };
type PrefKey = keyof typeof DEFAULT_PREFS;

export default function SettingsPage() {
  const [districts, setDistricts] = useState<string[]>([]);
  const [district, setDistrict] = useState(() => localStorage.getItem(DISTRICT_KEY) ?? '');
  const [prefs, setPrefs] = useState(DEFAULT_PREFS);
  const [saved, setSaved] = useState(false);
  const [permissionsOpen, setPermissionsOpen] = useState(false);
  const [districtError, setDistrictError] = useState('');

  useEffect(() => {
    try { setPrefs({ ...DEFAULT_PREFS, ...JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}') }); } catch { /* defaults */ }
    let active = true;
    void (async () => {
      if (!(await hasSession())) { if (active) setDistrictError('Sign in as an administrator to load district settings.'); return; }
      const { data, error } = await supabase.from('districts').select('name').order('name');
      if (!active) return;
      if (error) { setDistrictError(error.message); return; }
      const names = (data ?? []).map((row) => row.name);
      setDistricts(names);
      setDistrict((current) => names.includes(current) ? current : (names[0] ?? ''));
    })();
    return () => { active = false; };
  }, []);

  function save() {
    localStorage.setItem(PREFS_KEY, JSON.stringify(prefs));
    if (district) localStorage.setItem(DISTRICT_KEY, district);
    window.dispatchEvent(new Event('sahayogi-notification-preferences'));
    setSaved(true);
    window.setTimeout(() => setSaved(false), 2600);
  }
  function toggle(key: PrefKey) { setPrefs((current) => ({ ...current, [key]: !current[key] })); setSaved(false); }

  return <div className="settings-page"><header className="page__head"><div><h1>Settings &amp; access</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Settings&nbsp; / &nbsp;All districts</p></div><div className="page__actions"><QuickAction/></div></header>
    <div className="settings-grid"><section className="card access-card"><h2 className="card__title">Access and privacy</h2><dl className="access-list"><div><dt>Admin role</dt><dd>Operations administrator</dd></div><div><dt>Identity documents</dt><dd>Restricted · access recorded</dd></div><div><dt>Exact addresses</dt><dd>Authorised staff only</dd></div><div><dt>Live location</dt><dd>Active assignments only</dd></div></dl><h3>Location retention</h3><p className="retention-copy">Volunteer locations older than 30 minutes are hidden.<br/>Fulfilled requests remain on the map for 12 hours.<br/>Location sharing stops when an assignment ends.</p><button className="btn permission-button" onClick={() => setPermissionsOpen(true)}>Manage permissions</button></section>
      <section className="card preference-card"><h2 className="card__title">Notification preferences</h2><div className="preference-list">{([['shortage', 'Missing quantity alerts'], ['requests', 'New requests and donations'], ['volunteers', 'Volunteer applications'], ['inventory', 'Low inventory alerts']] as [PrefKey, string][]).map(([key, label]) => <label key={key} className="preference-option"><input type="checkbox" checked={prefs[key]} onChange={() => toggle(key)}/><span>{label}</span></label>)}</div>
        {districtError && <p className="auth-error" role="alert">{districtError}</p>}<label className="district-setting"><span>Default district</span><select value={district} disabled={!districts.length} onChange={(e) => { setDistrict(e.target.value); setSaved(false); }}><option value="">{districts.length ? 'Choose a district' : 'No districts available'}</option>{districts.map((name) => <option key={name}>{name}</option>)}</select><small>Preferences are saved on this device; server sync is not available yet.</small></label><button className="btn btn--primary save-settings" disabled={!districts.length} onClick={save}>Save preferences</button>{saved && <p className="settings-saved" role="status">Preferences saved on this device.</p>}</section>
    </div>
    {permissionsOpen && <div className="settings-modal-backdrop" role="presentation" onMouseDown={(e) => { if (e.target === e.currentTarget) setPermissionsOpen(false); }}><section className="settings-modal" role="dialog" aria-modal="true" aria-labelledby="permission-title"><button className="settings-modal-close" aria-label="Close" onClick={() => setPermissionsOpen(false)}>×</button><h2 id="permission-title">Access permissions</h2><p>Admin access is checked against your signed-in Supabase account. Sensitive volunteer identity documents are available only to authorised admins, and access is recorded.</p><ul><li>Review volunteer applications and documents</li><li>Manage requests, assignments, and incidents</li><li>View exact service addresses for operations</li><li>View live locations only during active assignments</li></ul><p className="settings-modal-note">Permission changes require an administrator account update.</p><button className="btn btn--primary" onClick={() => setPermissionsOpen(false)}>Done</button></section></div>}
  </div>;
}
