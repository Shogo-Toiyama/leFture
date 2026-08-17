// lib/application/asr/asr_model_manager.dart
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/domain/entities/asr_model_manifest.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/repositories/asr_model_repository.dart';

part 'asr_model_manager.g.dart';

enum AsrModelStatus { unknown, checking, downloading, ready, failed, paused }

class AsrLanguageModelState {
  const AsrLanguageModelState({
    required this.status,
    this.progress,
    this.errorMessage,
    this.installed = false,
  });

  final AsrModelStatus status;
  // 0.0〜1.0。Content-Lengthが取れない場合はnull(不定進捗)。
  final double? progress;
  final String? errorMessage;

  /// 実際に使えるモデルがディスク上にあるかどうか。[status]が「今この瞬間の
  /// 確認/ダウンロード処理がどこまで進んでいるか」という一時的な進行状況で
  /// あるのに対し、こちらは「機能が使えるか」という永続的な事実を表す。
  ///
  /// 例えばマニフェスト取得のためにページを開くたび[status]は一度
  /// [AsrModelStatus.checking]へ落ちるし、オフラインなら[AsrModelStatus.failed]
  /// にもなるが、その間もモデル自体は手元にあり使える。UI側の「ON/OFF
  /// トグルを出してよいか」「Realtimeを自動でOFFに戻すべきか」といった判断は
  /// [status]ではなく必ずこちらを見ること。
  final bool installed;

  static const initial = AsrLanguageModelState(status: AsrModelStatus.unknown);
}

/// VAD(Silero)モデル用の予約キー。`LocalAsrModels`は本来groupKeyをPKに
/// 持つテーブルだが、VADは全言語共有の単一アセットなので、通常のmodelIdと
/// 衝突しないアンダースコア始まりの疑似コードとして同じテーブルで管理する。
const kVadPseudoLanguageCode = '_vad';

/// 多言語Whisper(全言語共通)用の予約キー。VADと同様、全言語共有の単一アセット。
const kWhisperPseudoLanguageCode = '_whisper';

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
/// 全言語が共有Whisper(+共有VAD)の2アセットのみを使うため、常にこの2つだけを
/// 常駐させればよく、複数言語モデルを退避するLRU管理は不要。
@Riverpod(keepAlive: true)
class AsrModelManager extends _$AsrModelManager {
  @override
  Map<String, AsrLanguageModelState> build() {
    final observer = _AsrLifecycleObserver(
      onBackgrounded: _handleAppBackgrounded,
      onForegrounded: _handleAppForegrounded,
    );
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

    // アプリがバックグラウンドで(resumedイベントを受け取れないまま)killされた
    // 場合に備え、起動直後にも一度だけ自動一時停止の残骸を確認して再開する。
    // またマニフェスト取得(ネットワーク)を待たずに、ディスク+DBだけで分かる
    // 範囲を先に`ready`として反映しておく。
    // build()実行中のstate変更によるRiverpod例外を防ぐため、microtaskで非同期実行する。
    Future.microtask(() {
      _handleAppForegrounded();
      unawaited(_reconcileFromDiskAtStartup());
    });

    return {};
  }

  AsrModelRepository get _repo => AsrModelRepository(Supabase.instance.client);
  AppDatabase get _db => ref.read(appDatabaseProvider);

  // 進行中ダウンロードの中断ハンドル(groupKey単位)。pauseDownloadが
  // これを使ってストリームを中断する。
  final Map<String, ModelDownloadHandle> _activeDownloads = {};

  // _fetchManifestOrMarkFailedの多重実行防止用(呼び出しキー単位)。
  // state[key]を再入防止フラグとして使うと、成功後にキーがgroupKeyへ
  // 更新されて`checking`のまま二度と変わらなくなり、以後そのキーでの
  // ensureModelReadyが永久にブロックされてしまうため、状態表示とは
  // 独立してここで管理する。
  final Set<String> _manifestFetchesInFlight = {};

  // _ensureAssetの多重実行防止用(groupKey単位)。自動再開とユーザー操作が
  // 同時に同じグループを触ろうとするのを防ぐ。
  final Set<String> _ensureAssetInFlight = {};

  // ディスク上に実際に使えるモデルがあるgroupKeyの集合。stateの反映は
  // microtask経由で遅れるため、`installed`の真偽はここで同期的に管理し、
  // stateへは常にこの集合から反映する(_update直前に_markInstalledを呼ぶ)。
  final Set<String> _installedKeys = {};

  AsrLanguageModelState statusFor(String key) => state[key] ?? AsrLanguageModelState.initial;

  /// Realtime Transcribeに必要な共有アセット(Whisper + VAD)をまとめた状態を返す。
  /// 全言語が同じ2アセットを使うため[languageCode]は無視する。
  ///
  /// `installed`は両方が揃って初めてtrue(片方でも欠けていればRealtimeは
  /// 動かせない)。`status`は「ユーザーに見せるべき最も重要な進行状況」を
  /// failed > downloading > paused > checking の優先順で拾う。
  AsrLanguageModelState statusForLanguage(String languageCode) {
    final whisper = statusFor(kWhisperPseudoLanguageCode);
    final vad = statusFor(kVadPseudoLanguageCode);
    final installed = whisper.installed && vad.installed;

    AsrLanguageModelState? pick(AsrModelStatus status) {
      for (final s in [whisper, vad]) {
        if (s.status == status) return s;
      }
      return null;
    }

    for (final status in [
      AsrModelStatus.failed,
      AsrModelStatus.downloading,
      AsrModelStatus.paused,
      AsrModelStatus.checking,
    ]) {
      final match = pick(status);
      if (match != null) {
        return AsrLanguageModelState(
          status: status,
          progress: match.progress,
          errorMessage: match.errorMessage,
          installed: installed,
        );
      }
    }

    return AsrLanguageModelState(
      status: installed ? AsrModelStatus.ready : AsrModelStatus.unknown,
      installed: installed,
    );
  }

  void _update(String key, AsrLanguageModelState value) {
    final installed = _installedKeys.contains(key);
    Future.microtask(() {
      state = {
        ...state,
        key: AsrLanguageModelState(
          status: value.status,
          progress: value.progress,
          errorMessage: value.errorMessage,
          installed: installed,
        ),
      };
    });
  }

  /// [key]のモデル実体がディスク上に揃っているかを記録する。必ず対応する
  /// [_update]より前に呼ぶこと(_updateはこの集合を見て`installed`を決める)。
  void _markInstalled(String key, bool installed) {
    if (installed) {
      _installedKeys.add(key);
    } else {
      _installedKeys.remove(key);
    }
  }

  /// 共有Whisper + 共有VADの2アセットを揃える。[languageCode]は呼び出し側
  /// (画面ごとの「今選択されている言語」)をそのまま渡せるようにするための
  /// 引数だが、モデル選択には使わない。
  Future<void> ensureModelReady(String languageCode) async {
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
      return await _repo.fetchManifest();
    } catch (e, st) {
      dev.log('🚨 [AsrModelManager] fetchManifest failed for "$key"', error: e, stackTrace: st);
      _update(key, AsrLanguageModelState(status: AsrModelStatus.failed, errorMessage: e.toString()));
      return null;
    } finally {
      _manifestFetchesInFlight.remove(key);
    }
  }

  /// 1アセット(VAD/Whisper共通)のダウンロード〜展開〜DB反映。
  /// [key]は`LocalAsrModels.groupKey`に書き込むキー(`kVadPseudoLanguageCode`
  /// または`kWhisperPseudoLanguageCode`)。同じgroupKeyに対する多重実行
  /// (例: バックグラウンド復帰時の自動再開とユーザーの手動再開ボタンが
  /// 同時に走る)を防ぐため、groupKey単位で排他制御する。
  Future<void> _ensureAsset(String key, int engineCompatVersion, AsrModelInfo info) async {
    if (!_ensureAssetInFlight.add(key)) return; // 既に同じgroupKeyで進行中
    try {
      final existing =
          await (_db.select(_db.localAsrModels)..where((t) => t.groupKey.equals(key))).getSingleOrNull();

      // バージョンが古くても、実体が残っていれば「今は使えるモデルがある」
      // 状態(installed)として扱う。新しいバージョンのダウンロードが終わるまで
      // 古いモデルで機能を使い続けられるようにするため。
      final usable =
          existing != null && existing.status == 'ready' && await Directory(existing.localPath).exists();
      _markInstalled(key, usable);

      if (usable &&
          existing.engineCompatVersion == engineCompatVersion &&
          existing.modelVersion == info.modelVersion) {
        _update(key, const AsrLanguageModelState(status: AsrModelStatus.ready));
        return;
      }

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

      // 展開先はキーごとの専用ディレクトリ(既存があれば作り直す)。ここで
      // 古いモデルの実体が消えるため、展開が終わるまでは「使えるモデルなし」
      // として扱い、進捗も不定(展開中)に切り替える。
      final extractDir = Directory(p.join(modelsDir.path, key));
      _markInstalled(key, false);
      _update(key, const AsrLanguageModelState(status: AsrModelStatus.downloading));
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

      _markInstalled(key, true);
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
    } finally {
      _ensureAssetInFlight.remove(key);
    }
  }

  /// 進行中のダウンロードを一時停止する。部分ファイルはディスクに残るため、
  /// 次に[ensureModelReady]/[resumeDownload]が呼ばれた際にその続きから
  /// 再開される。共有アセットは常にVAD/Whisperの2つだけなので、
  /// [languageCode]は使わず、現在進行中の全ダウンロードを止める。
  Future<void> pauseDownload(String languageCode) async {
    for (final groupKey in _activeDownloads.keys.toList()) {
      final handle = _activeDownloads.remove(groupKey);
      if (handle == null) continue;
      _update(
        groupKey,
        AsrLanguageModelState(status: AsrModelStatus.paused, progress: statusFor(groupKey).progress),
      );
      await handle.cancel();
    }
  }

  /// 一時停止中(または中断された)ダウンロードを再開する。実体は
  /// [ensureModelReady]と同じ(部分ファイルが残っていれば自動的に続きから
  /// 再開される)。呼び出し側にとって意図が分かりやすいよう別名で公開する。
  Future<void> resumeDownload(String languageCode) => ensureModelReady(languageCode);

  /// アプリがバックグラウンドへ移行(またはkillされる直前)したタイミングで、
  /// 現在アクティブなダウンロードをすべて明示的に一時停止する。OSにソケットを
  /// 強制切断される前にこちらから止めることで、部分ファイルを正常な状態で
  /// 保持できる。ユーザーが手動でpauseした分は既に[_activeDownloads]から
  /// 取り除かれているので、ここでは触れない(＝自動再開の対象にもならない)。
  Future<void> _handleAppBackgrounded() async {
    final groupKeys = _activeDownloads.keys.toList();
    if (groupKeys.isEmpty) return;

    for (final groupKey in groupKeys) {
      final handle = _activeDownloads.remove(groupKey);
      if (handle == null) continue;
      _update(
        groupKey,
        AsrLanguageModelState(status: AsrModelStatus.paused, progress: statusFor(groupKey).progress),
      );
      await handle.cancel();
      dev.log('⏸️ [AsrModelManager] auto-paused "$groupKey" due to app backgrounding');
    }

    final existing = RecordingPreferences().getAutoPausedAsrGroupKeys();
    final merged = {...existing, ...groupKeys}.toList();
    await RecordingPreferences().setAutoPausedAsrGroupKeys(merged);
  }

  /// アプリがフォアグラウンドに戻った(または起動直後の)タイミングで、
  /// 前回自動一時停止されたまま残っているダウンロードがあれば自動的に
  /// 再開する。ユーザーが手動でpauseしたものは対象に含まれない
  /// ([_handleAppBackgrounded]がそれらを記録していないため)。
  Future<void> _handleAppForegrounded() async {
    final autoPaused = RecordingPreferences().getAutoPausedAsrGroupKeys();
    if (autoPaused.isEmpty) return;
    await RecordingPreferences().setAutoPausedAsrGroupKeys([]);

    for (final groupKey in autoPaused) {
      try {
        dev.log('▶️ [AsrModelManager] auto-resuming "$groupKey" after returning to foreground');
        await _ensureAssetForGroupKey(groupKey);
      } catch (e, st) {
        dev.log('🚨 [AsrModelManager] auto-resume failed for "$groupKey"', error: e, stackTrace: st);
      }
    }
  }

  /// groupKeyから直接manifest上のAsrModelInfoを逆引きして[_ensureAsset]を
  /// 呼ぶ。バックグラウンド復帰時の自動再開は、どのgroupKeyが中断していたか
  /// しか覚えていないため。
  Future<void> _ensureAssetForGroupKey(String groupKey) async {
    final manifest = await _repo.fetchManifest();

    if (groupKey == kVadPseudoLanguageCode) {
      final info = manifest.vad;
      if (info != null) await _ensureAsset(groupKey, manifest.engineCompatVersion, info);
      return;
    }
    if (groupKey == kWhisperPseudoLanguageCode) {
      final info = manifest.whisper;
      if (info != null) await _ensureAsset(groupKey, manifest.engineCompatVersion, info);
    }
  }

  /// 指定キーのローカルパス(ダウンロード済みでreadyな場合のみ)。エンジン初期化に使う。
  /// [key]は`kVadPseudoLanguageCode`または`kWhisperPseudoLanguageCode`。
  /// DBの`status`が'ready'でも、実ファイルが(ストレージクリア等で)既に
  /// 存在しない場合があるため、必ずファイル存在チェックも行う。
  Future<String?> localPathFor(String key) async {
    final row =
        await (_db.select(_db.localAsrModels)..where((t) => t.groupKey.equals(key))).getSingleOrNull();
    if (row == null || row.status != 'ready') return null;
    if (!await Directory(row.localPath).exists()) return null;
    return row.localPath;
  }

  /// 起動直後、マニフェストのネットワーク取得を待たずに、DB+ファイル存在
  /// チェックだけで`ready`と判定できるものを先に反映しておく。共有アセットは
  /// VAD/Whisperの2つ固定なので、そのままこの2キーだけを見ればよい。実際に
  /// モデルが使える状態かどうかは`_ensureAsset`と全く同じ基準
  /// (status=='ready' かつディレクトリが実在)で判定するため、二重管理には
  /// ならない。
  Future<void> _reconcileFromDiskAtStartup() async {
    for (final key in [kVadPseudoLanguageCode, kWhisperPseudoLanguageCode]) {
      try {
        final row =
            await (_db.select(_db.localAsrModels)..where((t) => t.groupKey.equals(key))).getSingleOrNull();
        if (row == null || row.status != 'ready') continue;
        if (!await Directory(row.localPath).exists()) continue;
        _markInstalled(key, true);
        _update(key, const AsrLanguageModelState(status: AsrModelStatus.ready));
      } catch (e, st) {
        dev.log('🚨 [AsrModelManager] disk reconcile failed for "$key"', error: e, stackTrace: st);
      }
    }
  }
}

/// アプリのフォアグラウンド/バックグラウンド遷移をAsrModelManagerへ橋渡しする
/// だけの小さなobserver。didChangeAppLifecycleStateのpaused/detachedを
/// 「バックグラウンド化」、resumedを「フォアグラウンド復帰」として扱う
/// (inactiveは通知バナー等の一時的な中断でも発火するため無視する)。
class _AsrLifecycleObserver extends WidgetsBindingObserver {
  _AsrLifecycleObserver({required this.onBackgrounded, required this.onForegrounded});

  final Future<void> Function() onBackgrounded;
  final Future<void> Function() onForegrounded;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        onBackgrounded();
      case AppLifecycleState.resumed:
        onForegrounded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
