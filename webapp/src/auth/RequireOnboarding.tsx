import React from 'react';
import { Navigate, Outlet } from 'react-router-dom';
import { useProfile } from '../hooks/useProfile';
import { hasCompletedOnboarding } from '../types/profile';

/**
 * app/router.dart:281-288相当。プロフィール取得済みでonboarding未完了なら
 * /onboardingへ強制遷移する。完了済みユーザーが/onboardingへ手動で行くのは
 * (mobile版の「Application > Onboarding再実行」相当として)ブロックしない。
 */
export const RequireOnboarding: React.FC = () => {
  const { profile, loading } = useProfile();

  if (loading) return null;
  if (!hasCompletedOnboarding(profile)) {
    return <Navigate to="/onboarding" replace />;
  }
  return <Outlet />;
};
