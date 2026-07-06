// lib/infrastructure/repositories/lecture_artifact_repository.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/lecture_data.dart';

/// R2に保存された成果物(トランスクリプトJSON・トピック画像など)を取得するリポジトリ。
///
/// R2の認証情報はクライアントに持たせられないため、バックエンドの
/// `/get-artifact-urls` でJWT認証した上で署名付きGET URLを発行してもらい、
/// それを使ってダウンロードする。取得したファイルはローカルにキャッシュし、
/// 2回目以降はネットワークを使わない。
class LectureArtifactRepository {
  final SupabaseClient _supabase;

  LectureArtifactRepository(this._supabase);

  static const _workerBaseUrl = 'https://lefture-artifact-worker.shogo-toiyama.workers.dev';

  // ---------------------------------------------------------------------------
  // 汎用: R2ストレージパス → ローカルキャッシュ済みFile
  // ---------------------------------------------------------------------------

  /// [storagePath] (例: "{uid}/{lectureId}/images/topic_1.jpg") のファイルを
  /// キャッシュ優先で取得する。存在しない/取得失敗時はnull。
  Future<File?> getArtifactFile(String storagePath) async {
    final localFile = await _localCacheFile(storagePath);
    if (localFile.existsSync() && localFile.lengthSync() > 0) {
      return localFile;
    }

    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) {
      debugPrint('Artifact download failed: token is null');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_workerBaseUrl/$storagePath'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) {
        // まだ生成されていない(404)等。キャッシュせずnullを返す。
        debugPrint('Artifact GET ${response.statusCode}: $storagePath');
        return null;
      }
      await localFile.writeAsBytes(response.bodyBytes);
      return localFile;
    } catch (e) {
      debugPrint('Artifact download error: $e');
      return null;
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
      final file = await getArtifactFile('$uid/$lectureId/$fileName');
      if (file == null) continue;

      try {
        final jsonString = await file.readAsString();
        return compute(_parseTranscript, jsonString);
      } catch (e) {
        debugPrint('Transcript parse error ($fileName): $e');
        // パースできない壊れたキャッシュは消して次の候補へ
        try {
          await file.delete();
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
