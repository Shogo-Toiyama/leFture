import React from 'react';
import { X } from 'lucide-react';

interface PvHeaderSkeletonProps {
  /** ツールバー行(復習カード/詳細ノートで表示する2段目)も出すか。 */
  withToolRow?: boolean;
  /** さらに下に続く行(復習カードの進捗セグメントなど)。 */
  children?: React.ReactNode;
  /** true の場合、自前の <header className="pv-top"> で囲まず中身だけ返す(呼び出し側が既にheaderを持つ場合)。 */
  bare?: boolean;
}

/** 出典シート・復習カード・詳細ノートで共通の .pv-top ヘッダーのスケルトン。 */
export const PvHeaderSkeleton: React.FC<PvHeaderSkeletonProps> = ({ withToolRow = true, children, bare = false }) => {
  const content = (
    <>
      <div className="pv-top-row">
        <span className="pv-icon-btn" style={{ opacity: 0.4, pointerEvents: 'none' }}>
          <X size={20} />
        </span>
        <span className="skeleton" style={{ width: 120, height: 16, borderRadius: 6 }} />
        <span style={{ width: 36 }} />
      </div>
      {withToolRow && (
        <div className="pv-tool-row">
          <span className="skeleton" style={{ width: 19, height: 19, borderRadius: '50%' }} />
          <span className="pv-divider" />
          <span className="skeleton" style={{ width: 18, height: 18, borderRadius: '50%' }} />
          <span className="skeleton" style={{ width: 44, height: 18, borderRadius: 999, marginLeft: 8 }} />
          <span className="pv-tool-spacer" />
          <span className="skeleton" style={{ width: 40, height: 13, borderRadius: 6 }} />
        </div>
      )}
      {children}
    </>
  );

  if (bare) return content;
  return <header className="pv-top">{content}</header>;
};
