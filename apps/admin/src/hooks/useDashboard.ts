import { useCallback, useEffect, useState } from 'react';
import { getDashboardData } from '../services/dashboardService';
import type { DashboardData } from '../types/dashboard';

export function useDashboard(refreshMs = 60_000) {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(async (initial = false) => {
    initial ? setLoading(true) : setRefreshing(true);
    try { setData(await getDashboardData()); setError(''); }
    catch (e) { setError(e instanceof Error ? e.message : 'Could not load the operations dashboard.'); }
    finally { setLoading(false); setRefreshing(false); }
  }, []);

  useEffect(() => {
    load(true);
    const id = setInterval(() => load(), refreshMs);
    return () => clearInterval(id);
  }, [load, refreshMs]);

  return { data, loading, refreshing, error, reload: () => load() };
}
