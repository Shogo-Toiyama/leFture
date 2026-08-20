import { useEffect } from 'react';

interface PageMetaOptions {
  title?: string;
  description?: string;
  canonicalPath?: string;
}

/**
 * Custom hook to dynamically update page title, meta description, and canonical URL in SPA.
 */
export function usePageMeta({ title, description, canonicalPath }: PageMetaOptions) {
  useEffect(() => {
    const prevTitle = document.title;
    if (title) {
      document.title = title;
    }

    let metaDesc = document.querySelector('meta[name="description"]');
    const prevDesc = metaDesc ? metaDesc.getAttribute('content') : null;
    if (description) {
      if (!metaDesc) {
        metaDesc = document.createElement('meta');
        metaDesc.setAttribute('name', 'description');
        document.head.appendChild(metaDesc);
      }
      metaDesc.setAttribute('content', description);
    }

    // Also update og:title, og:description, twitter:title, twitter:description if available
    const ogTitle = document.querySelector('meta[property="og:title"]');
    const prevOgTitle = ogTitle ? ogTitle.getAttribute('content') : null;
    if (title && ogTitle) {
      ogTitle.setAttribute('content', title);
    }

    const twitterTitle = document.querySelector('meta[name="twitter:title"]');
    const prevTwitterTitle = twitterTitle ? twitterTitle.getAttribute('content') : null;
    if (title && twitterTitle) {
      twitterTitle.setAttribute('content', title);
    }

    const ogDesc = document.querySelector('meta[property="og:description"]');
    const prevOgDesc = ogDesc ? ogDesc.getAttribute('content') : null;
    if (description && ogDesc) {
      ogDesc.setAttribute('content', description);
    }

    const twitterDesc = document.querySelector('meta[name="twitter:description"]');
    const prevTwitterDesc = twitterDesc ? twitterDesc.getAttribute('content') : null;
    if (description && twitterDesc) {
      twitterDesc.setAttribute('content', description);
    }

    let canonicalLink = document.querySelector('link[rel="canonical"]');
    const prevCanonical = canonicalLink ? canonicalLink.getAttribute('href') : null;
    if (canonicalPath !== undefined) {
      const cleanPath = canonicalPath === '/' ? '' : canonicalPath.startsWith('/') ? canonicalPath : `/${canonicalPath}`;
      const canonicalUrl = `https://lefture.com${cleanPath}`;
      if (!canonicalLink) {
        canonicalLink = document.createElement('link');
        canonicalLink.setAttribute('rel', 'canonical');
        document.head.appendChild(canonicalLink);
      }
      canonicalLink.setAttribute('href', canonicalUrl);
    }

    return () => {
      if (title && prevTitle) {
        document.title = prevTitle;
        if (ogTitle && prevOgTitle) ogTitle.setAttribute('content', prevOgTitle);
        if (twitterTitle && prevTwitterTitle) twitterTitle.setAttribute('content', prevTwitterTitle);
      }
      if (description && prevDesc && metaDesc) {
        metaDesc.setAttribute('content', prevDesc);
        if (ogDesc && prevOgDesc) ogDesc.setAttribute('content', prevOgDesc);
        if (twitterDesc && prevTwitterDesc) twitterDesc.setAttribute('content', prevTwitterDesc);
      }
      if (canonicalPath !== undefined && prevCanonical && canonicalLink) {
        canonicalLink.setAttribute('href', prevCanonical);
      }
    };
  }, [title, description, canonicalPath]);
}
