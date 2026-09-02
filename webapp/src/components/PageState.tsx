import React from 'react';

interface PageStateProps {
  kind: 'loading' | 'error' | 'empty';
  title?: string;
  message?: string;
  action?: React.ReactNode;
}

/** ローディング/エラー/空状態の共通表示。ローディングはスケルトンで表す。 */
export const PageState: React.FC<PageStateProps> = ({ kind, title, message, action }) => {
  if (kind === 'loading') {
    return (
      <div className="page-skeleton" aria-busy="true" aria-live="polite">
        <span className="skeleton skeleton-title" />
        <span className="skeleton skeleton-line" />
        <span className="skeleton skeleton-line" />
        <span className="skeleton skeleton-line short" />
      </div>
    );
  }

  return (
    <div className={`page-state ${kind === 'error' ? 'page-state-error' : ''}`}>
      <span className="page-state-glyph" aria-hidden="true">
        {kind === 'error' ? '!' : '✦'}
      </span>
      <h2>{title ?? (kind === 'error' ? 'Something went wrong' : 'Nothing here yet')}</h2>
      {message && <p>{message}</p>}
      {action && <div className="page-state-action">{action}</div>}
    </div>
  );
};
