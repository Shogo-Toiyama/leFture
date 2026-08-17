// lib/presentation/pages/profile/widgets/sign_out_flow.dart
//
// サインアウトの一連の流れ(未同期データの送信 → 破棄の同意 → ローカルデータの
// wipe → signOut)。
//
// サインアウトでローカルデータを全消しする理由と、消す/残すの線引きは
// [LocalDataWipeService]のヘッダコメントを参照。ここでは「消す前に、ユーザーの
// 意思確認と救済(送信のリトライ)を必ず通す」ことを担保する。
//
// 設計方針: ダイアログは本当に危ない時だけ出す。オンラインで未同期データが無い
// 大多数のケースでは、確認ダイアログは1枚も増えない。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/auth/local_data_wipe_service.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/recording/recording_state.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';

/// 未送信データの送信を試みる待ち時間の上限。長時間の講義音声はこの時間では
/// 終わらないので、送り切れなかった分は破棄の同意ダイアログへ回す(そこで
/// 「サインアウトしない」を選べば、アップロードはバックグラウンドで続く)。
const _drainTimeout = Duration(seconds: 20);

/// サインアウトのエントリポイント。My Accountの「Sign Out」から呼ぶ。
Future<void> runSignOutFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final uid = supabase.auth.currentUser?.id;

  // 1. 録音中(一時停止中も含む)はサインアウトさせない。録音中の音声はまだ
  //    どこにも保存し切れていないため、wipeすると丸ごと失われる。
  final phase = ref.read(recordingControllerProvider).phase;
  if (phase == RecordingPhase.recording ||
      phase == RecordingPhase.paused ||
      phase == RecordingPhase.requestingPermission) {
    await showCustomDialog(
      context: context,
      title: l10n.signOutBlockedByRecordingTitle,
      message: l10n.signOutBlockedByRecordingMessage,
      confirmLabel: l10n.signOutBlockedByRecordingConfirmButton,
      cancelLabel: null,
      icon: Icons.mic_rounded,
    );
    return;
  }

  // Providerへの参照は「まだウィジェットがmountされている今」のうちに取り出す。
  // WidgetRefはBuildContextに紐づくため、await後(=サインアウトでWelcomeへ
  // 遷移してMyAccountPageが破棄された後)に ref.read すると
  // 「Using "ref" when a widget is about to or has been unmounted is unsafe」で
  // 落ちる。ここで掴むNotifier/Manager自体はkeepAliveなProviderのインスタンス
  // なので、ウィジェットの寿命とは無関係に使い続けられる。
  final wipeService = LocalDataWipeService(ref.read(appDatabaseProvider));
  final lectureController = ref.read(lectureControllerProvider.notifier);
  final uploadManager = ref.read(uploadManagerProvider);

  var pending = uid == null
      ? const PendingSyncSummary.empty()
      : await wipeService.countPending(userId: uid);
  var isOnline = await isDeviceOnline();

  // 2. オンラインで未同期データがあるなら、まず送り切ることを試す。これが
  //    成功すれば「消えるもの」は無くなり、確認ダイアログも出さずに済む。
  if (isOnline && pending.isNotEmpty && uid != null) {
    if (!context.mounted) return;
    final progress = _showSyncingDialog(context, l10n);
    try {
      await _drainPendingSync(
        lectureController: lectureController,
        uploadManager: uploadManager,
        wipeService: wipeService,
        uid: uid,
      );
    } finally {
      progress.close();
    }
    pending = await wipeService.countPending(userId: uid);
    isOnline = await isDeviceOnline();
  }

  // 3. 「未同期のまま消えるものがある」か「オフライン(=再サインインできない)」
  //    のどちらかに当てはまる時だけ、明示的な同意を取る。
  if (pending.isNotEmpty || !isOnline) {
    if (!context.mounted) return;
    final confirmed = await showCustomDialog(
      context: context,
      title: isOnline ? l10n.signOutPendingTitle : l10n.signOutOfflineTitle,
      message: _buildWarningMessage(l10n, pending: pending, isOnline: isOnline),
      confirmLabel: l10n.signOutDiscardConfirmButton,
      cancelLabel: l10n.signOutStayCancelButton,
      icon: Icons.logout_rounded,
      isDestructive: true,
    );
    if (confirmed != true) return;
  }

  if (!context.mounted) return;
  await _signOutAndWipe(
    context,
    ref,
    wipeService,
    lectureController: lectureController,
    pending: pending,
  );
}

/// 未送信の変更をサーバーへ送る。
///
/// これが「最後の送信機会」なので、
/// - バックオフ待ち/ギブアップ済みの行もリトライ枠を解除して対象に含める
///   (送り先が既に消えている行はハンドラが畳んでOutboxから消えるため、ゴミ行の
///   掃除にもなる)
/// - 1回のpushは最大50行([AppDatabase.dequeuePendingOutbox]のlimit)なので、
///   ポーリングのたびにpushし直す(1回だけだと51行目以降が捨てられる)
/// - 進まなくなったら[_drainTimeout]を待たずに切り上げる(送れない行が残っている
///   端末で毎回20秒フリーズするのを避ける)
Future<void> _drainPendingSync({
  required LectureController lectureController,
  required UploadManager uploadManager,
  required LocalDataWipeService wipeService,
  required String uid,
}) async {
  final revived = await wipeService.reviveOutboxRetries();
  if (revived > 0) {
    DevLog.add('♻️ [SignOut] Cleared retry backoff on $revived outbox row(s) for a last attempt');
  }

  // アップロードキューも起こしておく。UploadManagerは自前のキュー処理なので、
  // 完了は件数の変化で観測する。
  try {
    uploadManager.tryProcessQueue();
  } catch (e) {
    DevLog.add('⚠️ [SignOut] Upload queue kick before sign-out failed: $e');
  }

  final deadline = DateTime.now().add(_drainTimeout);
  var previousChangeCount = -1;

  while (true) {
    try {
      await lectureController.pushOutboxNow();
    } catch (e) {
      DevLog.add('⚠️ [SignOut] Outbox push before sign-out failed: $e');
    }

    final pending = await wipeService.countPending(userId: uid);
    if (pending.isEmpty) return;

    // 未送信の変更が1件も減らず、音声のアップロード待ちも無い = これ以上
    // 待っても状況は変わらない。
    final madeProgress = pending.pendingChangeCount != previousChangeCount;
    previousChangeCount = pending.pendingChangeCount;
    if (!madeProgress && pending.pendingRecordingCount == 0) {
      DevLog.add('🛑 [SignOut] Drain made no progress ($pending) — not waiting further');
      return;
    }

    if (!DateTime.now().isBefore(deadline)) {
      DevLog.add('⏱️ [SignOut] Drain timed out; some data is still unsynced ($pending)');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// wipeとsignOutの実行。
///
/// 順序が重要: 先に[supabase.auth.signOut]でセッションを落としてからwipeする。
/// サインイン状態のままローカルDBを空にすると、まだ生きているProvider
/// (チュートリアル講義のシードなど)が「データが無い」と判断して即座に作り直し、
/// 消したはずの行が復活しうる。
///
/// signOut後にwipeが中断された場合は残骸が残るが、次回サインイン時の
/// [LocalDataWipeService.wipeOtherUsers]が回収する。
Future<void> _signOutAndWipe(
  BuildContext context,
  WidgetRef ref,
  LocalDataWipeService wipeService, {
  required LectureController lectureController,
  required PendingSyncSummary pending,
}) async {
  // ウィジェットが生きているうちに済ませる処理は、遷移より前にまとめて行う。
  ref.invalidate(courseListProvider);

  // onAuthStateChangeによるGoRouterの/sign_inへの割り込みリダイレクトを防ぐため、
  // signOut()の前にまず公開ルートであるWelcome画面へ遷移しておく。
  context.go(AppRoutes.welcome);

  try {
    await supabase.auth.signOut();
  } catch (e) {
    // gotrueのsignOut()はローカルセッションを先に破棄してからサーバーへ通知
    // するため、オフラインではこのネットワーク例外が飛ぶ。サインアウト自体は
    // 既に成立しているので、wipeへ進んで良い。
    DevLog.add('⚠️ [SignOut] signOut() threw (session is already cleared locally): $e');
  }

  if (pending.isNotEmpty) {
    DevLog.add('🗑️ [SignOut] Discarding unsynced data: $pending');
  }
  await wipeService.wipeAll();

  // ローカルDBを空にしたので、次のサインインでは必ず全件Pullし直す必要がある。
  // LectureControllerはkeepAliveでプロセス内に生き残るため、15分スロットルの
  // 記録もサインアウトを跨いで残ってしまう(同じアカウントで入り直した場合は
  // uid判定もすり抜ける)。ここで明示的に捨てる。
  //
  // ここは既にWelcomeへ遷移した後なので、ref.readは使えない
  // (MyAccountPageが破棄されており「ref ... unmounted is unsafe」で落ちる)。
  // 呼び出し元がmount中に取得しておいたNotifierを使う。
  lectureController.resetThrottle();

  // r2_cache/配下の実ファイルも消したので、キャッシュ済みのFileパスを
  // 保持しているProviderを無効化する。これを忘れると、次のサインイン後に
  // Image.fileが消えたパスを読もうとしてPathNotFoundExceptionを投げ続ける。
  lectureController.invalidateArtifactFileCache();
}

String _buildWarningMessage(
  AppLocalizations l10n, {
  required PendingSyncSummary pending,
  required bool isOnline,
}) {
  final lines = <String>[];
  if (pending.isNotEmpty) {
    lines.add(l10n.signOutPendingIntro);
    if (pending.pendingChangeCount > 0) {
      lines.add(l10n.signOutPendingChangesLine(pending.pendingChangeCount));
    }
    if (pending.pendingRecordingCount > 0) {
      lines.add(l10n.signOutPendingRecordingsLine(pending.pendingRecordingCount));
    }
  }
  if (!isOnline) {
    lines.add(l10n.signOutOfflineLine);
  }
  return lines.join('\n\n');
}

/// 閉じるボタンの無い進捗ダイアログ。呼び出し側が[_ProgressDialogHandle.close]で閉じる。
_ProgressDialogHandle _showSyncingDialog(
  BuildContext context,
  AppLocalizations l10n,
) {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161829),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.universe.glassBorder),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.starGold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l10n.signOutSyncingMessage,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return _ProgressDialogHandle(navigator);
}

class _ProgressDialogHandle {
  _ProgressDialogHandle(this._navigator);

  final NavigatorState _navigator;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (_navigator.canPop()) _navigator.pop();
  }
}
