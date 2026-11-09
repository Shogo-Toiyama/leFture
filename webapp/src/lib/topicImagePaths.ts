// トピック画像(R2: `{uid}/{lectureId}/images/topic_N.jpg`, 384x512)の縮小版
// (192x256 WebP)のパス規則。バックエンドの
// `app/services/logic/image_rendering.py`の`thumbnail_path_for`、Flutterの
// `topic_image_paths.dart`と同じ規則にすること。

const THUMBNAIL_SUFFIX = '_thumb192.webp';

/** `.../images/topic_3.jpg` -> `.../images/topic_3_thumb192.webp`。拡張子が無ければnull。 */
export function thumbnailPathFor(imagePath: string | null | undefined): string | null {
  if (!imagePath || imagePath.startsWith('assets/')) return null;
  const slash = imagePath.lastIndexOf('/');
  const dot = imagePath.lastIndexOf('.');
  if (dot <= slash) return null;
  return `${imagePath.slice(0, dot)}${THUMBNAIL_SUFFIX}`;
}

/** 講義の行のmetadataに記録された表紙サムネイル(FINALIZE_JOB/バックフィルが書く)。 */
export function coverThumbPathOf(metadata: Record<string, unknown> | null | undefined): string | null {
  const path = metadata?.cover_thumb_path;
  return typeof path === 'string' && path.length > 0 ? path : null;
}
