import { supabase } from './supabase';
import { apiFetch } from './api';
import type { UserProfile, UserProfileMetadata } from '../types/profile';

export async function getProfile(): Promise<UserProfile> {
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const { data, error } = await supabase.from('user_profiles').select('*').eq('id', userId).single();
  if (error) throw error;
  return data as UserProfile;
}

export interface ProfileFieldsInput {
  username?: string;
  bio?: string;
  interests?: string;
  future_goals?: string;
  avatar_url?: string;
}

export async function updateProfileFields(input: ProfileFieldsInput): Promise<UserProfile> {
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const { data, error } = await supabase
    .from('user_profiles')
    .update({ ...input, updated_at: new Date().toISOString() })
    .eq('id', userId)
    .select('*')
    .single();
  if (error) throw error;
  return data as UserProfile;
}

async function updateMetadata(
  currentMetadata: UserProfileMetadata | null,
  patch: UserProfileMetadata
): Promise<UserProfile> {
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const { data, error } = await supabase
    .from('user_profiles')
    .update({ metadata: { ...currentMetadata, ...patch }, updated_at: new Date().toISOString() })
    .eq('id', userId)
    .select('*')
    .single();
  if (error) throw error;
  return data as UserProfile;
}

export function setLanguagePreferences(
  currentMetadata: UserProfileMetadata | null,
  displayLanguage: string,
  recordingLanguage: string
): Promise<UserProfile> {
  return updateMetadata(currentMetadata, {
    display_language: displayLanguage,
    recording_language: recordingLanguage,
  });
}

/** onboarding_page.dartのDoneステップ相当: onboarding_completed_atを立てる。 */
export function markOnboardingCompleted(currentMetadata: UserProfileMetadata | null): Promise<UserProfile> {
  return updateMetadata(currentMetadata, { onboarding_completed_at: new Date().toISOString() });
}

interface RequestAvatarUploadUrlResponse {
  upload_url: string;
  storage_path: string;
}

/** change_avatar_sheet.dart のR2直PUTアップロードと同じ手順。 */
export async function uploadAvatar(file: File): Promise<string> {
  const { upload_url, storage_path } = await apiFetch<RequestAvatarUploadUrlResponse>(
    '/profile/request-avatar-upload-url',
    { method: 'POST', body: JSON.stringify({ file_name: file.name, content_type: file.type || 'image/jpeg' }) }
  );

  const putResponse = await fetch(upload_url, {
    method: 'PUT',
    headers: { 'Content-Type': file.type || 'image/jpeg' },
    body: file,
  });
  if (!putResponse.ok) {
    throw new Error(`Failed to upload avatar (status ${putResponse.status})`);
  }

  await updateProfileFields({ avatar_url: storage_path });
  return storage_path;
}
