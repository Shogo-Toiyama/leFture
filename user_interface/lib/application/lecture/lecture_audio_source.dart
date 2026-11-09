import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';

/// 講義音声をどこから再生するか。
class LectureAudioSource {
  const LectureAudioSource({
    required this.source,
    required this.isStreaming,
    this.refreshAfter,
  });

  final Source source;

  /// 署名付きURLでストリーミング再生する(再生位置の周りだけを取りに行く)ならtrue。
  final bool isStreaming;

  /// この時刻を過ぎたら署名付きURLを取り直す(端末の時計で判定)。
  /// Workerの署名は最低6時間有効なので、端末とWorkerの時計のずれに関係なく
  /// 余裕を持って切れる前に取り直せるよう、取得から5時間後にしている。
  final DateTime? refreshAfter;
}

typedef LectureAudioKey = ({String lectureId, String storagePath});

/// 文字起こし画面の音声。次の順で選ぶ:
/// 1. 端末にあるファイル(この端末で録音した音声、以前ダウンロードしたキャッシュ)。
///    オフラインでも聞ける。
/// 2. 署名付きURLでのストリーミング。音声(中央値約32MB、最大約170MB)を丸ごと
///    待たず、再生位置の周りだけを取る。
/// 3. 署名付きURLが使えない(古いWorker・秘密鍵未設定など)なら、従来通り丸ごと
///    ダウンロードしてから再生する。
///
/// 署名付きURLには期限があるので、keepAliveせず画面を閉じたら捨てる。
final lectureAudioSourceProvider = FutureProvider.autoDispose
    .family<LectureAudioSource, LectureAudioKey>((ref, key) async {
  final db = ref.read(appDatabaseProvider);
  final repo = ref.read(lectureArtifactRepositoryProvider);

  // 1a. この端末で録音した音声(アップロード後も残っていれば)
  final asset = await (db.select(db.localLectureAssets)
        ..where((t) => t.lectureId.equals(key.lectureId) & t.type.equals('master_audio'))
        ..limit(1))
      .getSingleOrNull();
  final localPath = asset?.localPath;
  if (localPath != null && localPath.isNotEmpty) {
    final file = File(localPath);
    if (file.existsSync() && file.lengthSync() > 0) {
      return LectureAudioSource(source: DeviceFileSource(file.path), isStreaming: false);
    }
  }

  // 1b. 以前に丸ごとダウンロードしたキャッシュ
  final cached = await repo.cachedArtifactFile(key.storagePath);
  if (cached != null) {
    return LectureAudioSource(source: DeviceFileSource(cached.path), isStreaming: false);
  }

  // 2. 署名付きURLでストリーミング(オフラインならArtifactOfflineExceptionが飛ぶ)
  final signed = await repo.signedAudioUrl(key.storagePath);
  if (signed != null) {
    return LectureAudioSource(
      source: UrlSource(signed.toString(), mimeType: 'audio/mp4'),
      isStreaming: true,
      refreshAfter: DateTime.now().add(const Duration(hours: 5)),
    );
  }

  // 3. 従来の丸ごとダウンロード
  DevLog.add('🎧 [LectureAudio] Signed URL unavailable for ${key.storagePath}; downloading the whole file.');
  final file = await repo.getArtifactFile(key.storagePath);
  return LectureAudioSource(source: DeviceFileSource(file.path), isStreaming: false);
});
