// lib/infrastructure/repositories/asr_model_repository.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/network_constants.dart';
import '../../domain/entities/asr_model_manifest.dart';

/// [AsrModelRepository.downloadModelArchive]がユーザー操作(pauseDownload)に
/// よって明示的に中断されたことを示すマーカー例外。呼び出し側(AsrModelManager)は
/// これを「失敗」ではなく「一時停止」として扱う。
class AsrDownloadPausedException implements Exception {
  const AsrDownloadPausedException();
}

/// 進行中のダウンロードを中断するためのハンドル。生の[StreamSubscription]を
/// 公開する代わりに、中断時に[AsrDownloadPausedException]で確実に
/// downloadModelArchiveのFutureを完了させる責務をカプセル化する。
class ModelDownloadHandle {
  ModelDownloadHandle._(this._cancel);

  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

class AsrModelRepository {
  final SupabaseClient _supabase;

  AsrModelRepository(this._supabase);

  static const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  String _requireJwt() {
    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot reach ASR model backend.');
    }
    return jwt;
  }

  /// 録音言語ごとのASRモデル一覧(engineCompatVersion/modelVersion込み)を取得する。
  Future<AsrModelManifest> fetchManifest() async {
    final jwt = _requireJwt();
    final response = await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/asr-models/manifest'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
        )
        .timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch ASR manifest (${response.statusCode}): ${response.body}');
    }
    return AsrModelManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// 指定modelIdのモデル本体(tar.gz)を取得するための署名付きURLをその場で発行してもらう。
  /// 署名URLは最大7日で失効するため、ダウンロード直前に毎回取り直す。
  Future<String> fetchDownloadUrl(String modelId) async {
    final jwt = _requireJwt();
    final response = await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/asr-models/download-url'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({'model_id': modelId}),
        )
        .timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch ASR model download URL (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  /// モデル本体(数十〜200MB弱)をストリーミングでダウンロードする。
  /// [onProgress]は0.0〜1.0の進捗率(Content-Lengthが取れない場合はnull)。
  /// [startByte]が0より大きい場合、`Range`ヘッダー付きで途中から再開を試みる。
  /// サーバーがRangeに対応していない(206ではなく200が返る)場合は、素直に
  /// 先頭からの全量ダウンロードにフォールバックする(安全側に倒す)。
  /// [onHandleCreated]でユーザー操作による中断用ハンドルを呼び出し元に渡す
  /// (`AsrModelManager.pauseDownload`から使う)。
  /// ここには`networkTimeout`(15秒)を適用しない — ダウンロード自体は数十秒〜
  /// 数分かかることが想定されるため。
  Future<void> downloadModelArchive(
    String downloadUrl,
    File destination, {
    int startByte = 0,
    void Function(double? progress)? onProgress,
    void Function(ModelDownloadHandle handle)? onHandleCreated,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }
      final response = await client.send(request);

      final isResuming = startByte > 0 && response.statusCode == 206;
      if (response.statusCode != 200 && !isResuming) {
        throw Exception('Failed to download ASR model archive (${response.statusCode})');
      }

      int? total;
      if (isResuming) {
        // "bytes 1000-2000000/2000001" 形式。合計サイズが取れなければ
        // startByte + 残りのContent-Lengthで代用する。
        final contentRange = response.headers['content-range'];
        final totalStr = contentRange?.split('/').last;
        total = totalStr != null ? int.tryParse(totalStr) : null;
        total ??= response.contentLength != null ? startByte + response.contentLength! : null;
      } else {
        total = response.contentLength;
      }

      var received = isResuming ? startByte : 0;
      final sink = destination.openWrite(mode: isResuming ? FileMode.append : FileMode.write);

      final completer = Completer<void>();
      late final StreamSubscription<List<int>> subscription;
      subscription = response.stream.listen(
        (chunk) {
          received += chunk.length;
          sink.add(chunk);
          if (total != null && total > 0) {
            onProgress?.call(received / total);
          } else {
            onProgress?.call(null);
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        cancelOnError: true,
      );

      onHandleCreated?.call(
        ModelDownloadHandle._(() async {
          await subscription.cancel();
          if (!completer.isCompleted) {
            completer.completeError(const AsrDownloadPausedException());
          }
        }),
      );

      try {
        await completer.future;
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}
