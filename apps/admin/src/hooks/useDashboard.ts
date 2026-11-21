import { useCallback, useEffect, useState } from 'react';
import { getDashboardData } from '../services/dashboardService';
import type { DashboardData } from '../types/dashboard';

export function useDashboard(refreshMs = 60_000) {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async (initial = false) => {
    initial ? setLoading(true) : setRefreshing(true);
    setData(await getDashboardData());
    setLoading(false);
    setRefreshing(false);
  }, []);

  useEffect(() => {
    load(true);
    const id = setInterval(() => load(), refreshMs);
    return () => clearInterval(id);
  }, [load, refreshMs]);

  return { data, loading, refreshing, reload: () => load() };
}