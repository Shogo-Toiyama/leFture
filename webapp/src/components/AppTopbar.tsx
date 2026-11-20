import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useProfile } from '../hooks/useProfile';
import { getCreditSummary } from '../lib/billing';
import { toDisplayCredits } from '../types/billing';
import { AvatarImage } from './AvatarImage';
import { RecordingChip } from './recording/RecordingChip';

const RING_RADIUS = 15;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

interface GaugeData {
  monthlyFraction: number;
  totalFraction: number;
  isDepleted: boolean;
}

/**
 * 画面上部のヘッダー(ロゴ・録音中のタイマー・クレジットゲージ付きアバター)。
 * アプリの枠(Layout)の画面は暗い宇宙テーマ、Layoutの外の全画面の読み物
 * (Deep Notes・復習カード・文字起こし・チャット)は紙テーマ(variant="light")で同じものを出す。
 * PCの音の録音中は、ロゴのすぐ右にタイマー(RecordingChip)が入る。
 */
export const AppTopbar: React.FC<{ variant?: 'dark' | 'light'; centerTitle?: string }> = ({
  variant = 'dark',
  centerTitle,
}) => {
  const { profile } = useProfile();
  const [gaugeData, setGaugeData] = useState<GaugeData | null>(null);

  useEffect(() => {
    getCreditSummary()
      .then((summary) => {
        const totalBalance = toDisplayCredits(summary.credit_balance);
        const monthlyAllocation = toDisplayCredits(summary.monthly_allocation);
        const extraBalance = toDisplayCredits(summary.extra_credit_balance);

        const isDepleted = !summary.has_active_plan || totalBalance <= 0;
        let monthlyFraction: number;
        let totalFraction: number;

        if (isDepleted) {
          monthlyFraction = 0.03;
          totalFraction = 0.03;
        } else {
          const monthlyBalance = Math.max(0, Math.min(monthlyAllocation, totalBalance - extraBalance));
          const maxCapacity = Math.max(monthlyAllocation, totalBalance);
          if (maxCapacity <= 0) {
            monthlyFraction = 0.0;
            totalFraction = 0.0;
          } else {
            monthlyFraction = Math.max(0, Math.min(1, monthlyBalance / maxCapacity));
            totalFraction = Math.max(0, Math.min(1, totalBalance / maxCapacity));
          }
        }

        setGaugeData({ monthlyFraction, totalFraction, isDepleted });
      })
      .catch(() => setGaugeData(null));
  }, []);

  return (
    <header className={`app-topbar ${variant === 'light' ? 'is-light' : ''} ${centerTitle ? 'has-center-title' : ''}`}>
      <div className="app-topbar-left">
        <Link to="/" className="app-topbar-home" title="leFture Home">
          <img src="/img/logo-icon.webp" alt="leFture Logo" className="app-topbar-logo" />
          <span className="app-topbar-brand-name">
            leFture<span className="app-topbar-brand-suffix"> app</span>
          </span>
        </Link>
        <RecordingChip />
      </div>

      {centerTitle && (
        <span className="app-topbar-title" title={centerTitle}>{centerTitle}</span>
      )}

      <div className="app-topbar-account">
        <Link to="/account" className="credit-gauge" aria-label="Account">
          {gaugeData !== null && (
            <svg width="34" height="34" viewBox="0 0 34 34">
              <circle className="credit-gauge-track" cx="17" cy="17" r={RING_RADIUS} strokeWidth="2.5" />
              {gaugeData.totalFraction > 0 && (
                <circle
                  className={gaugeData.isDepleted ? 'credit-gauge-fill-depleted' : 'credit-gauge-fill-extra'}
                  cx="17"
                  cy="17"
                  r={RING_RADIUS}
                  strokeWidth="2.5"
                  strokeDasharray={RING_CIRCUMFERENCE}
                  strokeDashoffset={RING_CIRCUMFERENCE * (1 - gaugeData.totalFraction)}
                />
              )}
              {!gaugeData.isDepleted && gaugeData.monthlyFraction > 0 && (
                <circle
                  className="credit-gauge-fill-monthly"
                  cx="17"
                  cy="17"
                  r={RING_RADIUS}
                  strokeWidth="2.5"
                  strokeDasharray={RING_CIRCUMFERENCE}
                  strokeDashoffset={RING_CIRCUMFERENCE * (1 - gaugeData.monthlyFraction)}
                />
              )}
            </svg>
          )}
          <AvatarImage
            key={profile?.avatar_url || 'default'}
            avatarUrl={profile?.avatar_url ?? null}
            username={profile?.username}
            size={25}
          />
        </Link>
      </div>
    </header>
  );
};
