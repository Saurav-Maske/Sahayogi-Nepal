import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { listNotifications, type Notice } from '../services/notificationsService';

type NotificationsState = {
  items: Notice[];
  loading: boolean;
  error: string;
  reload: () => void;
};

const NotificationsContext = createContext<NotificationsState | null>(null);

export function NotificationsProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Notice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const hasLoaded = useRef(false);

  const reload = useCallback(() => {
    if (!hasLoaded.current) setLoading(true);
    void listNotifications()
      .then((next) => { setItems(next); setError(''); hasLoaded.current = true; })
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load operational notifications.'))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    reload();
    const poll = window.setInterval(reload, 60_000);
    return () => window.clearInterval(poll);
  }, [reload]);

  const value = useMemo(() => ({ items, loading, error, reload }), [items, loading, error, reload]);
  return <NotificationsContext.Provider value={value}>{children}</NotificationsContext.Provider>;
}

export function useNotifications() {
  const state = useContext(NotificationsContext);
  if (!state) throw new Error('useNotifications must be used inside <NotificationsProvider>');
  return state;
}
