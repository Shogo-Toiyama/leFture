import React, { useEffect } from 'react';
import { X } from 'lucide-react';

export interface AdaptiveSheetProps {
  open: boolean;
  onClose: () => void;
  title?: React.ReactNode;
  subtitle?: React.ReactNode;
  children: React.ReactNode;
  width?: string;
  className?: string;
  /** PC幅でのスライド方向。既定は右から。モバイル幅では常に下から。 */
  side?: 'left' | 'right';
  /** 背景の暗転・ぼかしスクリムを表示するか。既定は true。false の場合は暗くぼかす視覚効果を無効化。 */
  showScrim?: boolean;
  /** サイドシート表示時、背面の操作（マップ操作など）を許可するか。既定は false。 */
  allowBackdropInteractionOnSide?: boolean;
  /** 機能しないグラブバーを非表示にするか。既定は true (非表示)。 */
  hideGrabBar?: boolean;
}

/**
 * 画面幅に応じて挙動を切り替えるレスポンシブシート:
 * - PC (> 900px): 右側からスライドインするサイドシート (Side Drawer)
 * - モバイル (<= 900px): 下からスライドアップするボトムシート (Bottom Sheet)
 */
export const AdaptiveSheet: React.FC<AdaptiveSheetProps> = ({
  open,
  onClose,
  title,
  subtitle,
  children,
  width,
  className = '',
  side = 'right',
  showScrim = true,
  allowBackdropInteractionOnSide = false,
  hideGrabBar = true,
}) => {
  useEffect(() => {
    if (!open) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);

    // 背面操作を許可するサイドシート時はスクロール抑制を行わない
    let prevOverflow: string | undefined;
    const isSideMode = typeof window !== 'undefined' && window.matchMedia('(min-width: 901px)').matches;
    if (!(allowBackdropInteractionOnSide && isSideMode)) {
      prevOverflow = document.body.style.overflow;
      document.body.style.overflow = 'hidden';
    }

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      if (prevOverflow !== undefined) {
        document.body.style.overflow = prevOverflow;
      }
    };
  }, [open, onClose, allowBackdropInteractionOnSide]);

  if (!open) return null;

  return (
    <div
      className={`adaptive-sheet-portal ${!showScrim ? 'has-no-scrim' : ''} ${
        allowBackdropInteractionOnSide ? 'interactive-side' : ''
      }`}
      role="dialog"
      aria-modal={allowBackdropInteractionOnSide ? 'false' : 'true'}
    >
      {/* 背景スクリム */}
      <div className="adaptive-sheet-scrim" onClick={onClose} aria-hidden="true" />

      {/* シート本体 */}
      <div
        className={`adaptive-sheet-container is-${side} ${className}`}
        style={width ? ({ '--sheet-width': width } as React.CSSProperties) : undefined}
      >
        {/* モバイル用グラブハンドル (機能しないため既定は非表示) */}
        {!hideGrabBar && (
          <div className="adaptive-sheet-grab-bar" aria-hidden="true">
            <span className="adaptive-sheet-grab-handle" />
          </div>
        )}

        {/* ヘッダー */}
        {(title || subtitle) && (
          <div className="adaptive-sheet-head">
            <div className="adaptive-sheet-head-text">
              {title && <h2 className="adaptive-sheet-title">{title}</h2>}
              {subtitle && <p className="adaptive-sheet-subtitle">{subtitle}</p>}
            </div>
            <button
              type="button"
              className="adaptive-sheet-close-btn"
              onClick={onClose}
              aria-label="Close"
            >
              <X size={20} />
            </button>
          </div>
        )}

        {/* スクロール領域 */}
        <div className="adaptive-sheet-body">{children}</div>
      </div>
    </div>
  );
};
