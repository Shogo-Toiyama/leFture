import React from 'react';
import { useArtifactImage } from '../hooks/useArtifactImage';

interface TopicImageProps {
  imagePath: string | null;
  alt: string;
  className?: string;
}

export const TopicImage: React.FC<TopicImageProps> = ({ imagePath, alt, className }) => {
  const url = useArtifactImage(imagePath);
  if (!url) return <div className={`topic-image topic-image-placeholder ${className ?? ''}`} aria-hidden="true" />;
  return <img src={url} alt={alt} className={`topic-image ${className ?? ''}`} loading="lazy" />;
};
