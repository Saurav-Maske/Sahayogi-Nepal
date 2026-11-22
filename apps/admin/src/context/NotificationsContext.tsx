import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { listNotifications, type Notice } from '../services/notificationsService';

const READ_KEY = 'sahayogi-admin-read-notifications';
const readStoredIds = () => {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(READ_KEY) ?? '[]');
    return Array.isArray(value) ? value.filter((id): id is string => typeof id === 'string') : [];
  } catch { return []; }
};

type NotificationsState = {
  items: Notice[];
  readIds: string[];
  unreadCount: number;
  loading: boolean;
  error: string;
  reload: () => void;
  markRead: (id: string) => void;
  markAllRead: () => void;
};

const NotificationsContext = createContext<NotificationsState | null>(null);

export function NotificationsProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Notice[]>([]);
  const [readIds, setReadIds] = useState<string[]>(readStoredIds);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const hasLoaded = useRef(false);

  const reload = useCallback(() => {
    if (!hasLoaded.current) setLoading(true);
    void listNotifications().then((next) => {
      setItems(next);
      const activeIds = new Set(next.map((item) => item.id));
      setReadIds((current) => {
        const retained = current.filter((id) => activeIds.has(id));
        localStorage.setItem(READ_KEY, JSON.stringify(retained));
        return retained;
      });
      setError('');
      hasLoaded.current = true;
    }).catch((e) => setError(e instanceof Error ? e.message : 'Could not load notifications.'))
      .finally(() => setLoading(false));
  }, []);

  const saveReadIds = useCallback((ids: string[]) => {
    setReadIds(ids);
    localStorage.setItem(READ_KEY, JSON.stringify(ids));
    window.dispatchEvent(new CustomEvent('sahayogi-notifications-read', { detail: ids }));
  }, []);

  const markRead = useCallback((id: string) => saveReadIds([...new Set([...readIds, id])]), [readIds, saveReadIds]);
  const markAllRead = useCallback(() => saveReadIds([...new Set([...readIds, ...items.map((item) => item.id)])]), [items, readIds, saveReadIds]);

  useEffect(() => {
    reload();
    const poll = window.setInterval(reload, 60_000);
    const onStorage = (event: StorageEvent) => {
      if (event.key === READ_KEY) setReadIds(readStoredIds());
      if (event.key === 'sahayogi-admin-notification-preferences') reload();
    };
    const onReadChange = (event: Event) => {
      const ids = (event as CustomEvent<unknown>).detail;
      if (Array.isArray(ids)) setReadIds(ids.filter((id): id is string => typeof id === 'string'));
    };
    const onPreferencesChange = () => reload();
    window.addEventListener('storage', onStorage);
    window.addEventListener('sahayogi-notifications-read', onReadChange);
    window.addEventListener('sahayogi-notification-preferences', onPreferencesChange);
    return () => {
      window.clearInterval(poll);
      window.removeEventListener('storage', onStorage);
      window.removeEventListener('sahayogi-notifications-read', onReadChange);
      window.removeEventListener('sahayogi-notification-preferences', onPreferencesChange);
    };
  }, [reload]);

  const value = useMemo(() => ({
    items, readIds, unreadCount: items.reduce((count, item) => count + (readIds.includes(item.id) ? 0 : 1), 0),
    loading, error, reload, markRead, markAllRead,
  }), [items, readIds, loading, error, reload, markRead, markAllRead]);

  return <NotificationsContext.Provider value={value}>{children}</NotificationsContext.Provider>;
}

export function useNotifications() {
  const state = useContext(NotificationsContext);
  if (!state) throw new Error('useNotifications must be used inside <NotificationsProvider>');
  return state;
}
