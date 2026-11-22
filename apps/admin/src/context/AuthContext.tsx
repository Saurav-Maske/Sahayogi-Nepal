import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../supabase';

/** Value of profiles.role for admins. Check the user_role enum in the migration. */
export const ADMIN_ROLE = 'admin';

/**
 * DEV ONLY: set VITE_DEV_BYPASS_AUTH=true in .env to skip login while there is no admin user.
 * Ignored in production builds (import.meta.env.DEV is false there).
 * No real Supabase session exists in bypass mode, so database-backed pages will show an access error.
 */
const DEV_BYPASS = import.meta.env.DEV && import.meta.env.VITE_DEV_BYPASS_AUTH === 'true';
const BYPASS_SESSION = { user: { id: 'dev-bypass', email: 'dev@localhost' } } as unknown as Session;

interface Profile {
  full_name: string | null;
  role: string;
}

interface AuthState {
  session: Session | null;
  profile: Profile | null;
  profileError: string | null;
  isAdmin: boolean;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<string | null>; // returns an error message or null
  signOut: () => Promise<void>;
  devBypassAvailable: boolean; // dev only: VITE_DEV_BYPASS_AUTH=true
  enterDevMode: () => void;
}

const BYPASS_PROFILE: Profile = { full_name: 'Dev Admin', role: ADMIN_ROLE };
const BYPASS_OFF_KEY = 'dev-bypass-off';

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [sessionLoading, setSessionLoading] = useState(true);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [profileUid, setProfileUid] = useState<string | null>(null); // which user the profile belongs to
  // bypass can be switched off with Sign out and back on from the login page
  const [bypassOn, setBypassOn] = useState(() => sessionStorage.getItem(BYPASS_OFF_KEY) !== '1');

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setSessionLoading(false);
    });
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);

  const uid = session?.user.id ?? null;

  useEffect(() => {
    if (!uid) {
      setProfile(null);
      setProfileError(null);
      setProfileUid(null);
      return;
    }
    let cancelled = false;
    supabase
      .from('profiles')
      .select('full_name, role')
      .eq('id', uid)
      .single()
      .then(({ data, error }) => {
        if (cancelled) return;
        setProfile((data as Profile | null) ?? null);
        setProfileError(error ? error.message : null);
        setProfileUid(uid);
      });
    return () => { cancelled = true; };
  }, [uid]);

  const realValue = useMemo<AuthState>(() => ({
    session,
    profile,
    profileError,
    isAdmin: profile?.role === ADMIN_ROLE,
    loading: sessionLoading || (!!uid && profileUid !== uid),
    signIn: async (email, password) => {
      const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (!error) return null;
      return /invalid login/i.test(error.message) ? 'Email or password is incorrect.' : error.message;
    },
    signOut: async () => { await supabase.auth.signOut(); },
    devBypassAvailable: DEV_BYPASS,
    enterDevMode: () => { sessionStorage.removeItem(BYPASS_OFF_KEY); setBypassOn(true); },
  }), [session, profile, profileError, sessionLoading, uid, profileUid]);

  const value: AuthState = DEV_BYPASS && bypassOn
    ? {
        ...realValue,
        session: BYPASS_SESSION,
        profile: BYPASS_PROFILE,
        profileError: null,
        isAdmin: true,
        loading: false,
        signOut: async () => {
          sessionStorage.setItem(BYPASS_OFF_KEY, '1');
          setBypassOn(false);
        },
      }
    : realValue;

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
