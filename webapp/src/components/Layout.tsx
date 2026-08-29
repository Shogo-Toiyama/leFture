import React from 'react';
import { Link, Outlet } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { supabase } from '../lib/supabase';

export const Layout: React.FC = () => {
  const { user } = useAuth();

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-header-nav">
          <Link to="/" className="app-header-brand">
            leFture
          </Link>
          <Link to="/courses">Courses</Link>
        </div>
        {user && (
          <div className="app-header-account">
            <Link to="/account">{user.email}</Link>
            <button type="button" onClick={() => supabase.auth.signOut()}>
              Sign out
            </button>
          </div>
        )}
      </header>
      <main className="app-main">
        <Outlet />
      </main>
    </div>
  );
};
