import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { User, Sparkles, Flag, Edit3, ArrowLeft } from 'lucide-react';
import { useProfile } from '../../hooks/useProfile';
import { EditProfileSheet } from '../../components/account/EditProfileSheet';
import { ProfileSkeleton } from '../../components/account/ProfileSkeleton';

export const ProfilePage: React.FC = () => {
  const { profile, loading, refetch } = useProfile();
  const [isEditOpen, setIsEditOpen] = useState(false);

  if (loading) return <ProfileSkeleton />;

  const hasBio = Boolean(profile?.bio && profile.bio.trim().length > 0);
  const hasInterests = Boolean(profile?.interests && profile.interests.trim().length > 0);
  const hasGoals = Boolean(profile?.future_goals && profile.future_goals.trim().length > 0);

  return (
    <div className="account-page">
      {/* ── Top Header ─────────────────────────────────────────── */}
      <div className="profile-detail-top-nav">
        <Link to="/account" className="back-link" style={{ margin: 0 }}>
          <ArrowLeft size={18} />
          <span>Account</span>
        </Link>
        <button
          type="button"
          className="profile-detail-edit-action"
          onClick={() => setIsEditOpen(true)}
          title="Edit profile"
        >
          <Edit3 size={16} />
          <span>Edit</span>
        </button>
      </div>

      <div className="profile-detail-title-row">
        <h1 style={{ margin: '0.5rem 0 0.25rem', fontSize: '1.8rem' }}>Profile</h1>
        <p className="muted" style={{ margin: 0, fontSize: '0.9rem' }}>
          Your bio, interests, and future learning dreams
        </p>
      </div>

      {/* ── Profile Details Card (Flutter UserProfileDetailPage準拠) ── */}
      <div className="glass-card" style={{ marginTop: '1.5rem' }}>
        {/* 1. About You */}
        <div className="profile-detail-item">
          <div className="profile-detail-label">
            <User size={15} className="profile-detail-icon" />
            <span>ABOUT YOU</span>
          </div>
          <p className={`profile-detail-content ${hasBio ? 'has-content' : 'is-placeholder'}`}>
            {hasBio ? profile?.bio : 'No description set yet.'}
          </p>
        </div>

        <div className="glass-divider" />

        {/* 2. Interests */}
        <div className="profile-detail-item">
          <div className="profile-detail-label">
            <Sparkles size={15} className="profile-detail-icon" />
            <span>INTERESTS</span>
          </div>
          <p className={`profile-detail-content ${hasInterests ? 'has-content' : 'is-placeholder'}`}>
            {hasInterests ? profile?.interests : 'No interests set yet.'}
          </p>
        </div>

        <div className="glass-divider" />

        {/* 3. Future Goals */}
        <div className="profile-detail-item">
          <div className="profile-detail-label">
            <Flag size={15} className="profile-detail-icon" />
            <span>FUTURE DREAMS</span>
          </div>
          <p className={`profile-detail-content ${hasGoals ? 'has-content' : 'is-placeholder'}`}>
            {hasGoals ? profile?.future_goals : 'No future dream set yet.'}
          </p>
        </div>
      </div>

      {/* 編集用レスポンシブシート */}
      <EditProfileSheet
        open={isEditOpen}
        onClose={() => setIsEditOpen(false)}
        profile={profile}
        onUpdated={refetch}
      />
    </div>
  );
};
