/**
 * Outbound links used across the site.
 *
 * TODO(shogo): replace APP_STORE_URL with the real listing once the app is
 * published — e.g. https://apps.apple.com/jp/app/lefture/id0000000000
 * It is referenced by the header CTA, the hero CTA, and the closing CTA, so
 * changing it here updates all three.
 */
export const APP_STORE_URL = 'https://apps.apple.com';

/**
 * TODO(shogo): set this to the production origin (no trailing slash) so the
 * Open Graph tags in index.html can be made absolute. Social crawlers reject
 * relative og:image paths.
 */
export const SITE_ORIGIN = 'https://lefture.app';
