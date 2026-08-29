export interface UserProfileMetadata {
  onboarding_completed_at?: string;
  display_language?: string;
  recording_language?: string;
  [key: string]: unknown;
}

export interface UserProfile {
  id: string;
  username: string | null;
  avatar_url: string | null;
  bio: string | null;
  interests: string | null;
  future_goals: string | null;
  metadata: UserProfileMetadata | null;
  deleted_at: string | null;
}

export function hasCompletedOnboarding(profile: Pick<UserProfile, 'metadata'> | null): boolean {
  return Boolean(profile?.metadata?.onboarding_completed_at);
}
