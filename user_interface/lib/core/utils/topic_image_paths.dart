// トピック画像(R2: `{uid}/{lectureId}/images/topic_N.jpg`, 384x512)の縮小版
// (192x256 WebP)のパス規則。バックエンドの
// `app/services/logic/image_rendering.py`の`thumbnail_path_for`と同じ規則にすること。
// ファイル名にサイズを入れているのは、サイズを変えた時に端末の古いキャッシュ
// (パスがキー)を使い回さないため。

const String _thumbnailSuffix = '_thumb192.webp';

/// `.../images/topic_3.jpg` -> `.../images/topic_3_thumb192.webp`。
/// アセット画像(チュートリアル等)や拡張子の無いパスは縮小版が無いのでnull。
String? thumbnailPathFor(String imagePath) {
  if (imagePath.startsWith('assets/')) return null;
  final slash = imagePath.lastIndexOf('/');
  final dot = imagePath.lastIndexOf('.');
  if (dot <= slash) return null;
  return '${imagePath.substring(0, dot)}$_thumbnailSuffix';
}

/// 講義の行のmetadataに記録された表紙サムネイル(FINALIZE_JOB/バックフィルが書く)。
String? coverThumbPathOf(Map<String, dynamic>? lectureMetadata) {
  final path = lectureMetadata?['cover_thumb_path'];
  return path is String && path.isNotEmpty ? path : null;
}
