// lib/application/recording/recovery/recovery_providers.dart

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart' show StreamProvider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/application/recording/recovery/recording_recovery_service.dart';
import 'package:lefture/application/recording/recovery/recovery_models.dart';
import 'package:lefture/application/recording/recording_controller.dart'
    show audioRecorderService, audioRecorderServiceProvider;
import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/recording_repository_drift.dart';

part 'recovery_providers.g.dart';

// audioRecorderServiceに依存していることを明示しないと(dependencies無しの
// 既定@riverpodは「スコープ不明な提供元には依存できない」というdebug安全
// 機構に引っかかり、実行時にAsyncErrorで落ちる — audioRecorderServiceProvider
// はdev_tools/のTestタブから差し替え可能な「スコープ可能provider」として
// dependencies: []を宣言済みのため。recording_controller.dartのRecordingController
// と同じ理由・同じ書き方。
@Riverpod(keepAlive: true, dependencies: [audioRecorderService])
RecordingRecoveryService recordingRecoveryService(Ref ref) {
  final service = RecordingRecoveryService(
    repo: ref.watch(recordingRepositoryDriftProvider),
    recorder: ref.watch(audioRecorderServiceProvider),
    uploadManager: ref.watch(uploadManagerProvider),
    lectureRepo: ref.watch(lectureRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// 起動時に一度検出し、見つかった孤児のエンコードをバックグラウンドで
/// 自動的に開始する(カードを開くのを待たない — ユーザーが「壊れているのでは」
/// と不安になる時間を最小化するため)。
///
/// app.dartがtutorialLectureSeedProvider/uploadManagerProviderと同じ形で
/// ref.watchしてアプリ起動と同時に必ず生成させる想定。
///
/// recordingRecoveryServiceProviderがdependenciesを宣言した(スコープ可能な
/// audioRecorderServiceProviderに依存するため)ことで、それをwatchする
/// このプロバイダも連鎖的にdependenciesの明示が必要になる。
@Riverpod(keepAlive: true, dependencies: [recordingRecoveryService])
class OrphanRecordings extends _$OrphanRecordings {
  @override
  Future<List<OrphanRecording>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      // ★ ここで無言でreturnすると、「検出処理自体が一度も走っていない
      // (認証がまだ確立していない)」のか「走った上で0件だった」のか
      // DevLogから区別できなくなる。診断のため必ず1行残す。
      DevLog.add('🔎 [Recovery] Skipped detection: no signed-in user yet.');
      return const [];
    }

    final service = ref.watch(recordingRecoveryServiceProvider);
    final orphans = await service.detectOrphans(userId: user.id);

    // ★ 0件の場合も必ずログを出す。以前はorphans.isNotEmptyの時しかログが
    // 無く、「検出処理が実行されて0件だった」のか「そもそも実行されて
    // いない」のかDevLogから区別できなかった。
    DevLog.add('🔎 [Recovery] Detection finished: ${orphans.length} orphaned recording(s) for user ${user.id}.');

    if (orphans.isNotEmpty) {
      // awaitしない: 起動をブロックしない。エンコードはRecordingRecoveryService
      // 内部で順番に処理され、進捗はrecoveryEncodeStateProviderで別途配信される。
      unawaited(service.encodeAllInBackground(orphans));
    }

    return orphans;
  }

  /// 分析開始/削除の後に呼ぶ。検出条件(ファイルの有無・ジョブの有無)は
  /// その操作で変わっているはずなので、作り直して一覧を最新化する。
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// [lectureId]のエンコード進捗を購読する。
/// recordingRecoveryServiceProviderのdependencies宣言を連鎖的に受け継ぐ
/// 必要がある理由はOrphanRecordingsのコメントを参照。
@Riverpod(dependencies: [recordingRecoveryService])
Stream<RecoveryEncodeState> recoveryEncodeState(Ref ref, String lectureId) {
  return ref.watch(recordingRecoveryServiceProvider).watchEncodeState(lectureId);
}

/// 復旧カードがタイトル/録音言語/Realtime有無を表示するための、単一講義の
/// ローカルDB行watch。domain層のLectureはこれらのフィールドを持たないため
/// (Supabaseに一度も同期されない孤児講義には無関係な列のため)、ローカルDB
/// 直参照が必要。
///
/// ★ @riverpodのコード生成マクロではなく手書きのStreamProvider.familyを使う
/// (upload_manager.dartのstartAnalysisJobsProvider等と同じ書き方) —
/// LocalLecture(Drift生成のnullable row型)を@riverpod関数の戻り値型にすると
/// riverpod_generatorが`InvalidTypeException: The type is invalid and cannot
/// be converted to code`で落ちる(実機検証済み)。Drift型を直接返す既存の
/// providerが軒並み手書きなのはこれが理由と思われる。
final recoveryLectureProvider = StreamProvider.family<LocalLecture?, String>((ref, lectureId) {
  return ref.watch(recordingRepositoryDriftProvider).watchLecture(lectureId);
});
