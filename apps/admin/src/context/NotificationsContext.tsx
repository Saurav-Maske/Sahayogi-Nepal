import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { listNotifications, type Notice } from '../services/notificationsService';

const READ_NOTICES_KEY = 'sahayogi.admin.notifications.read.v1';

function loadReadNoticeIds(): Set<string> | null {
  try {
    const saved = window.localStorage.getItem(READ_NOTICES_KEY);
    if (saved === null) return null;
    const parsed: unknown = JSON.parse(saved);
    return new Set(Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === 'string') : []);
  } catch {
    return null;
  }
}

function saveReadNoticeIds(ids: Set<string>) {
  try {
    window.localStorage.setItem(READ_NOTICES_KEY, JSON.stringify([...ids]));
  } catch {
    // Keep the current session usable when browser storage is unavailable.
  }
}

type NotificationsState = {
  items: Notice[];
  unreadCount: number;
  loading: boolean;
  error: string;
  reload: () => void;
  markRead: (id: string) => void;
};

const NotificationsContext = createContext<NotificationsState | null>(null);

export function NotificationsProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Notice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [readIds, setReadIds] = useState<Set<string>>(() => loadReadNoticeIds() ?? new Set());
  const readIdsRef = useRef(readIds);
  const hasReadBaseline = useRef(loadReadNoticeIds() !== null);
  const hasLoaded = useRef(false);

  const reload = useCallback(() => {
    if (!hasLoaded.current) setLoading(true);
    void listNotifications()
      .then((next) => {
        if (!hasReadBaseline.current) {
          const baseline = new Set(next.map((notice) => notice.id));
          readIdsRef.current = baseline;
          setReadIds(baseline);
          saveReadNoticeIds(baseline);
          hasReadBaseline.current = true;
        }
        setItems(next);
        setError('');
        hasLoaded.current = true;
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load operational notifications.'))
      .finally(() => setLoading(false));
  }, []);

  const markRead = useCallback((id: string) => {
    if (readIdsRef.current.has(id)) return;
    const updated = new Set(readIdsRef.current);
    updated.add(id);
    readIdsRef.current = updated;
    setReadIds(updated);
    saveReadNoticeIds(updated);
  }, []);

  useEffect(() => {
    reload();
    const poll = window.setInterval(reload, 30_000);
    const onVisibilityChange = () => {
      if (document.visibilityState === 'visible') reload();
    };
    document.addEventListener('visibilitychange', onVisibilityChange);
    return () => {
      window.clearInterval(poll);
      document.removeEventListener('visibilitychange', onVisibilityChange);
    };
  }, [reload]);

  const unreadCount = useMemo(
    () => items.reduce((count, notice) => count + (readIds.has(notice.id) ? 0 : 1), 0),
    [items, readIds],
  );
  const value = useMemo(
    () => ({ items, unreadCount, loading, error, reload, markRead }),
    [items, unreadCount, loading, error, reload, markRead],
  );
  return <NotificationsContext.Provider value={value}>{children}</NotificationsContext.Provider>;
}

export function useNotifications() {
  const state = useContext(NotificationsContext);
  if (!state) throw new Error('useNotifications must be used inside <NotificationsProvider>');
  return state;
}
