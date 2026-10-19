import type { UserProfileMetadata } from '../types/profile';

/**
 * AIサービスへのデータ送信への同意(アプリ=Flutterと同じ仕組み・同じキー)。
 * 録音(音声のアップロード)とチャットは送り先も目的も違うので、別々に同意をもらう。
 * 同意はアカウント単位で profiles.metadata に残り、アプリで同意した人にはここでも出さない(逆も同じ)。
 *
 * 同意には版番号を持たせる。送り先を増やして版を上げたときは、前の版に同意した人にもう一度聞く。
 * 版番号が無く日時だけある録音の同意は、第1版(アプリが版番号をつける前に同意した人)。
 */
export type AiConsentKind = 'recording' | 'chat';

interface ConsentSpec {
  atKey: string;
  versionKey: string;
  /** 今の版。送り先を変えたら上げる。 */
  version: number;
  /** 版番号が無く日時だけあるときの版。 */
  legacyVersion: number;
}

const SPECS: Record<AiConsentKind, ConsentSpec> = {
  // 第2版: 送り先にOpenAI(GPT-6 Luna)を明記した
  recording: {
    atKey: 'ai_recording_profile_share_consent_at',
    versionKey: 'ai_recording_share_consent_version',
    version: 2,
    legacyVersion: 1,
  },
  // 第1版: 初回
  chat: {
    atKey: 'ai_chat_share_consent_at',
    versionKey: 'ai_chat_share_consent_version',
    version: 1,
    legacyVersion: 1,
  },
};

/** 記録されている同意の版。まだ同意していなければ0。 */
export function consentVersionOf(metadata: UserProfileMetadata | null | undefined, kind: AiConsentKind): number {
  const spec = SPECS[kind];
  const v = metadata?.[spec.versionKey];
  if (typeof v === 'number') return Math.trunc(v);
  return metadata?.[spec.atKey] ? spec.legacyVersion : 0;
}

/** 今の版で同意済みか。 */
export function hasAiConsent(metadata: UserProfileMetadata | null | undefined, kind: AiConsentKind): boolean {
  return consentVersionOf(metadata, kind) >= SPECS[kind].version;
}

/** 同意を記録するときにmetadataへ足す値。 */
export function aiConsentPatch(kind: AiConsentKind): UserProfileMetadata {
  const spec = SPECS[kind];
  return { [spec.atKey]: new Date().toISOString(), [spec.versionKey]: spec.version };
}
