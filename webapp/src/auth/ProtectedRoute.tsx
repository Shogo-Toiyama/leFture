import React from 'react';
import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from './AuthProvider';

export const ProtectedRoute: React.FC = () => {
  const { session, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return null;
  }

  if (!session) {
    return <Navigate to="/sign-in" state={{ from: location }} replace />;
  }

  return <Outlet />;
};
