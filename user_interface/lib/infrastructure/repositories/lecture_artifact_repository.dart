// lib/infrastructure/repositories/lecture_artifact_repository.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/connectivity_utils.dart';
import '../../core/utils/network_constants.dart';
import '../../domain/entities/lecture_data.dart';
import '../local_db/app_database.dart';

/// R2に保存された成果物(トランスクリプトJSON・トピック画像など)を取得するリポジトリ。
///
/// R2の認証情報はクライアントに持たせられないため、バックエンドの
/// `/get-artifact-urls` でJWT認証した上で署名付きGET URLを発行してもらい、
/// それを使ってダウンロードする。取得したファイルはローカルにキャッシュし、
/// 2回目以降はネットワークを使わない。
/// [LectureArtifactRepository.getArtifactFile] が取得に失敗した際に投げる例外。
/// 未生成(404)・認証未リフレッシュ(401)・ネットワークエラー等、理由を問わず
/// 「まだ取得できていない」ことを表す。
class ArtifactFetchException implements Exception {
  final String message;
  final String storagePath;

  ArtifactFetchException(this.message, {required this.storagePath});

  @override
  String toString() => 'ArtifactFetchException($storagePath): $message';
}

/// [ArtifactFetchException]の一種で、そもそも端末がオフラインだったために
/// リクエストすら送らなかったことを表す。呼び出し元(UI)はこれを他の失敗理由
/// (未生成/認証切れ等)と区別して「オフラインです」という分かりやすい表示に
/// 差し替えられる。
class ArtifactOfflineException extends ArtifactFetchException {
  ArtifactOfflineException({required super.storagePath}) : super('offline');
}

class LectureArtifactRepository {
  final SupabaseClient _supabase;
  final AppDatabase _db;

  LectureArtifactRepository(this._supabase, this._db);

  static const _workerBaseUrl = 'https://lefture-artifact-worker.shogo-toiyama.workers.dev';

  // ---------------------------------------------------------------------------
  // 汎用: R2ストレージパス → ローカルキャッシュ済みFile
  // ---------------------------------------------------------------------------

  /// [storagePath] (例: "{uid}/{lectureId}/images/topic_1.jpg") のファイルを
  /// キャッシュ優先で取得する。
  ///
  /// 取得できたファイルは容量管理(LocalRetentionService)がLRU判定できるよう
  /// [LocalCacheEntries] にサイズを記録する。すでにキャッシュ済みの場合も、
  /// このテーブル追加より前にダウンロードされたファイルを後から拾えるように
  /// 都度upsertしておく。
  ///
  /// 未取得(トークン未リフレッシュ・生成未完了・ネットワークエラー等)の場合は
  /// [ArtifactFetchException] を投げる。null成功値としては返さない
  /// (呼び出し元のProviderが失敗結果をキャッシュに残さず再取得できるように
  /// するため。詳しくは [artifactFileProvider] を参照)。
  Future<File> getArtifactFile(String storagePath) async {
    if (storagePath.startsWith('assets/')) {
      throw ArtifactFetchException('Local asset path should not be fetched from remote worker', storagePath: storagePath);
    }

    final localFile = await _localCacheFile(storagePath);
    if (localFile.existsSync() && localFile.lengthSync() > 0) {
      await _registerCacheEntry(storagePath, localFile);
      return localFile;
    }

    // 既にオフラインと分かっているなら、DNS解決待ちで何十秒も待たされた挙句に
    // 生のSocketException文言をユーザーに見せてしまうことのないよう、
    // リクエスト自体を送らずその場で分かりやすい専用の例外にする。
    if (!await isDeviceOnline()) {
      throw ArtifactOfflineException(storagePath: storagePath);
    }

    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) {
      throw ArtifactFetchException('token is null', storagePath: storagePath);
    }

    try {
      final response = await http.get(
        Uri.parse('$_workerBaseUrl/$storagePath'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(networkTimeout);
      if (response.statusCode != 200) {
        // まだ生成されていない(404)、トークン未リフレッシュ(401)等。
        debugPrint('Artifact GET ${response.statusCode}: $storagePath');
        throw ArtifactFetchException(
          'HTTP ${response.statusCode}',
          storagePath: storagePath,
        );
      }
      await localFile.writeAsBytes(response.bodyBytes);
      await _registerCacheEntry(storagePath, localFile);
      return localFile;
    } on ArtifactFetchException {
      rethrow;
    } catch (e) {
      debugPrint('Artifact download error: $e');
      throw ArtifactFetchException('$e', storagePath: storagePath);
    }
  }

  /// [storagePath]は"{uid}/{lectureId}/..."形式であることを前提に、
  /// 容量管理用のキャッシュエントリを記録する。形式が想定と異なる場合は
  /// キャッシュ管理をスキップする(ファイル自体の取得は成功させたいため)。
  Future<void> _registerCacheEntry(String storagePath, File file) async {
    final segments = storagePath.split('/');
    if (segments.length < 2) return;
    final uid = segments[0];
    final lectureId = segments[1];

    try {
      final sizeBytes = await file.length();
      await _db.upsertCacheEntry(
        id: storagePath,
        userId: uid,
        lectureId: lectureId,
        localFilePath: file.path,
        sizeBytes: sizeBytes,
      );
    } catch (e) {
      debugPrint('Cache entry registration failed for $storagePath: $e');
    }
  }

  Future<File> _localCacheFile(String storagePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'r2_cache', storagePath));
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  // ---------------------------------------------------------------------------
  // トランスクリプト
  // ---------------------------------------------------------------------------

  /// トランスクリプトを取得する。
  ///
  /// role分類済みの `role_classification.json` を優先し、
  /// まだ無ければ組み立て直後の `transcript_assembled.json` にフォールバックする。
  Future<List<TranscriptSentence>?> getTranscript({
    required String uid,
    required String lectureId,
  }) async {
    for (final fileName in const [
      'pipeline_logs/role_classification.json',
      'pipeline_logs/transcript_assembled.json',
    ]) {
      final File file;
      try {
        file = await getArtifactFile('$uid/$lectureId/$fileName');
      } on ArtifactOfflineException {
        // オフラインなら他の候補ファイル名を試しても結果は変わらないので、
        // ここで即座に伝播する。呼び出し元は「まだ生成中」と誤表示せず
        // 「オフラインです」を出せる。
        rethrow;
      } on ArtifactFetchException {
        continue;
      }

      try {
        final jsonString = await file.readAsString();
        return compute(_parseTranscript, jsonString);
      } catch (e) {
        debugPrint('Transcript parse error ($fileName): $e');
        // パースできない壊れたキャッシュは消して次の候補へ
        final storagePath = '$uid/$lectureId/$fileName';
        try {
          await file.delete();
        } catch (_) {}
        try {
          await _db.deleteCacheEntry(id: storagePath, userId: uid);
        } catch (_) {}
      }
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// Isolate (別スレッド) で実行するためのトップレベル関数
// -----------------------------------------------------------------------------

List<TranscriptSentence> _parseTranscript(String jsonString) {
  final jsonList = jsonDecode(jsonString) as List<dynamic>;
  return jsonList
      .map((e) => TranscriptSentence.fromJson(e as Map<String, dynamic>))
      .toList();
}
