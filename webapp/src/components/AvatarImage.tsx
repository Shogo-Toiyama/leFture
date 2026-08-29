import React, { useEffect, useState } from 'react';
import { fetchArtifactObjectUrl } from '../lib/artifacts';

interface AvatarImageProps {
  /** 外部URL(ソーシャルログインのアバター)かR2のstorage_pathのどちらか。 */
  avatarUrl: string | null;
  size?: number;
}

function isExternalUrl(value: string): boolean {
  return value.startsWith('http://') || value.startsWith('https://');
}

export const AvatarImage: React.FC<AvatarImageProps> = ({ avatarUrl, size = 48 }) => {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!avatarUrl || isExternalUrl(avatarUrl)) return;
    let cancelled = false;
    let created: string | null = null;
    fetchArtifactObjectUrl(avatarUrl).then((url) => {
      if (cancelled) {
        URL.revokeObjectURL(url);
        return;
      }
      created = url;
      setObjectUrl(url);
    });
    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [avatarUrl]);

  const src = avatarUrl && isExternalUrl(avatarUrl) ? avatarUrl : objectUrl;

  if (!src) {
    return <div className="avatar-placeholder" style={{ width: size, height: size }} />;
  }
  return <img src={src} alt="Avatar" className="avatar-image" style={{ width: size, height: size }} />;
};
