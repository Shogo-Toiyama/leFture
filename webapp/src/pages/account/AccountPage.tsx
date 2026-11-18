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
import { seedTutorial } from '../../lib/tutorial';
import { toDisplayCredits } from '../../types/billing';
import { AvatarImage } from '../../components/AvatarImage';
import { AccountPageSkeleton } from '../../components/account/AccountPageSkeleton';
import { AnnouncementsModal } from '../../components/modals/AnnouncementsModal';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { useAnnouncements } from '../../hooks/useAnnouncements';
import { useLanguage } from '../../i18n/LanguageContext';
import { ChangeAvatarSheet } from '../../components/account/ChangeAvatarSheet';
import { LanguageSelectionSheet, type LanguageSheetMode } from '../../components/account/LanguageSelectionSheet';
import { recordingLanguageNativeName } from '../../i18n/recordingLanguages';
import {
  ChangePasswordSheet,
  ChangeEmailSheet,
  DeleteAccountModal,
} from '../../components/account/AccountAuthSheets';

function getLanguageLabel(code: string | undefined, currentLanguage: string): string {
  return recordingLanguageNativeName(code || 'ja', currentLanguage);
}

export const AccountPage: React.FC = () => {
  const { profile, loading, refetch } = useProfile();
  const { user } = useAuth();
  const navigate = useNavigate();
  const { t, language } = useLanguage();

  const { summary, loading: creditLoading } = useCreditSummary(false);

  // ── インライン名前編集 ─────────────────────────────────────
  const displayName = profile?.username || t('explorerDefaultName');
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
      alert(err instanceof Error ? err.message : t('failedToUpdateUsername'));
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
  const { announcements, setAnnouncements } = useAnnouncements();

  const handleTransmissionsClick = () => {
    if (!announcements || announcements.length === 0) {
      showToast(t('noTransmissionsToast'));
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
        // オンボーディング完了時のseedが(オフライン等で)失敗したユーザー向けの再試行
        const lectureId = await seedTutorial(language);
        navigate(`/lectures/${lectureId}`);
        return;
      }
    } catch (err) {
      console.error('Failed to find or seed tutorial lecture:', err);
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
  // scope: 'local' を必ず明示する。supabase-jsのsignOut()は既定が
  // scope: 'global' で、このブラウザだけでなく「そのユーザーの全端末」の
  // セッションを失効させてしまう(gotrue-dart側の既定はlocalなので、
  // モバイル→Webの向きでは起きない非対称な挙動)。
  // 実際に2026-09-19、ここからのサインアウトでiOSアプリのセッションが
  // 巻き添えで失効し、アプリ側のクレジット表示が読めなくなる事故が起きた。
  const handleConfirmSignOut = async () => {
    await supabase.auth.signOut({ scope: 'local' });
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
            title={t('changeAvatarTitle')}
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
                  title={t('save')}
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
                  title={t('cancel')}
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
                  title={t('editDisplayName')}
                >
                  <Edit2 size={16} />
                </button>
              </div>
            )}
          </div>
        </div>

        {/* ── Credit Card (Flutter _CreditCard 準拠) ─────────────── */}
        <Link to="/account/credits" className="credit-card-interactive" title={t('viewCreditDetails')}>
          <div className="credit-card-top-row">
            <div className="credit-card-title-group">
              <span className="credit-card-icon-pill">
                <CreditStarIcon size={16} color="var(--star-gold, #fbc02d)" />
              </span>
              <span className="credit-card-title">{t('creditBalance')}</span>
            </div>
            <div className="credit-card-value-group">
              {creditLoading ? (
                <span className="credit-card-loading-val">{t('loading')}</span>
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
        <span>{t('profileSectionTitle')}</span>
      </p>
      <div className="glass-card">
        {/* 1. About You */}
        <Link to="/account/profile" className="account-preview-tile">
          <div className="account-preview-tile-body">
            <div className="account-preview-tag">
              <User size={14} />
              <span>{t('aboutYouSection')}</span>
            </div>
            <p className="account-preview-desc">
              {profile?.bio?.trim() ? profile.bio : t('noBioYet')}
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
              <span>{t('interestsSection')}</span>
            </div>
            <p className="account-preview-desc">
              {profile?.interests?.trim() ? profile.interests : t('noInterestsYet')}
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
              <span>{t('futureDreamsSection')}</span>
            </div>
            <p className="account-preview-desc">
              {profile?.future_goals?.trim() ? profile.future_goals : t('noFutureDreamsYet')}
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
        <span>{t('activitySection')}</span>
      </p>
      <div className="glass-card">
        {/* Saved */}
        <Link to="/account/activity/saved" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(76, 175, 80, 0.2)', color: 'var(--star-gold, #fbc02d)' }}>
            <Bookmark size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{t('savedSectionTitle')}</span>
            <span className="glass-row-sub">{t('savedSectionSub')}</span>
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
            <span className="glass-row-title">{t('likesSectionTitle')}</span>
            <span className="glass-row-sub">{t('likesSectionSub')}</span>
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
            <span className="glass-row-title">{t('dislikesSectionTitle')}</span>
            <span className="glass-row-sub">{t('dislikesSectionSub')}</span>
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
            <span className="glass-row-title">{t('announcementsSectionTitle')}</span>
            <span className="glass-row-sub">{t('announcementsSectionSub')}</span>
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
              {t('trashSectionTitle')}
            </span>
            <span className="glass-row-sub">{t('trashSectionSub')}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>
      </div>

      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          SECTION 3 — APPLICATION
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <p className="glass-section-label">
        <Rocket size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>{t('applicationSection')}</span>
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
            <span className="glass-row-title">{t('transmissionsTitle')}</span>
            <span className="glass-row-sub">{t('transmissionsSub')}</span>
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
            <span className="glass-row-title">{t('onboardingTitle')}</span>
            <span className="glass-row-sub">{t('onboardingSub')}</span>
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
            <span className="glass-row-title">{t('tutorialTitle')}</span>
            <span className="glass-row-sub">{t('tutorialSub')}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>
      </div>

      {/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          SECTION 4 — SETTINGS (Flutter版準拠: アイコンと背景はニュートラルグレー)
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <p className="glass-section-label">
        <Shield size={15} className="section-label-icon" color="var(--comet, #8e99a6)" />
        <span>{t('settingsSection')}</span>
      </p>

      {/* 1. Preferences */}
      <div className="glass-card">
        <Link to="/account/ai-memory" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Sparkles size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{t('aiSettingsButton')}</span>
            <span className="glass-row-sub">{t('accountAiSettingsSub')}</span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </Link>

        <div className="glass-divider" />

        <button
          type="button"
          className="glass-row is-interactive-button"
          onClick={() => setLangSheetMode('recording')}
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Mic size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{t('recordingLanguageLabel')}</span>
            <span className="glass-row-sub">
              {getLanguageLabel(profile?.metadata?.recording_language, language)}
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
            <span className="glass-row-title">{t('displayLanguage')}</span>
            <span className="glass-row-sub">
              {getLanguageLabel(profile?.metadata?.display_language, language)}
            </span>
          </span>
          <ChevronRight size={18} className="glass-row-chevron" />
        </button>
      </div>

      {/* 2. Legal & Support (外部Webサイトのリンク) */}
      <div className="glass-card" style={{ marginTop: '0.85rem' }}>
        <a
          href="https://lefture.tech/privacy"
          target="_blank"
          rel="noopener noreferrer"
          className="glass-row"
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <ShieldCheck size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{t('privacyPolicy')}</span>
          </span>
          <ExternalLink size={16} className="glass-row-chevron" style={{ opacity: 0.6 }} />
        </a>

        <div className="glass-divider" />

        <a
          href="https://lefture.tech/terms"
          target="_blank"
          rel="noopener noreferrer"
          className="glass-row"
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Gavel size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{t('termsOfService')}</span>
          </span>
          <ExternalLink size={16} className="glass-row-chevron" style={{ opacity: 0.6 }} />
        </a>

        <div className="glass-divider" />

        <a
          href="https://lefture.tech/contact"
          target="_blank"
          rel="noopener noreferrer"
          className="glass-row"
        >
          <span className="glass-row-icon" style={{ background: 'rgba(255, 255, 255, 0.08)', color: 'var(--comet, #8E99A6)' }}>
            <Mail size={17} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">{t('contactUs')}</span>
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
              <span className="glass-row-title">{t('changeEmailTitle')}</span>
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
              <span className="glass-row-title">{t('changePasswordTitle')}</span>
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
              {t('signOutButton')}
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
              {t('deleteAccountTitle')}
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
          onAnnouncementToggled={(updated) => {
            setAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
          }}
          onAnnouncementUpdated={(updated) => {
            setAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
          }}
          onAnnouncementDeleted={(id) => {
            setAnnouncements((prev) => prev.filter((a) => a.id !== id));
          }}
        />
      )}

      {/* サインアウト確認カスタムモーダル */}
      <ConfirmModal
        open={showSignOutModal}
        onClose={() => setShowSignOutModal(false)}
        onConfirm={handleConfirmSignOut}
        title={t('signOutConfirmTitle')}
        message={t('signOutConfirmMessage')}
        confirmLabel={t('signOutButton')}
        cancelLabel={t('cancel')}
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
