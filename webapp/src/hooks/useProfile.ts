import { useCallback, useEffect, useState } from 'react';
import { getProfile } from '../lib/profile';
import type { UserProfile } from '../types/profile';

// Shared module-level cache and subscriber listeners to keep all instances (Header, Account, etc.) in sync
let cachedProfile: UserProfile | null = null;
let isFetched = false;
const listeners = new Set<(p: UserProfile | null) => void>();

export async function mutateProfile(): Promise<UserProfile | null> {
  const fresh = await getProfile();
  cachedProfile = fresh ? { ...fresh } : null;
  isFetched = true;
  listeners.forEach((fn) => fn(cachedProfile));
  return cachedProfile;
}

export function notifyProfileUpdate(updated: UserProfile) {
  cachedProfile = { ...updated };
  isFetched = true;
  listeners.forEach((fn) => fn(cachedProfile));
}

export function useProfile() {
  const [profile, setProfile] = useState<UserProfile | null>(cachedProfile);
  const [loading, setLoading] = useState(!isFetched);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const listener = (p: UserProfile | null) => {
      setProfile(p);
      setLoading(false);
    };
    listeners.add(listener);

    if (!isFetched) {
      mutateProfile()
        .then((p) => {
          setProfile(p);
          setError(null);
        })
        .catch((err) => {
          setError(err instanceof Error ? err.message : 'Failed to load profile');
        })
        .finally(() => {
          setLoading(false);
        });
    }

    return () => {
      listeners.delete(listener);
    };
  }, []);

  const refetch = useCallback(async () => {
    setLoading(true);
    try {
      await mutateProfile();
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load profile');
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { profile, loading, error, refetch, setProfile };
}
