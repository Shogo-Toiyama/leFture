import React from 'react';
import { useArtifactImage } from '../hooks/useArtifactImage';
import { thumbnailPathFor } from '../lib/topicImagePaths';

interface TopicImageProps {
  imagePath: string | null;
  alt: string;
  className?: string;
  fallback?: React.ReactNode;
  /** trueなら、元の画像(約170KB)が届くまで縮小版(192x256, 約9KB)を先に出す。 */
  progressive?: boolean;
}

export const TopicImage: React.FC<TopicImageProps> = ({ imagePath, alt, className, fallback, progressive }) => {
  const url = useArtifactImage(imagePath);
  // 元の画像が届いたら縮小版は要らないので、パスをnullにして取得をやめる
  // (届いていた縮小版のobject URLはフックが解放する)。
  const thumbUrl = useArtifactImage(progressive && !url ? thumbnailPathFor(imagePath) : null);
  const shown = url ?? thumbUrl;
  if (!shown) return fallback ?? <div className={`topic-image topic-image-placeholder ${className ?? ''}`} aria-hidden="true" />;
  return <img src={shown} alt={alt} className={`topic-image ${className ?? ''}`} loading="lazy" />;
};
