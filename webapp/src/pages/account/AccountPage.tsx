import React, { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  User,
  Sparkles,
  Flag,
  ChevronRight,
  Edit2,
  Check,
  X,
  Bookmark,
  Heart,
  ThumbsDown,
  Megaphone,
  Trash2,
  Radio,
  Rocket,
  GraduationCap,
  Mic,
  Globe,
  Shield,
  ShieldCheck,
  Gavel,
  Mail,
  Lock,
  LogOut,
  UserX,
  ExternalLink,
} from 'lucide-react';
import { CreditStarIcon } from '../../components/icons/CreditStarIcon';
import { useProfile } from '../../hooks/useProfile';
import { useAuth } from '../../auth/AuthProvider';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { updateProfileFields } from '../../lib/profile';
import { hasEmailIdentity } from '../../lib/account';
import { supabase } from '../../lib/supabase';
import { toDisplayCredits } from '../../types/billing';
import { AvatarImage } from '../../components/AvatarImage';
import { AccountPageSkeleton } from '../../components/account/AccountPageSkeleton';
import { AnnouncementsModal } from '../../components/modals/AnnouncementsModal';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { useAnnouncements } from '../../hooks/useAnnouncements';
import { useLanguage } from '../../i18n/LanguageContext';
import { ChangeAvatarSheet } from '../../components/account/ChangeAvatarSheet';
import { LanguageSelectionSheet, type LanguageSheetMode } from '../../components/account/LanguageSelectionSheet';
import {
  ChangePasswordSheet,
  ChangeEmailSheet,
  DeleteAccountModal,
} from '../../components/account/AccountAuthSheets';

function getLanguageLabel(code: string | undefined): string {
  switch (code) {
    case 'en':
      return 'English';
    case 'ja':
      return '日本語';
    case 'zh':
      return '中文';
    case 'es':
      return 'Español';
    case 'fr':
      return 'Français';
    case 'de':
      return 'Deutsch';
    case 'ko':
      return '한국어';
    default:
      return '日本語';
  }
}

export const AccountPage: React.FC = () => {
  const { profile, loading, refetch } = useProfile();
  const { user } = useAuth();
  const navigate = useNavigate();
  const { language } = useLanguage();
  const isJa = language === 'ja';

  const { summary, loading: creditLoading } = useCreditSummary(false);

  // ── インライン名前編集 ─────────────────────────────────────
  const displayName = profile?.username || (isJa ? '探検者' : 'Explorer');
  const [isEditingName, setIsEditingName] = useState(false);
  const [nameInput, setNameInput] = useState(displayName);
  const [savingName, setSavingName] = useState(false);

  useEffect(() => {
    setNameInput(displayName);
  }, [displayName]);

  const handleSaveName = async () => {
    const trimmed = nameInput.trim();
    if (!trimmed || trimmed === displayName) {
      setIsEditingName(false);
      setNameInput(displayName);
      return;
    }
    setSavingName(true);
    try {
      await updateProfileFields({ username: trimmed });
      await refetch();
      setIsEditingName(false);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to update username');
    } finally {
      setSavingName(false);
    }
  };

  // ── シート/モーダルの開閉状態 ─────────────────────────────
  const [avatarSheetOpen, setAvatarSheetOpen] = useState(false);
  const [langSheetMode, setLangSheetMode] = useState<LanguageSheetMode | null>(null);
  const [passwordSheetOpen, setPasswordSheetOpen] = useState(false);
  const [emailSheetOpen, setEmailSheetOpen] = useState(false);
  const [deleteModalOpen, setDeleteModalOpen] = useState(false);

  // カスタム確認モーダル状態
  const [showSignOutModal, setShowSignOutModal] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 3500);
  };

  // トランスミッション用
  const [announcementsModalOpen, setAnnouncementsModalOpen] = useState(false);
  const { announcements } = useAnnouncements();

  const handleTransmissionsClick = () => {
    if (!announcements || announcements.length === 0) {
      showToast(
        language === 'ja'
          ? '現在利用可能なお知らせはありません。'
          : 'No transmissions available at this time.'
      );
    } else {
      setAnnouncementsModalOpen(true);
    }
  };

  const handleTutorialClick = async () => {
    try {
      const { data: userData } = await supabase.auth.getUser();
      const uid = userData?.user?.id;
      if (uid) {
        const { data: lectures } = await supabase
          .from('lectures')
          .select('id, course_id, metadata')
          .eq('user_id', uid)
          .is('deleted_at', null);

        const tut = lectures?.find((l) => (l.metadata as Record<string, unknown> | null)?.is_tutorial === true);
        if (tut) {
          navigate(`/lectures/${tut.id}`);
          return;
        }
      }
    } catch (err) {
      console.error('Failed to find tutorial lecture:', err);
    }
    navigate('/onboarding');
  };

  const isEmailUser = hasEmailIdentity(user);

  // ── クレジット計算 (Flutter _CreditCardContent 準拠) ────────
  const totalBalance = summary?.has_active_plan ? toDisplayCredits(summary.credit_balance) : 0;
  const monthlyAllocation = summary?.has_active_plan ? toDisplayCredits(summary.monthly_allocation) : 0;
  const extraBalance = summary?.has_active_plan ? toDisplayCredits(summary.extra_credit_balance) : 0;

  const monthlyBalance =
    totalBalance < 0
      ? totalBalance
      : Math.max(0, Math.min(monthlyAllocation, totalBalance - extraBalance));
  const maxCapacity = Math.max(monthlyAllocation, totalBalance);
  const isDepleted = totalBalance <= 0;

  const monthlyFraction = isDepleted
    ? 0.03
    : maxCapacity <= 0
      ? 0
      : Math.max(0, Math.min(1, monthlyBalance / maxCapacity));
  const totalFraction = isDepleted
    ? 0.03
    : maxCapacity <= 0
      ? 0
      : Math.max(0, Math.min(1, totalBalance / maxCapacity));

  // ── サインアウト実行 ───────────────────────────────────────
  const handleConfirmSignOut = async () => {
    await supabase.auth.signOut();
    navigate('/sign-in', { replace: true });
  };

  if (loading) return <AccountPageSkeleton />;

  return (
    <div className="account-page">
      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          HEADER SECTION (Avatar + Name & Credit Card)
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <div className="account-top-header">
        <div className="account-user-row">
          {/* Avatar with edit pencil badge */}
          <div
            className="account-avatar-wrapper"
            onClick={() => setAvatarSheetOpen(true)}
            role="button"
            tabIndex={0}
            title={isJa ? 'アバターを変更' : 'Change avatar'}
          >
            <AvatarImage avatarUrl={profile?.avatar_url ?? null} size={72} username={displayName} />
            <span className="account-avatar-edit-badge">
              <Edit2 size={12} color="#000" />
            </span>
          </div>

          {/* Username Inline Editor */}
          <div className="account-name-block">
            {isEditingName ? (
              <div className="account-inline-name-edit">
                <input
                  type="text"
                  className="account-name-input"
                  value={nameInput}
                  autoFocus
                  onChange={(e) => setNameInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleSaveName();
                    if (e.key === 'Escape') {
                      setIsEditingName(false);
                      setNameInput(displayName);
                    }
                  }}
                  disabled={savingName}
                />
                <button
                  type="button"
                  className="account-icon-btn is-save"
                  onClick={handleSaveName}
                  disabled={savingName}
                  title={isJa ? '保存' : 'Save'}
                >
                  <Check size={18} />
                </button>
                <button
                  type="button"
                  className="account-icon-btn is-cancel"
                  onClick={() => {
                    setIsEditingName(false);
                    setNameInput(displayName);
                  }}
                  disabled={savingName}
                  title={isJa ? 'キャンセル' : 'Cancel'}
                >
                  <X size={18} />
                </button>
              </div>
            ) : (
              <div className="account-name-display-row">
                <h1 className="account-display-name">{displayName}</h1>
                <button
                  type="button"
                  className="account-edit-name-btn"
                  onClick={() => setIsEditingName(true)}
                  title={isJa ? '名前を編集' : 'Edit display name'}
                >
                  <Edit2 size={16} />
                </button>
              </div>
            )}
          </div>
        </div>

        {/* ── Credit Card (Flutter _CreditCard 準拠) ─────────────── */}
        <Link to="/account/credits" className="credit-card-interactive" title={isJa ? 'クレジット詳細を表示' : 'View Credit Details'}>
          <div className="credit-card-top-row">
            <div className="credit-card-title-group">
              <span className="credit-card-icon-pill">
                <CreditStarIcon size={16} color="var(--star-gold, #fbc02d)" />
              </span>
              <span className="credit-card-title">{isJa ? 'クレジット残高' : 'Credit balance'}</span>
            </div>
            <div className="credit-card-value-group">
              {creditLoading ? (
                <span className="credit-card-loading-val">{isJa ? '読み込み中…' : 'Loading…'}</span>
              ) : (
                <>
                  <span className="credit-card-bold-val">{totalBalance}</span>
                  <span className="credit-card-denom-val"> / {monthlyAllocation}</span>
                </>
              )}
              <ChevronRight size={16} className="credit-card-chevron" />
            </div>
          </div>

          {/* デュアルプログレスバー */}
          <div className="credit-dual-track">
            {creditLoading ? (
              <div className="credit-bar-loading" />
            ) : isDepleted ? (
              <div className="credit-bar-depleted" />
            ) : (
              <>
                {/* 1. 下層: 追加クレジット（紫） */}
                {totalFraction > 0 && (
                  <div
                    className="credit-bar-extra"
                    style={{ width: `${Math.round(totalFraction * 100)}%` }}
                  />
                )}
                {/* 2. 上層: 月次クレジット（黄色/ゴールド） */}
                {monthlyFraction > 0 && (
                  <div
                    className="credit-bar-monthly"
                    style={{ width: `${Math.round(monthlyFraction * 100)}%` }}
                  />
                )}
              </>
            )}
          </div>
        </Link>
      </div>

      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          SECTION 1 — PROFILE
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <p className="glass-section-label">
        <User size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>{isJa ? 'プロフィール' : 'Profile'}</span>
      </p>
      <div className="glass-card">
        {/* 1. About You */}
        <Link to="/account/profile" className="account-preview-tile">
          <div className="account-preview-tile-body">
            <div className="account-preview-tag">
              <User size={14} />
              <span>{isJa ? '自己紹介' : 'ABOUT YOU'}</span>
            </div>
            <p className="account-preview-desc">
              {profile?.bio?.trim() ? profile.bio : (isJa ? 'まだ自己紹介が設定されていません。' : 'No description set yet.')}
            </p>
          </div>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* 2. Interests */}
        <Link to="/account/profile" className="account-preview-tile">
          <div className="account-preview-tile-body">
            <div className="account-preview-tag">
              <Sparkles size={14} />
              <span>{isJa ? '興味・関心' : 'INTERESTS'}</span>
            </div>
            <p className="account-preview-desc">
              {profile?.interests?.trim() ? profile.interests : (isJa ? 'まだ興味・関心が設定されていません。' : 'No interests set yet.')}
            </p>
          </div>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* 3. Future Dreams */}
        <Link to="/account/profile" className="account-preview-tile">
          <div className="account-preview-tile-body">
            <div className="account-preview-tag">
              <Flag size={14} />
              <span>{isJa ? '将来の夢' : 'FUTURE DREAMS'}</span>
            </div>
            <p className="account-preview-desc">
              {profile?.future_goals?.trim() ? profile.future_goals : (isJa ? 'まだ将来の夢が設定されていません。' : 'No future dream set yet.')}
            </p>
          </div>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>
      </div>

      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          SECTION 2 — ACTIVITY
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <p className="glass-section-label">
        <Bookmark size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>{isJa ? 'アクティビティ' : 'Activity'}</span>
      </p>
      <div className="glass-card">
        {/* Saved */}
        <Link to="/account/activity/saved" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(76, 175, 80, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <Bookmark size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? '保存済み' : 'Saved'}</span>
            <span className="glass-row-sub">{isJa ? '復習カード・詳細ノート・キーワード' : 'Review Cards · Deep Notes · Keywords'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* Likes */}
        <Link to="/account/activity/likes" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(229, 57, 53, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <Heart size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? '高評価' : 'Likes'}</span>
            <span className="glass-row-sub">{isJa ? '復習カード・詳細ノート・ファンファクト' : 'Review Cards · Deep Notes · Fun Facts'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* Dislikes */}
        <Link to="/account/activity/dislikes" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(33, 150, 243, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <ThumbsDown size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? '低評価' : 'Dislikes'}</span>
            <span className="glass-row-sub">{isJa ? '復習カード・詳細ノート・ファンファクト' : 'Review Cards · Deep Notes · Fun Facts'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* Announcements */}
        <Link to="/account/activity/announcements" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(156, 39, 176, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <Megaphone size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? 'お知らせ' : 'Announcements'}</span>
            <span className="glass-row-sub">{isJa ? '完了済みのものを含む' : 'Including completed items'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* Trash */}
        <Link to="/account/activity/trash" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(229, 57, 53, 0.15)', color: 'var(--correction-red, #ff5252)' }}>
            <Trash2 size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title" style={{ color: 'var(--correction-red, #ff5252)' }}>
              {isJa ? 'ゴミ箱' : 'Trash'}
            </span>
            <span className="glass-row-sub">{isJa ? '削除されたコース・講義' : 'Deleted courses & lectures'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>
      </div>

      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          SECTION 3 — APPLICATION
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <p className="glass-section-label">
        <Rocket size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>{isJa ? 'アプリケーション' : 'Application'}</span>
      </p>
      <div className="glass-card">
        {/* Transmissions */}
        <button
          type="button"
          className="glass-row is-interactive-button"
          onClick={handleTransmissionsClick}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(30, 136, 229, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <Radio size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? 'トランスミッション' : 'Transmissions'}</span>
            <span className="glass-row-sub">{isJa ? '最新情報とアップデート' : 'What\'s new & updates'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>

        <div className="glass-divider" />

        {/* Onboarding */}
        <Link to="/onboarding" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(3, 169, 244, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <Rocket size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? 'オンボーディング' : 'Onboarding'}</span>
            <span className="glass-row-sub">{isJa ? '初期設定のやり直し' : 'Revisit initial setup'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        {/* Tutorial */}
        <button
          type="button"
          className="glass-row is-interactive-button"
          onClick={handleTutorialClick}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(156, 39, 176, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <GraduationCap size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? 'チュートリアル' : 'Tutorial'}</span>
            <span className="glass-row-sub">{isJa ? '使い方ガイド' : 'Interactive guide'}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>
      </div>

      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          SECTION 4 — SETTINGS (Flutter版準拠: アイコンと背景はニュートラルグレー)
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <p className="glass-section-label">
        <Shield size={15} className="section-label-icon" color="var(--comet, #8e99a6)" />
        <span>{isJa ? '設定' : 'Settings'}</span>
      </p>

      {/* 1. Preferences */}
      <div className="glass-card">
        <button
          type="button"
          className="glass-row is-interactive-button"
          onClick={() => setLangSheetMode('recording')}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Mic size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? '録音言語' : 'Recording Language'}</span>
            <span className="glass-row-sub">
              {getLanguageLabel(profile?.metadata?.recording_language)}
            </span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>

        <div className="glass-divider" />

        <button
          type="button"
          className="glass-row is-interactive-button"
          onClick={() => setLangSheetMode('display')}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Globe size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? '表示言語' : 'Display Language'}</span>
            <span className="glass-row-sub">
              {getLanguageLabel(profile?.metadata?.display_language)}
            </span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>
      </div>

      {/* 2. Legal & Support (外部Webサイトのリンク) */}
      <div className="glass-card" style={{ marginTop: '0.85rem' }}>
        <a
          href="https://lefture.com/privacy"
          target="_blank"
          rel="noopener noreferrer"
          className="glass-row"
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <ShieldCheck size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? 'プライバシーポリシー' : 'Privacy Policy'}</span>
          </span>
          <ExternalLink size={16} className="glass-row-chevron" style={{ opacity: 0.6 }} />
        </a>

        <div className="glass-divider" />

        <a
          href="https://lefture.com/terms"
          target="_blank"
          rel="noopener noreferrer"
          className="glass-row"
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Gavel size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? '利用規約' : 'Terms of Service'}</span>
          </span>
          <ExternalLink size={16} className="glass-row-chevron" style={{ opacity: 0.6 }} />
        </a>

        <div className="glass-divider" />

        <a
          href="https://lefture.com/contact"
          target="_blank"
          rel="noopener noreferrer"
          className="glass-row"
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Mail size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{isJa ? 'お問い合わせ' : 'Contact Us'}</span>
          </span>
          <ExternalLink size={16} className="glass-row-chevron" style={{ opacity: 0.6 }} />
        </a>
      </div>

      {/* 3. Account Auth Settings (Emailユーザーのみメアド/パスワード変更) */}
      {isEmailUser && (
        <div className="glass-card" style={{ marginTop: '0.85rem' }}>
          <button
            type="button"
            className="glass-row is-interactive-button"
            onClick={() => setEmailSheetOpen(true)}
          >
            <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
              <Mail size={17} />
            </span>
            <span className="glass-row-text">
              <span className="glass-row-title">{isJa ? 'メールアドレスを変更' : 'Change Email'}</span>
            </span>
            <ChevronRight size={18} className="glass-row-chevron" />
          </button>

          <div className="glass-divider" />

          <button
            type="button"
            className="glass-row is-interactive-button"
            onClick={() => setPasswordSheetOpen(true)}
          >
            <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
              <Lock size={17} />
            </span>
            <span className="glass-row-text">
              <span className="glass-row-title">{isJa ? 'パスワードを変更' : 'Change Password'}</span>
            </span>
            <ChevronRight size={18} className="glass-row-chevron" />
          </button>
        </div>
      )}

      {/* 4. Danger Zone (アイコンと背景は赤) */}
      <div className="glass-card" style={{ marginTop: '0.85rem' }}>
        <button
          type="button"
          className="glass-row is-interactive-button is-danger"
          onClick={() => setShowSignOutModal(true)}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(229, 57, 53, 0.15)', color: 'var(--correction-red, #ff5252)' }}>
            <LogOut size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title" style={{ color: 'var(--correction-red, #ff5252)' }}>
              {isJa ? 'サインアウト' : 'Sign Out'}
            </span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>

        <div className="glass-divider" />

        <button
          type="button"
          className="glass-row is-interactive-button is-danger"
          onClick={() => setDeleteModalOpen(true)}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(229, 57, 53, 0.15)', color: 'var(--correction-red, #ff5252)' }}>
            <UserX size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title" style={{ color: 'var(--correction-red, #ff5252)' }}>
              {isJa ? 'アカウントを削除' : 'Delete Account'}
            </span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>
      </div>

      {/* ── 各種シート & モーダル ───────────────────────────── */}
      <ChangeAvatarSheet
        open={avatarSheetOpen}
        onClose={() => setAvatarSheetOpen(false)}
        profile={profile}
        onUpdated={refetch}
      />

      {langSheetMode && (
        <LanguageSelectionSheet
          open={Boolean(langSheetMode)}
          onClose={() => setLangSheetMode(null)}
          mode={langSheetMode}
          profile={profile}
          onUpdated={refetch}
        />
      )}

      <ChangePasswordSheet
        open={passwordSheetOpen}
        onClose={() => setPasswordSheetOpen(false)}
      />

      <ChangeEmailSheet
        open={emailSheetOpen}
        onClose={() => setEmailSheetOpen(false)}
        currentEmail={user?.email}
      />

      <DeleteAccountModal
        open={deleteModalOpen}
        onClose={() => setDeleteModalOpen(false)}
        user={user}
        profile={profile}
      />

      {announcementsModalOpen && (
        <AnnouncementsModal
          announcements={announcements}
          onClose={() => setAnnouncementsModalOpen(false)}
        />
      )}

      {/* サインアウト確認カスタムモーダル */}
      <ConfirmModal
        open={showSignOutModal}
        onClose={() => setShowSignOutModal(false)}
        onConfirm={handleConfirmSignOut}
        title={isJa ? 'サインアウト' : 'Sign Out'}
        message={isJa ? 'アカウントからサインアウトしますか？' : 'Are you sure you want to sign out of your account?'}
        confirmLabel={isJa ? 'サインアウト' : 'Sign Out'}
        cancelLabel={isJa ? 'キャンセル' : 'Cancel'}
        isDanger={true}
      />

      {/* トースト通知 */}
      {toastMessage && (
        <div
          style={{
            position: 'fixed',
            bottom: '24px',
            right: '24px',
            background: 'rgba(18, 20, 34, 0.95)',
            border: '1px solid var(--glass-border)',
            color: '#fff',
            padding: '0.75rem 1.25rem',
            borderRadius: '12px',
            boxShadow: '0 8px 32px rgba(0,0,0,0.5)',
            zIndex: 2000,
            fontSize: '0.88rem',
            fontWeight: 500,
            animation: 'sheet-fade-in 0.2s ease-out',
          }}
        >
          {toastMessage}
        </div>
      )}
    </div>
  );
};
