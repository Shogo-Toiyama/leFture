import React, { useEffect, useState } from 'react';
import { fetchArtifactObjectUrl } from '../lib/artifacts';
import { parsePreset, getGradientsForStyle, getTextColorForStyle } from '../lib/avatar';

interface AvatarImageProps {
  /** 外部URL(ソーシャルログインのアバター)かR2のstorage_pathかpreset形式 */
  avatarUrl: string | null;
  username?: string | null;
  size?: number;
}

export const AvatarImage: React.FC<AvatarImageProps> = ({
  avatarUrl,
  username,
  size = 48,
}) => {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [externalLoadFailed, setExternalLoadFailed] = useState(false);

  const cleanUrl = avatarUrl?.trim() ?? '';
  const isExternal = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');
  const isPreset = cleanUrl.startsWith('preset:');
  const isStoragePath = cleanUrl.length > 0 && !isExternal && !isPreset;

  // GoogleのプロフィールURL(lh3.googleusercontent.com等)はReferrerを見て弾く
  // ことがあり、Referrer-Policyを指定しないと何のエラーも出さずに読み込みに
  // 失敗する(<img>のonerrorすら発火しないケースがある)。念のため
  // referrerPolicy="no-referrer"を指定し、それでも失敗したらonErrorで
  // イニシャルのプレースホルダーにフォールバックする。
  useEffect(() => {
    setExternalLoadFailed(false);
    if (!isStoragePath) {
      setObjectUrl(null);
    }
  }, [cleanUrl, isStoragePath]);

  useEffect(() => {
    if (!isStoragePath) return;

    let cancelled = false;
    let created: string | null = null;

    fetchArtifactObjectUrl(cleanUrl)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        created = url;
        setObjectUrl(url);
      })
      .catch((err) => {
        console.warn('Failed to load avatar from storage:', err);
      });

    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [cleanUrl, isStoragePath]);

  const effectiveName = (username || '').trim() || 'Explorer';
  const initials = effectiveName
    .split(' ')
    .filter(Boolean)
    .map((s) => s[0].toUpperCase())
    .slice(0, 2)
    .join('');

  if (isExternal && !externalLoadFailed) {
    return (
      <img
        src={cleanUrl}
        alt={effectiveName}
        className="avatar-image"
        referrerPolicy="no-referrer"
        onError={() => setExternalLoadFailed(true)}
        style={{
          width: size,
          height: size,
          borderRadius: '50%',
          objectFit: 'cover',
        }}
      />
    );
  }

  if (isPreset) {
    const { bgStyle, bgIndex, icon } = parsePreset(cleanUrl);
    const gradients = getGradientsForStyle(bgStyle);
    const bg = gradients[bgIndex % gradients.length];
    const textColor = getTextColorForStyle(bgStyle, bgIndex);
    const isClayIcon = icon && icon !== 'initials';
    return (
      <div
        className="avatar-preset"
        style={{
          width: size,
          height: size,
          borderRadius: '50%',
          background: bg,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: textColor,
          fontWeight: 700,
          fontSize: Math.round(size * 0.36),
          userSelect: 'none',
          boxShadow: '0 2px 8px rgba(0,0,0,0.2)',
          overflow: 'hidden',
          position: 'relative',
        }}
      >
        {isClayIcon ? (
          <img
            src={`/avatars/${icon.replace(/\.png$/, '.webp')}`}
            alt={effectiveName}
            style={{ width: '80%', height: '80%', objectFit: 'contain' }}
            onError={(e) => {
              (e.currentTarget as HTMLElement).style.display = 'none';
            }}
          />
        ) : (
          initials
        )}
      </div>
    );
  }

  if (objectUrl) {
    return (
      <img
        src={objectUrl}
        alt={effectiveName}
        className="avatar-image"
        style={{
          width: size,
          height: size,
          borderRadius: '50%',
          objectFit: 'cover',
        }}
      />
    );
  }

  return (
    <div
      className="avatar-placeholder"
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: 'linear-gradient(135deg, #7C83FD, #FFB300)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: '#ffffff',
        fontWeight: 700,
        fontSize: Math.round(size * 0.36),
        userSelect: 'none',
      }}
    >
      {initials}
    </div>
  );
};
