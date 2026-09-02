import React, { useEffect, useState } from 'react';
import { fetchArtifactObjectUrl } from '../lib/artifacts';

interface AvatarImageProps {
  /** 外部URL(ソーシャルログインのアバター)かR2のstorage_pathかpreset形式 */
  avatarUrl: string | null;
  username?: string;
  size?: number;
}

const VIVID_GRADIENTS = [
  'linear-gradient(135deg, #FF6B6B, #FF8E53)',
  'linear-gradient(135deg, #4E65FF, #92EFFD)',
  'linear-gradient(135deg, #FFB300, #F77737)',
  'linear-gradient(135deg, #11998E, #38EF7D)',
  'linear-gradient(135deg, #FC5C7D, #6A82FB)',
  'linear-gradient(135deg, #7F00FF, #E100FF)',
  'linear-gradient(135deg, #3A1C71, #D76D77)',
  'linear-gradient(135deg, #00C6FF, #0072FF)',
];

function parsePreset(presetStr: string) {
  const payload = presetStr.replace(/^preset:/, '');
  const parts = payload.split(';');
  let bgIndex = 0;
  let iconName = 'initials';

  for (const part of parts) {
    const [key, val] = part.split('=');
    if (key === 'bg_index') bgIndex = parseInt(val, 10) || 0;
    if (key === 'icon') iconName = val || 'initials';
  }
  return { bgIndex, iconName };
}

export const AvatarImage: React.FC<AvatarImageProps> = ({
  avatarUrl,
  username = 'Explorer',
  size = 48,
}) => {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);

  const cleanUrl = avatarUrl?.trim() ?? '';
  const isExternal = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');
  const isPreset = cleanUrl.startsWith('preset:');
  const isStoragePath = cleanUrl.length > 0 && !isExternal && !isPreset;

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

  const initials = (username.trim() || 'EX')
    .split(' ')
    .filter(Boolean)
    .map((s) => s[0].toUpperCase())
    .slice(0, 2)
    .join('');

  if (isExternal) {
    return (
      <img
        src={cleanUrl}
        alt={username}
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

  if (isPreset) {
    const { bgIndex } = parsePreset(cleanUrl);
    const bg = VIVID_GRADIENTS[bgIndex % VIVID_GRADIENTS.length];
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
          color: '#ffffff',
          fontWeight: 700,
          fontSize: Math.round(size * 0.36),
          userSelect: 'none',
          boxShadow: '0 2px 8px rgba(0,0,0,0.2)',
        }}
      >
        {initials}
      </div>
    );
  }

  if (objectUrl) {
    return (
      <img
        src={objectUrl}
        alt={username}
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
