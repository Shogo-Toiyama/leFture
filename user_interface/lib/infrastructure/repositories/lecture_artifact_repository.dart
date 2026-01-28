// lib/infrastructure/repositories/lecture_artifact_repository.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/lecture_data.dart';

class LectureArtifactRepository {
  final SupabaseClient _supabase;

  LectureArtifactRepository(this._supabase);

  // ---------------------------------------------------------------------------
  // 1. 読む授業 (LectureCompleteData) を取得
  // ---------------------------------------------------------------------------
  Future<LectureCompleteData?> getLectureCompleteData({
    required String uid,
    required String lectureId,
  }) async {
    const fileName = 'lecture_complete_data.json';
    
    try{
      // 1. ファイルを取得（ローカルにあればそれを、なければDL）
      final file = await _downloadOrGetLocalFile(
        uid: uid,
        lectureId: lectureId,
        fileName: fileName,
      );

      // 2. JSON文字列を読み込む
      final jsonString = await file.readAsString();

      // 3. 重いパース処理は別スレッド(compute)で行う
      return compute(_parseLectureCompleteData, jsonString);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('Object not found') || msg.contains('not_found')) {
        return null;
      }
      
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 2. トランスクリプト (List<TranscriptSentence>) を取得
  // ---------------------------------------------------------------------------
  Future<List<TranscriptSentence>?> getTranscript({
    required String uid,
    required String lectureId,
  }) async {
    const fileName = 'sentences_final.json';

    try {
      final file = await _downloadOrGetLocalFile(
        uid: uid,
        lectureId: lectureId,
        fileName: fileName,
      );

      final jsonString = await file.readAsString();
      return compute(_parseTranscript, jsonString);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('Object not found') || msg.contains('not_found')) {
        return null;
      }
      
      rethrow;
    }
  }

  // ===========================================================================
  // Private Helpers
  // ===========================================================================

  /// ローカルにファイルがあればそれを返し、なければStorageからDLして保存して返す
  Future<File> _downloadOrGetLocalFile({
    required String uid,
    required String lectureId,
    required String fileName,
  }) async {
    // ローカルの保存先パスを取得
    // 例: /data/user/0/com.example/app_flutter/lectures/<lectureId>/<fileName>
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(
      p.join(dir.path, 'lectures', lectureId, 'artifacts')
    );
    
    // ディレクトリがなければ作成
    if (!saveDir.existsSync()) {
      await saveDir.create(recursive: true);
    }

    final localFile = File('${saveDir.path}/$fileName');

    // すでにファイルが存在するなら、それを返す (Cache Hit)
    if (localFile.existsSync()) {
      debugPrint('Cache Hit: ${localFile.path}');
      return localFile;
    }

    // 存在しないなら Supabase からダウンロード (Cache Miss)
    debugPrint('Downloading from Supabase: $fileName');
    try {
      // Storageのパス: <UID>/<LectureID>/artifacts/<FileName>
      final storagePath = '$uid/$lectureId/artifacts/$fileName';

      // Supabaseからバイトデータをダウンロード
      // ※ バケット名は 'lecture_assets' と仮定しています。違っていれば変更してください。
      final bytes = await _supabase.storage
          .from('lecture_assets') 
          .download(storagePath);

      // ローカルに書き込み
      await localFile.writeAsBytes(bytes);
      
      return localFile;
    } catch (e) {
      // ダウンロード失敗時などはエラーを投げる
      // (まだ生成が終わっていない場合など)
      debugPrint('Download Error: $e');
      throw Exception('Failed to download $fileName: $e');
    }
  }
}

// -----------------------------------------------------------------------------
// Isolate (別スレッド) で実行するためのトップレベル関数
// -----------------------------------------------------------------------------

LectureCompleteData _parseLectureCompleteData(String jsonString) {
  final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
  return LectureCompleteData.fromJson(jsonMap);
}

List<TranscriptSentence> _parseTranscript(String jsonString) {
  final jsonList = jsonDecode(jsonString) as List<dynamic>;
  return jsonList
      .map((e) => TranscriptSentence.fromJson(e as Map<String, dynamic>))
      .toList();
}