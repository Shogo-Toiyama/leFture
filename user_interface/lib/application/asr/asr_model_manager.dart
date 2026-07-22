// lib/application/asr/asr_model_manager.dart
import 'dart:developer' as dev;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lecture_companion_ui/domain/entities/asr_model_manifest.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/asr_model_repository.dart';

part 'asr_model_manager.g.dart';

enum AsrModelStatus { unknown, checking, downloading, ready, failed, paused }

class AsrLanguageModelState {
  const AsrLanguageModelState({required this.status, this.progress, this.errorMessage});

  final AsrModelStatus status;
  // 0.0〜1.0。Content-Lengthが取れない場合はnull(不定進捗)。
  final double? progress;
  final String? errorMessage;

  static const initial = AsrLanguageModelState(status: AsrModelStatus.unknown);
}

/// VAD(Silero)モデル用の予約キー。`LocalAsrModels`は本来groupKeyをPKに
/// 持つテーブルだが、VADは全言語共有の単一アセットなので、通常のmodelIdと
/// 衝突しないアンダースコア始まりの疑似コードとして同じテーブルで管理する。
const kVadPseudoLanguageCode = '_vad';

/// 多言語Whisper(Tier3、languagesマップに無い言語すべてのフォールバック)用の
/// 予約キー。VADと同様、全言語共有の単一アセット。
const kWhisperPseudoLanguageCode = '_whisper';

/// 言語コードから、実際のダウンロード/ストレージ/状態管理の単位となる
/// "アセットグループキー"を解決する。manifest.languagesにあるモデルは
/// modelIdをそのままキーに使う(ja/ko/yueのようにmodelIdが同一なら
/// 自動的に1つのグループに束ねられ、二重ダウンロードを防げる)。
/// 無ければ共有Whisperにフォールバックする。
String resolveAssetGroupKey(AsrModelManifest manifest, String languageCode) {
  final info = manifest.languages[languageCode];
  if (info != null) return info.modelId;
  return kWhisperPseudoLanguageCode;
}

/// 録音言語ごとのオンデバイスASRモデルのダウンロード/バージョン整合性を管理する。
/// RecordingPageに入った瞬間と、録音言語の設定を変更した瞬間の2箇所から
/// `ensureModelReady`が呼ばれる想定(プロアクティブダウンロード)。
///
/// マニフェストの`engineCompatVersion`(モデル形式に影響する変更があった時だけ
/// 上げる)と`modelVersion`(モデル本体だけ差し替えたい時に上げる)を、ローカル
/// キャッシュ(LocalAsrModels)のタグと突き合わせて再ダウンロードが必要か判定する。
/// 失敗時は既存のreadyなモデルを壊さない(新しいダウンロードが成功するまで
/// 古いモデルを使い続けられるようにする、堅牢性優先)。
///
/// 言語は3段構成: `manifest.languages`にエントリがあればTier1(streaming_zipformer)
/// またはTier2(sense_voice、あわせて共有VADも必要)。無ければTier3として
/// 共有Whisper(+共有VAD)にフォールバックする。
///
/// ストレージは、VADを除く(Whisperは含む)グループを最大[_maxResidentGroups]個
/// までしか同時保持しない。3個目をダウンロードする際は、最も長く使われて
/// いない(lastUsedAt基準)グループを自動的に退避する。
@Riverpod(keepAlive: true)
class AsrModelManager extends _$AsrModelManager {
  static const _maxResidentGroups = 2;

  @override
  Map<String, AsrLanguageModelState> build() => {};

  AsrModelRepository get _repo => AsrModelRepository(Supabase.instance.client);
  AppDatabase get _db => ref.read(appDatabaseProvider);

  // UIが言語コードから状態を引けるようにするための、直近取得したmanifestの
  // キャッシュ。ダウンロードの可否判定には使わず(ensureModelReadyは毎回
  // fetchManifestし直す)、あくまでstatusForLanguageの同期的なキー解決用。
  AsrModelManifest? _cachedManifest;

  // 進行中ダウンロードの中断ハンドル(groupKey単位)。pauseDownloadが
  // これを使ってストリームを中断する。
  final Map<String, ModelDownloadHandle> _activeDownloads = {};

  // _fetchManifestOrMarkFailedの多重実行防止用(呼び出しキー単位)。
  // state[key]を再入防止フラグとして使うと、成功後にキーがgroupKeyへ
  // 更新されて`checking`のまま二度と変わらなくなり、以後そのキーでの
  // ensureModelReadyが永久にブロックされてしまうため、状態表示とは
  // 独立してここで管理する。
  final Set<String> _manifestFetchesInFlight = {};

  AsrLanguageModelState statusFor(String key) => state[key] ?? AsrLanguageModelState.initial;

  /// 言語コードから、実際に紐づくアセットグループの状態を返す。ja/ko/yueの
  /// ように複数の言語コードが同じグループを共有している場合、そのグループの
  /// ダウンロードが完了すれば対応するすべての言語コードで`ready`になる。
  /// まだmanifestを取得していない場合は`unknown`を返す。
  AsrLanguageModelState statusForLanguage(String languageCode) {
    final manifest = _cachedManifest;
    if (manifest == null) return AsrLanguageModelState.initial;
    final key = resolveAssetGroupKey(manifest, languageCode);
    return state[key] ?? AsrLanguageModelState.initial;
  }

  void _update(String key, AsrLanguageModelState value) {
    state = {...state, key: value};
  }

  /// 指定言語に必要なアセット一式(本体モデル + 該当すればVAD/Whisper)を揃える。
  Future<void> ensureModelReady(String languageCode) async {
    final manifest = await _fetchManifestOrMarkFailed(languageCode);
    if (manifest == null) return;

    final info = manifest.languages[languageCode];
    if (info != null) {
      final groupKey = resolveAssetGroupKey(manifest, languageCode);
      await _ensureAsset(groupKey, manifest.engineCompatVersion, info);
      if (info.engine == 'sense_voice') {
        await ensureVadModelReady();
      }
      return;
    }

    // languagesマップに無い言語は共有Whisper(+VAD)にフォールバックする。
    await ensureWhisperModelReady();
    await ensureVadModelReady();
  }

  Future<void> ensureVadModelReady() async {
    final manifest = await _fetchManifestOrMarkFailed(kVadPseudoLanguageCode);
    if (manifest == null) return;

    final info = manifest.vad;
    if (info == null) {
      _update(
        kVadPseudoLanguageCode,
        const AsrLanguageModelState(status: AsrModelStatus.failed, errorMessage: 'VADモデルがまだ用意されていません'),
      );
      return;
    }
    await _ensureAsset(kVadPseudoLanguageCode, manifest.engineCompatVersion, info);
  }

  Future<void> ensureWhisperModelReady() async {
    final manifest = await _fetchManifestOrMarkFailed(kWhisperPseudoLanguageCode);
    if (manifest == null) return;

    final info = manifest.whisper;
    if (info == null) {
      _update(
        kWhisperPseudoLanguageCode,
        const AsrLanguageModelState(status: AsrModelStatus.failed, errorMessage: 'Whisperモデルがまだ用意されていません'),
      );
      return;
    }
    await _ensureAsset(kWhisperPseudoLanguageCode, manifest.engineCompatVersion, info);
  }

  Future<AsrModelManifest?> _fetchManifestOrMarkFailed(String key) async {
    if (statusFor(key).status == AsrModelStatus.downloading) {
      return null; // 本体のダウンロード自体は既に進行中
    }
    if (!_manifestFetchesInFlight.add(key)) {
      return null; // 同じキーでのmanifest取得が既に進行中
    }
    _update(key, const AsrLanguageModelState(status: AsrModelStatus.checking));
    try {
      final manifest = await _repo.fetchManifest();
      _cachedManifest = manifest;
      return manifest;
    } catch (e, st) {
      dev.log('🚨 [AsrModelManager] fetchManifest failed for "$key"', error: e, stackTrace: st);
      _update(key, AsrLanguageModelState(status: AsrModelStatus.failed, errorMessage: e.toString()));
      return null;
    } finally {
      _manifestFetchesInFlight.remove(key);
    }
  }

  /// 1アセット(言語モデル/VAD/Whisper共通)のダウンロード〜展開〜DB反映。
  /// [key]は`LocalAsrModels.groupKey`に書き込むキー(通常はmodelIdそのもの、
  /// または`kVadPseudoLanguageCode`/`kWhisperPseudoLanguageCode`)。
  Future<void> _ensureAsset(String key, int engineCompatVersion, AsrModelInfo info) async {
    try {
      final existing =
          await (_db.select(_db.localAsrModels)..where((t) => t.groupKey.equals(key))).getSingleOrNull();

      if (existing != null &&
          existing.engineCompatVersion == engineCompatVersion &&
          existing.modelVersion == info.modelVersion &&
          existing.status == 'ready' &&
          await Directory(existing.localPath).exists()) {
        _update(key, const AsrLanguageModelState(status: AsrModelStatus.ready));
        return;
      }

      await _evictIfOverCapacity(key);

      final supportDir = await getApplicationSupportDirectory();
      final modelsDir = Directory(p.join(supportDir.path, 'asr_models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      // 前回一時停止/中断された部分ファイルが残っていれば、その続きから
      // 再開する(サーバーがRangeに対応していなければリポジトリ側が自動的に
      // 先頭からの全量ダウンロードにフォールバックする)。最終的なsha256検証は
      // 必ず行うため、たとえ古いバージョンの部分ファイルを誤って再開しても
      // 不整合は検出され、失敗として扱われるだけで安全。
      final archiveFile = File(p.join(modelsDir.path, '${info.modelId}.tar.gz'));
      final startByte = await archiveFile.exists() ? await archiveFile.length() : 0;

      _update(key, const AsrLanguageModelState(status: AsrModelStatus.downloading, progress: 0));

      final downloadUrl = await _repo.fetchDownloadUrl(info.modelId);

      await _repo.downloadModelArchive(
        downloadUrl,
        archiveFile,
        startByte: startByte,
        onProgress: (progress) {
          _update(key, AsrLanguageModelState(status: AsrModelStatus.downloading, progress: progress));
        },
        onHandleCreated: (handle) => _activeDownloads[key] = handle,
      );
      _activeDownloads.remove(key);

      final bytes = await archiveFile.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest != info.sha256.toLowerCase()) {
        await archiveFile.delete();
        throw Exception('Downloaded ASR asset failed checksum verification: $key');
      }

      // 展開先はキーごとの専用ディレクトリ(既存があれば作り直す)。
      final extractDir = Directory(p.join(modelsDir.path, key));
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      final tarBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);
      for (final file in archive) {
        final outPath = p.join(extractDir.path, file.name);
        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      await archiveFile.delete();

      await _db.into(_db.localAsrModels).insertOnConflictUpdate(
            LocalAsrModelsCompanion.insert(
              groupKey: key,
              modelId: info.modelId,
              engineCompatVersion: engineCompatVersion,
              modelVersion: info.modelVersion,
              localPath: extractDir.path,
              sizeBytes: info.sizeBytes,
              status: 'ready',
              downloadedAt: Value(DateTime.now().toUtc()),
            ),
          );

      _update(key, const AsrLanguageModelState(status: AsrModelStatus.ready));
    } on AsrDownloadPausedException {
      // pauseDownloadが既にstateをpausedへ更新済み。部分ファイルはディスクに
      // 残したまま、failedとして上書きしない。
      _activeDownloads.remove(key);
    } catch (e, st) {
      _activeDownloads.remove(key);
      dev.log('🚨 [AsrModelManager] _ensureAsset failed for "$key" (modelId=${info.modelId})', error: e, stackTrace: st);
      // 失敗しても既存のreadyな行(古いモデル)はそのまま残す。
      _update(key, AsrLanguageModelState(status: AsrModelStatus.failed, errorMessage: e.toString()));
    }
  }

  /// 進行中のダウンロードを一時停止する。部分ファイルはディスクに残るため、
  /// 次に[ensureModelReady]/[resumeDownload]が呼ばれた際にその続きから
  /// 再開される。
  Future<void> pauseDownload(String languageCode) async {
    final manifest = _cachedManifest;
    if (manifest == null) return;
    final groupKey = resolveAssetGroupKey(manifest, languageCode);
    final handle = _activeDownloads.remove(groupKey);
    if (handle == null) return;
    _update(
      groupKey,
      AsrLanguageModelState(status: AsrModelStatus.paused, progress: statusFor(groupKey).progress),
    );
    await handle.cancel();
  }

  /// 一時停止中(または中断された)ダウンロードを再開する。実体は
  /// [ensureModelReady]と同じ(部分ファイルが残っていれば自動的に続きから
  /// 再開される)。呼び出し側にとって意図が分かりやすいよう別名で公開する。
  Future<void> resumeDownload(String languageCode) => ensureModelReady(languageCode);

  /// [protectedGroupKey]をこれからダウンロードする前提で、VAD以外のreadyな
  /// グループが[_maxResidentGroups]を超えていれば、最も長く使われていない
  /// (lastUsedAt、無ければdownloadedAt基準)グループから順に削除する。
  /// [protectedGroupKey]自身は絶対に退避しない。
  Future<void> _evictIfOverCapacity(String protectedGroupKey) async {
    final readyRows =
        await (_db.select(_db.localAsrModels)..where((t) => t.status.equals('ready'))).get();
    final residentOthers = readyRows
        .where((r) => r.groupKey != kVadPseudoLanguageCode && r.groupKey != protectedGroupKey)
        .toList();

    if (residentOthers.length < _maxResidentGroups) return;

    residentOthers.sort((a, b) {
      final aAt = a.lastUsedAt ?? a.downloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.lastUsedAt ?? b.downloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aAt.compareTo(bAt);
    });

    final evictCount = residentOthers.length - _maxResidentGroups + 1;
    for (final row in residentOthers.take(evictCount)) {
      dev.log('🗑️ [AsrModelManager] evicting LRU group "${row.groupKey}" to make room for "$protectedGroupKey"');
      final dir = Directory(row.localPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await (_db.delete(_db.localAsrModels)..where((t) => t.groupKey.equals(row.groupKey))).go();
      _update(row.groupKey, const AsrLanguageModelState(status: AsrModelStatus.unknown));
    }
  }

  /// 指定キーのローカルパス(ダウンロード済みでreadyな場合のみ)。エンジン初期化に使う。
  /// [key]は解決済みのgroupKey(通常はmodelId、またはVAD/Whisperの疑似コード)。
  Future<String?> localPathFor(String key) async {
    final row =
        await (_db.select(_db.localAsrModels)..where((t) => t.groupKey.equals(key))).getSingleOrNull();
    if (row == null || row.status != 'ready') return null;
    return row.localPath;
  }
}
