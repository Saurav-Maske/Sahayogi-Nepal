import { useCallback, useEffect, useState } from 'react';
import { getRequest, listRequests } from '../services/requestsService';
import type { DetailResult, ListResult, RequestFilters } from '../types/requests';

export function useAsync<T>(load: () => Promise<T>, deps: unknown[]) {
  const [state, setState] = useState<{ data: T | null; loading: boolean; error: string | null }>({ data: null, loading: true, error: null });
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let off = false;
    setState((s) => ({ ...s, loading: true, error: null })); // keep old data on screen while reloading
    load()
      .then((data) => !off && setState({ data, loading: false, error: null }))
      .catch((e) => !off && setState({ data: null, loading: false, error: e?.message ?? String(e) }));
    return () => { off = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);

  return { ...state, reload: useCallback(() => setTick((t) => t + 1), []) };
}

export const useRequestList = (f: RequestFilters) => useAsync<ListResult>(() => listRequests(f), [JSON.stringify(f)]);
export const useRequest = (id: string) => useAsync<DetailResult>(() => getRequest(id), [id]);