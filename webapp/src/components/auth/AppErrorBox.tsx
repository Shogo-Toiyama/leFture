import React from 'react';

interface AppErrorBoxProps {
  actionName?: string;
  rawError: any;
}

export const AppErrorBox: React.FC<AppErrorBoxProps> = ({ actionName, rawError }) => {
  if (!rawError) return null;

  let message = '';
  if (typeof rawError === 'string') {
    message = rawError;
  } else if (rawError instanceof Error) {
    message = rawError.message;
  } else if (rawError?.message) {
    message = String(rawError.message);
  } else {
    message = String(rawError);
  }

  // Supabase等の一般的なエラーメッセージを親しみやすく整形
  if (message.includes('Invalid login credentials')) {
    message = 'Invalid email or password. Please try again.';
  } else if (message.includes('User already registered')) {
    message = 'An account with this email already exists. Please sign in instead.';
  }

  return (
    <div className="app-error-box" role="alert">
      <svg className="app-error-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <circle cx="12" cy="12" r="10" />
        <line x1="12" y1="8" x2="12" y2="12" />
        <line x1="12" y1="16" x2="12.01" y2="16" />
      </svg>
      <div className="app-error-content">
        {actionName && <div className="app-error-action">Error {actionName}</div>}
        <div className="app-error-message">{message}</div>
      </div>
    </div>
  );
};
