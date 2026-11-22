import { useCallback, useEffect, useState } from 'react';
import { getAnalyticsData } from '../services/analyticsService';
import type { AnalyticsData } from '../types/analytics';

export function useAnalytics() {
  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try { setData(await getAnalyticsData()); setError(''); }
    catch (e) { setError(e instanceof Error ? e.message : 'Could not load analytics.'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  return { data, loading, error, reload: load };
}
