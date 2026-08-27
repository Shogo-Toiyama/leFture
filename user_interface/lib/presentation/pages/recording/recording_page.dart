// import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/themes/app_colors.dart'; // 色追加
// AIチャットはApple審査対応のため一時的に非表示。再有効化時にコメントアウトを外す。
// import 'package:lefture/presentation/widgets/ai_chat_sheet.dart';
import 'package:lefture/application/recording/lecture_moments_provider.dart';
import 'package:lefture/application/recording/live_transcript_provider.dart';
import 'package:lefture/application/asr/live_asr_controller.dart';
import 'package:lefture/core/services/asr_engine/asr_engine_status.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/domain/entities/lecture_moment.dart';
import 'package:lefture/domain/entities/live_transcript_sentence.dart';
import 'package:lefture/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lefture/presentation/widgets/asr_model_dialog_helpers.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';
import '../../../core/services/audio_record/audio_recorder_service.dart';
import '../dev_tools/simulate_recording_tab.dart';
import '../dev_tools/test_mode_flag.dart';
import 'widgets/audio_waveform_visualizer.dart';
import 'widgets/live_listening_indicator.dart';
import 'widgets/course_picker_sheet.dart';

class RecordingPage extends HookConsumerWidget {
  const RecordingPage({super.key, this.initialTab, this.initialCourseId});

  // URLパラメータなどでタブ指定を受け取れるように拡張
  final String? initialTab;
  final String? initialCourseId;

  Future<void> _showConsentDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    bool dontShowAgain = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF13131C),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppColors.universe.glassBorder),
              borderRadius: BorderRadius.circular(20),
            ),
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.starGold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.recordingConsentDialogTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.recordingConsentDialogMessage,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showConsentInfoDialog(ctx, l10n),
                        tooltip: l10n.recordingConsentInfoTooltip,
                        icon: Icon(
                          Icons.info_outline,
                          color: AppColors.universe.textComet,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setState(() => dontShowAgain = !dontShowAgain),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Checkbox(
                            value: dontShowAgain,
                            onChanged: (value) =>
                                setState(() => dontShowAgain = value ?? false),
                            activeColor: AppColors.starGold,
                            checkColor: Colors.black,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.recordingConsentDialogCheckboxLabel,
                              style: TextStyle(
                                color: AppColors.universe.textComet,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (dontShowAgain) {
                      RecordingPreferences().setHasSeenRecordingConsentNotice(
                        true,
                      );
                    }
                    ctx.pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.starGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    l10n.recordingConsentDialogConfirmButton,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showConsentInfoDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13131C),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          l10n.recordingConsentInfoDialogTitle,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Text(
            l10n.recordingConsentInfoDialogBody,
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: Text(
              l10n.recordingConsentInfoDialogCloseButton,
              style: TextStyle(
                color: AppColors.starGold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _format(int sec) {
    final h = (sec ~/ 3600).toString();
    final m = ((sec ~/ 60) % 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // 周囲の同意を得てから録音するよう、毎回リマインドする。
    // 「次回以降表示しない」にチェックして確認した場合のみ、以後は出さない。
    useEffect(() {
      if (!RecordingPreferences().getHasSeenRecordingConsentNotice()) {
        Future.microtask(() {
          if (context.mounted) {
            _showConsentDialog(context, l10n);
          }
        });
      }
      return null;
    }, []);

    // タブコントローラー (Voice / Live、isTestModeの時だけTestタブが加わる)
    final tabController = useTabController(initialLength: isTestMode ? 3 : 2);

    // Liveタブ(index 1)が表示中かどうかをLiveAsrControllerへ通知する。
    // Liveタブを見ていない間はオンデバイスASRの重い処理(VAD推論・デコード)を
    // 一時停止し、バッテリー消費を抑える(音声の受け取り自体は止めない)。
    useEffect(() {
      void listener() {
        ref
            .read(liveAsrControllerProvider.notifier)
            .setLiveTabFocused(tabController.index == 1);
      }

      tabController.addListener(listener);
      listener(); // マウント時点の初期状態を反映
      return () => tabController.removeListener(listener);
    }, [tabController]);

    // ページ自体から離れる(タブ切り替えではなく画面遷移)時もLiveタブは
    // 見えなくなるので、一時停止扱いにする。上のeffectとは意図的に分けている
    // (tabControllerのリスナー解除と「ページ離脱」を1つのeffectに混ぜると、
    // 将来的にクリーンアップの意味が食い違って事故りやすいため)。
    useEffect(() {
      final liveAsrNotifier = ref.read(liveAsrControllerProvider.notifier);
      return () {
        Future.microtask(() => liveAsrNotifier.setLiveTabFocused(false));
      };
    }, []);

    // MVPのためコメントアウト
    // final memoCtl = useTextEditingController();
    // useListenable(memoCtl);
    final showMoreSettings = useState(false);
    final moreSettingsKey = useMemoized(() => GlobalKey());
    final scrollController = useScrollController();
    final selectedAudioFilePath = useState<String?>(null);
    final isSelectingFile = useState(false);

    // 初期タブの設定 (noteなら1番目) - MVPのためコメントアウト
    /*
    useEffect(() {
      if (initialTab == 'note') {
        tabController.animateTo(1);
      }
      return null;
    }, []);
    */

    // コースIDの初期設定
    useEffect(() {
      if (initialCourseId != null) {
        Future.microtask(() {
          ref
              .read(recordingControllerProvider.notifier)
              .setCourseId(initialCourseId);
        });
      }
      return null;
    }, [initialCourseId]);

    // マイク許可を、録音ボタンを押す前に前倒しでリクエストしておく
    // (授業が始まってしまってからもたつかないように、ページに入った瞬間に済ませる)。
    // ASRモデルの準備は、Realtime Recordingが有効な場合のみ行う
    // (無効なら無駄なダウンロードを避ける)。
    useEffect(() {
      Future.microtask(() async {
        final micStatus = await ref
            .read(recordingControllerProvider.notifier)
            .requestMicPermissionEarly();
        // permanentlyDenied/restrictedならOSは二度とダイアログを出さない
        // (特にiOS)ため、request()だけでは何も起きない。設定画面へ誘導する。
        if ((micStatus.isPermanentlyDenied || micStatus.isRestricted) &&
            context.mounted) {
          final openSettings = await showCustomDialog(
            context: context,
            title: l10n.recordingMicSettingsDialogTitle,
            message: l10n.recordingMicSettingsDialogMessage,
            cancelLabel: l10n.recordingMicSettingsDialogLater,
            confirmLabel: l10n.recordingMicSettingsDialogOpenSettings,
            icon: Icons.mic_off_rounded,
          );
          if (openSettings == true) {
            await openAppSettings();
          }
        }
        if (RecordingPreferences().getRealtimeTranscribe()) {
          final lang = ref.read(recordingLanguageControllerProvider);
          final modelManager = ref.read(asrModelManagerProvider.notifier);
          await modelManager.ensureModelReady(lang);
          // モデルが結局用意できなかった場合、Realtime Transcribeが「On」の
          // まま実体の無い機能として残ってしまう(裏でモデルが動いていると
          // 誤解する原因にもなる)ため、ここで自動的にOffへ戻す。
          //
          // 判定は`installed`で行う。オフラインで更新確認に失敗しただけ
          // (=モデルは手元にあって使える)の場合まで勝手にOffにされると、
          // ユーザーからは「何もしていないのに切れた」ようにしか見えない。
          final modelState = modelManager.statusForLanguage(lang);
          if (!modelState.installed &&
              modelState.status == AsrModelStatus.failed) {
            await ref
                .read(recordingControllerProvider.notifier)
                .setRealtimeTranscribe(false);
          }
        }
      });
      return null;
    }, []);

    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);

    final recordingLanguage = ref.watch(recordingLanguageControllerProvider);
    ref.watch(asrModelManagerProvider);
    final asrModelState = ref
        .read(asrModelManagerProvider.notifier)
        .statusForLanguage(recordingLanguage);

    // Realtime Transcribeタイルの表示分岐。`installed`(モデルの実体が手元に
    // あるか)と`status`(今この瞬間の取得処理の進行状況)は別物なので混同しない。
    //
    // - 未インストール → ON/OFFではなくダウンロード導線を出す
    // - インストール済み → 常にON/OFFスイッチを出す(裏で更新確認/再取得が
    //   走っていてもスイッチは消さず、タイトル横の小さなスピナーで知らせる)
    // - エラー表示は「モデルが無く、かつ取得にも失敗した」ときだけ。オフラインで
    //   更新確認に失敗しただけならモデルは使えるので、赤字で不安にさせない。
    final asrModelErrored =
        asrModelState.status == AsrModelStatus.failed &&
        !asrModelState.installed;
    final asrModelUpdating =
        asrModelState.installed &&
        (asrModelState.status == AsrModelStatus.checking ||
            asrModelState.status == AsrModelStatus.downloading);
    // 取得が進行中(downloading/checking/paused)のときに行全体をタップしても
    // ダウンロード確認ダイアログを出し直さないよう、開始できる状態かを見る。
    final asrModelDownloadable =
        !asrModelState.installed &&
        (asrModelState.status == AsrModelStatus.unknown ||
            asrModelState.status == AsrModelStatus.failed ||
            asrModelState.status == AsrModelStatus.ready);
    // Realtime Transcribeの設定は録音を始める前にしか変更できない。
    final realtimeLocked = state.phase != RecordingPhase.idle;

    Future<void> showRealtimeLockedDialog() => showCustomDialog(
      context: context,
      title: l10n.recordingRealtimeLockedDialogTitle,
      message: l10n.recordingRealtimeLockedDialogMessage,
      icon: Icons.lock_outline,
      confirmLabel: l10n.coursePageOkButton,
      cancelLabel: null,
    );

    /// ONにできなかった理由をユーザーに見える形で伝える。無言でトグルが
    /// 元に戻るだけ、という状態を作らないこと。
    Future<void> showRealtimeToggleFailure(RealtimeToggleResult result) async {
      switch (result) {
        case RealtimeToggleResult.ok:
          return;
        case RealtimeToggleResult.lockedWhileRecording:
          await showRealtimeLockedDialog();
        case RealtimeToggleResult.insufficientCredits:
          final confirmed = await showCustomDialog(
            context: context,
            title: l10n.recordingRealtimeCreditsDialogTitle,
            message: l10n.recordingRealtimeCreditsDialogMessage,
            icon: Icons.account_balance_wallet_outlined,
            confirmLabel: l10n.recordingRealtimeCreditsDialogConfirm,
            cancelLabel: l10n.recordingCancelButton,
          );
          if (confirmed == true && context.mounted) {
            context.push(AppRoutes.creditDetail);
          }
      }
    }

    Future<void> confirmAndDownloadAsrModel() async {
      final confirmed = await showCustomDialog(
        context: context,
        title: l10n.recordingSpeechModelDialogTitle,
        message: l10n.recordingSpeechModelDialogMessage,
        icon: Icons.download_rounded,
        confirmLabel: l10n.recordingSpeechModelDownloadConfirm,
        cancelLabel: l10n.recordingCancelButton,
      );
      if (confirmed != true) return;
      // ダウンロードを始める＝この機能を使う意思表示なので、先にONにしておく
      // (完了を待たずに録音を始めても、準備でき次第字幕が出る)。ONにできない
      // 場合は理由を伝えて、数百MBのダウンロードには進まない。
      final result = await controller.setRealtimeTranscribe(true);
      if (!context.mounted) return;
      if (result != RealtimeToggleResult.ok) {
        await showRealtimeToggleFailure(result);
        return;
      }
      await ensureAsrModelWithErrorDialog(context, ref, recordingLanguage);
    }

    final coursesAsync = ref.watch(courseListProvider);
    final courses = coursesAsync.asData?.value ?? const [];
    final selectedCourse = state.courseId != null
        ? courses.any((c) => c.id == state.courseId)
              ? courses.firstWhere((c) => c.id == state.courseId)
              : null
        : null;

    final courseColor = selectedCourse != null
        ? CourseStyleHelper.hexToColor(
            selectedCourse.color,
            fallback: AppColors.starGold,
          )
        : AppColors.starGold;
    final HSLColor hsl = HSLColor.fromColor(courseColor);
    final displayIconColor = hsl.lightness < 0.45
        ? hsl.withLightness(0.55).toColor()
        : courseColor;
    final iconData = selectedCourse != null
        ? CourseStyleHelper.getIcon(selectedCourse.icon)
        : Icons.folder_outlined;

    // 録音完了時の自動クローズ監視
    ref.listen<RecordingState>(recordingControllerProvider, (previous, next) {
      final isDone = next.phase == RecordingPhase.queued;
      final wasDone = previous?.phase == RecordingPhase.queued;
      if (isDone && !wasDone) {
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            context.pop();
            ref.invalidate(recordingControllerProvider);
          }
        });
      }
    });

    // フェーズを変えない一回きりの通知(例: モデルダウンロード中に録音を
    // 始めた場合の案内)をSnackBarで表示する。
    ref.listen<RecordingState>(recordingControllerProvider, (previous, next) {
      final notice = next.transientNotice;
      if (notice == null || notice == previous?.transientNotice) return;
      controller.clearTransientNotice();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notice)));
      }
    });

    final titleCtl = useTextEditingController(text: state.title);
    // タイトル同期
    useEffect(() {
      if (titleCtl.text != state.title) {
        titleCtl.text = state.title;
        // カーソル位置を維持しようとすると厄介なので、入力中は同期しない等の工夫も必要だが
        // ここでは単純に末尾へ移動
        titleCtl.selection = TextSelection.collapsed(
          offset: titleCtl.text.length,
        );
      }
      return null;
    }, [state.title]);

    // 共通スタイル定義
    InputDecoration glassInputDecoration(
      String label,
      IconData icon, {
      String? hintText,
    }) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        hintText: hintText,
        hintStyle: TextStyle(
          color: AppColors.universe.textComet.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: AppColors.universe.textComet),
        filled: true,
        fillColor: AppColors.universe.glassWhiteLow,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.starGold),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    /// [trailing]が渡された場合は、トグルスイッチの代わりにその
    /// ウィジェット(ダウンロードボタン等)を右側に置いた行を作る。
    /// その場合[onTileTap]で行全体のタップも受けられる。
    Widget buildToggleRow({
      required IconData icon,
      required String title,
      required String subtitle,
      Color? subtitleColor,
      Widget? titleTrailing,
      Widget? trailing,
      VoidCallback? onTileTap,
      required bool value,
      required ValueChanged<bool>? onChanged,
      bool dimmed = false,
    }) {
      final titleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (titleTrailing != null) ...[
            const SizedBox(width: 8),
            titleTrailing,
          ],
        ],
      );
      final subtitleWidget = Text(
        subtitle,
        style: TextStyle(
          color: subtitleColor ?? AppColors.universe.textComet,
          fontSize: 11,
        ),
      );
      const contentPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 4);

      return Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C2E).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.universe.glassBorder),
          ),
          child: trailing != null
              ? ListTile(
                  tileColor: Colors.transparent,
                  leading: Icon(icon, color: AppColors.universe.textComet),
                  title: titleWidget,
                  subtitle: subtitleWidget,
                  trailing: trailing,
                  onTap: onTileTap,
                  contentPadding: contentPadding,
                )
              : SwitchListTile(
                  tileColor: Colors.transparent,
                  secondary: Icon(icon, color: AppColors.universe.textComet),
                  title: titleWidget,
                  subtitle: subtitleWidget,
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: AppColors.starGold,
                  activeTrackColor: AppColors.starGold.withValues(alpha: 0.3),
                  inactiveThumbColor: AppColors.universe.textComet,
                  inactiveTrackColor: AppColors.universe.glassWhiteLow,
                  contentPadding: contentPadding,
                ),
        ),
      );
    }

    /// ダウンロードの進行状況に応じたアクションアイコン
    /// (ダウンロード / 一時停止 / 再開 / 再試行)。
    Widget buildAsrActionIcon({
      required AsrLanguageModelState modelState,
      required VoidCallback onDownloadTap,
      required VoidCallback onPauseTap,
      required VoidCallback onResumeTap,
    }) {
      switch (modelState.status) {
        case AsrModelStatus.checking:
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.universe.textComet,
              ),
            ),
          );

        case AsrModelStatus.downloading:
          final progress = modelState.progress;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 2.5,
                      value: progress,
                      color: AppColors.starGold,
                      backgroundColor: AppColors.universe.glassWhiteLow,
                    ),
                    if (progress != null)
                      Text(
                        '${(progress * 100).round()}',
                        style: const TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.starGold,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.pause_circle_outline),
                color: AppColors.universe.textComet,
                iconSize: 22,
                tooltip: l10n.recordingSpeechModelPauseTooltip,
                onPressed: onPauseTap,
              ),
            ],
          );

        case AsrModelStatus.paused:
          return IconButton(
            icon: const Icon(Icons.play_circle_outline),
            color: AppColors.starGold,
            iconSize: 24,
            tooltip: l10n.recordingSpeechModelResumeTooltip,
            onPressed: onResumeTap,
          );

        case AsrModelStatus.failed:
          return IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.correctionRed,
            iconSize: 22,
            tooltip: l10n.recordingSpeechModelRetryTooltip,
            onPressed: onDownloadTap,
          );

        // `ready`はモデルが揃っている(installed)ときにしか起きず、その場合は
        // 呼び出し元がスイッチを出すのでここへは来ない。万一来た場合も
        // ダウンロード導線を出しておく。
        case AsrModelStatus.unknown:
        case AsrModelStatus.ready:
          return Container(
            decoration: BoxDecoration(
              color: AppColors.starGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.starGold.withValues(alpha: 0.4),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.download_rounded),
              color: AppColors.starGold,
              iconSize: 20,
              tooltip: l10n.recordingSpeechModelDownloadTooltip,
              onPressed: onDownloadTap,
            ),
          );
      }
    }

    /// モデルの実体がまだ手元に無い([AsrLanguageModelState.installed]がfalse)
    /// ときだけ、トグルスイッチの代わりに出すダウンロード導線を返す。モデルが
    /// 揃っていればnullを返し、呼び出し側は通常のON/OFFスイッチを出す。
    ///
    /// 判定に`status`ではなく`installed`を使うのが重要。`status`はページを開く
    /// たびに`checking`へ落ちるし、オフラインなら`failed`にもなるため、これを
    /// 基準にするとダウンロード済みなのにスイッチが消えてしまう。
    ///
    /// [locked](録音中)のときはタップを透過させ、タイル側の
    /// 「録音中は変更できません」ダイアログに繋げる。
    Widget? buildAsrTrailingAction({
      required AsrLanguageModelState modelState,
      required bool locked,
      required VoidCallback onDownloadTap,
      required VoidCallback onPauseTap,
      required VoidCallback onResumeTap,
    }) {
      if (modelState.installed) return null;
      return IgnorePointer(
        ignoring: locked,
        child: buildAsrActionIcon(
          modelState: modelState,
          onDownloadTap: onDownloadTap,
          onPauseTap: onPauseTap,
          onResumeTap: onResumeTap,
        ),
      );
    }

    // コース選択ロジック

    Future<void> openCoursePicker() async {
      final result = await showModalBottomSheet<CoursePickerResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            CoursePickerSheet(initialSelectedCourseId: state.courseId),
      );
      if (result != null && result.confirmed) {
        controller.setCourseId(result.courseId);
      }
    }

    /// アップロード前のコース必須チェック。コース未選択のまま保存すると
    /// バックエンドの自動分析が始まらず(UploadManager/RecordingController
    /// どちらの発火判定もcourseId != nullを要求する)、ユーザーからは
    /// 「アップロードしたのに何も起きない」ようにしか見えないため、
    /// ここで明示的に止めてコース選択へ誘導する。
    /// コースが選ばれた(または元から選ばれていた)場合のみtrueを返す。
    Future<bool> ensureCourseSelected() async {
      if (state.courseId != null) return true;

      final goToPicker = await showCustomDialog(
        context: context,
        title: l10n.recordingCourseRequiredDialogTitle,
        message: l10n.recordingCourseRequiredDialogMessage,
        icon: Icons.school_outlined,
        confirmLabel: l10n.recordingCourseRequiredSelectButton,
        cancelLabel: l10n.recordingCancelButton,
      );
      if (goToPicker != true) return false;

      await openCoursePicker();
      // ピッカーで「コースなしで続ける」を選ぶこともできるため、
      // 戻ってきた時点の最新状態で再確認する。
      return ref.read(recordingControllerProvider).courseId != null;
    }

    final isBusy = state.isBusy;
    final isDonePhase = state.phase == RecordingPhase.queued;

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground, // 宇宙背景
      resizeToAvoidBottomInset: true, // キーボード対応
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: TabBar(
          controller: tabController,
          indicatorColor: AppColors.starGold,
          labelColor: AppColors.starGold,
          unselectedLabelColor: AppColors.universe.textComet,
          dividerColor: AppColors.universe.glassBorder,
          tabs: const [
            Tab(icon: Icon(Icons.mic)),
            Tab(icon: Icon(Icons.forum_outlined)),
            if (isTestMode) Tab(icon: Icon(Icons.bug_report)),
          ],
        ),
        // ★ テスト専用: 実機の短い録音でも「保存直後の画面ロックでOSに
        // アプリを止められる」バグを再現できるよう、意図的にエンコードを
        // 遅らせるスイッチ。実際の講義(90分)でもFFmpegエンコードは10秒未満
        // なので、短い録音では保護の有無に関わらずエンコードが一瞬で終わり、
        // バックグラウンド保護(BackgroundTask)が効いているかを検証できない。
        // isTestModeでのみ表示され、本番ビルドではtree-shakingで消える。
        actions: [
          if (isTestMode) const _DebugSlowEncodeToggle(),
        ],
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: tabController,
            children: [
              // ==========================================
              // Tab 1: Voice (Audio Recording)
              // ==========================================
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: Column(
                            children: [
                              // 1. Course
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.universe.glassWhiteLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.universe.glassBorder,
                                  ),
                                  boxShadow: selectedCourse != null
                                      ? [
                                          BoxShadow(
                                            color: courseColor.withValues(
                                              alpha: 0.16,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          (selectedCourse != null
                                                  ? displayIconColor
                                                  : AppColors
                                                        .universe
                                                        .textComet)
                                              .withValues(alpha: 0.15),
                                    ),
                                    child: Icon(
                                      selectedCourse != null
                                          ? iconData
                                          : Icons.folder_outlined,
                                      color: selectedCourse != null
                                          ? displayIconColor
                                          : AppColors.universe.textComet,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    l10n.recordingCourseLabel,
                                    style: TextStyle(
                                      color: AppColors.universe.textComet,
                                      fontSize: 12,
                                    ),
                                  ),
                                  subtitle: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final text = selectedCourse != null
                                          ? selectedCourse.displayTitle
                                          : l10n.recordingNoCourseSelected;
                                      // 1. テキストのスタイル定義
                                      final style = TextStyle(
                                        color: AppColors.universe.textStarlight,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      );

                                      // 2. 幅に入りきるか計算する関数
                                      bool checkFit(String text) {
                                        final textPainter = TextPainter(
                                          text: TextSpan(
                                            text: text,
                                            style: style,
                                          ),
                                          maxLines: 1,
                                          textDirection: TextDirection.ltr,
                                        )..layout(maxWidth: double.infinity);

                                        // コンテナの幅より小さければOK
                                        return textPainter.size.width <=
                                            constraints.maxWidth;
                                      }

                                      // A. そのままで入るならそのまま表示
                                      if (checkFit(text)) {
                                        return Text(
                                          text,
                                          style: style,
                                          maxLines: 1,
                                        );
                                      }

                                      // B. 入らない場合、パス区切り「 / 」で分解して、左から削っていく
                                      final parts = text.split(' / ');

                                      // 左端から1つずつ削って「... / 」に置き換えて試す
                                      for (int i = 1; i < parts.length; i++) {
                                        final candidate =
                                            '... / ${parts.sublist(i).join(' / ')}';

                                        if (checkFit(candidate)) {
                                          return Text(
                                            candidate,
                                            style: style,
                                            maxLines: 1,
                                          );
                                        }
                                      }

                                      // C. それでも入らない場合（最後の1フォルダすら長い場合）
                                      return Text(
                                        parts.isNotEmpty ? parts.last : text,
                                        style: style,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.white,
                                  ),
                                  onTap: isBusy ? null : openCoursePicker,
                                ),
                              ),

                              // 設定ステータスバッジ（言語 & Realtime）
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: InkWell(
                                  onTap: () {
                                    showMoreSettings.value = true;
                                    Future.delayed(
                                      const Duration(milliseconds: 300),
                                      () {
                                        final ctx =
                                            moreSettingsKey.currentContext;
                                        if (ctx != null && ctx.mounted) {
                                          Scrollable.ensureVisible(
                                            ctx,
                                            alignment: 0.0,
                                            duration: const Duration(
                                              milliseconds: 350,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          );
                                        }
                                      },
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.universe.glassWhiteLow,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppColors.universe.glassBorder,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.language,
                                          size: 14,
                                          color: AppColors.universe.textComet,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            recordingLanguageFromCode(
                                              recordingLanguage,
                                            ).nativeName,
                                            style: TextStyle(
                                              color: AppColors
                                                  .universe
                                                  .textStarlight,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          height: 12,
                                          width: 1,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          color: AppColors.universe.glassBorder,
                                        ),
                                        Icon(
                                          state.realtimeTranscribe
                                              ? Icons.bolt
                                              : Icons.offline_bolt_outlined,
                                          size: 14,
                                          color: state.realtimeTranscribe
                                              ? AppColors.starGold
                                              : AppColors.universe.textComet,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            state.realtimeTranscribe
                                                ? l10n.recordingRealtimeOnBadge
                                                : l10n.recordingRealtimeOffBadge,
                                            style: TextStyle(
                                              color: state.realtimeTranscribe
                                                  ? AppColors.starGold
                                                  : AppColors
                                                        .universe
                                                        .textComet,
                                              fontSize: 12,
                                              fontWeight:
                                                  state.realtimeTranscribe
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 14,
                                          color: AppColors.universe.textComet
                                              .withValues(alpha: 0.6),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // コース未選択時の注意書き（録音開始後のみ表示）
                              if (state.courseId == null &&
                                  (state.phase == RecordingPhase.recording ||
                                      state.phase == RecordingPhase.paused))
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.alertAmber.withValues(
                                        alpha: 0.15,
                                      ),
                                      border: Border.all(
                                        color: AppColors.alertAmber,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: AppColors.alertAmber,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            l10n.recordingNoCourseWarning,
                                            style: TextStyle(
                                              color: AppColors
                                                  .universe
                                                  .textStarlight,
                                              fontSize: 12,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 40),

                              // 3. Timer
                              Text(
                                _format(state.elapsedSeconds),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 64,
                                  fontWeight: FontWeight.w200,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  shadows: [
                                    Shadow(
                                      color:
                                          (state.isRecording
                                                  ? AppColors.correctionRed
                                                  : AppColors.starGold)
                                              .withValues(
                                                alpha: state.isRecording
                                                    ? 0.45
                                                    : 0.22,
                                              ),
                                      blurRadius: 24,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 波形表示 (Audio Visualizer)
                              AudioWaveformVisualizer(
                                audioLevel: state.audioLevel,
                                isRecording: state.isRecording,
                                isPaused: state.isPaused,
                              ),
                              const SizedBox(height: 20),

                              // 4. Big Mic Button (Center)
                              _MicButton(
                                state: state,
                                controller: controller,
                                isBusy: isBusy,
                              ),
                              const SizedBox(height: 16),

                              // Status Text
                              _StatusArea(state: state, controller: controller),

                              // Select Audio File (アイドル時のみ表示)
                              if (state.phase == RecordingPhase.idle) ...[
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: AppColors.universe.glassBorder,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        l10n.recordingOrDivider,
                                        style: TextStyle(
                                          color: AppColors.universe.textComet,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: AppColors.universe.glassBorder,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.universe.glassWhiteLow,
                                    border: Border.all(
                                      color: selectedAudioFilePath.value != null
                                          ? AppColors.starGold
                                          : AppColors.universe.textComet
                                                .withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: isSelectingFile.value
                                          ? null
                                          : () async {
                                              isSelectingFile.value = true;
                                              try {
                                                // FileType.audioはiOSでは「ミュージック
                                                // ライブラリ」ピッカー(MPMediaPickerController)
                                                // を開く実装で、Info.plistに
                                                // NSAppleMusicUsageDescriptionが無いと
                                                // 即クラッシュする上、ダウンロードした
                                                // 音声ファイルやiCloud Drive上のファイルには
                                                // そもそも辿り着けない。FileType.customで
                                                // 拡張子指定すれば標準の書類ピッカー(Files)が
                                                // 開き、ダウンロード/iCloud Drive/他アプリの
                                                // 共有先まで選択できる。
                                                final result =
                                                    await FilePicker.pickFiles(
                                                      type: FileType.custom,
                                                      allowedExtensions: const [
                                                        'mp3',
                                                        'm4a',
                                                        'wav',
                                                        'aac',
                                                        'aiff',
                                                        'caf',
                                                        'flac',
                                                        'ogg',
                                                      ],
                                                      allowMultiple: false,
                                                    );

                                                if (result == null) {
                                                  // ユーザーによるキャンセル
                                                  return;
                                                }

                                                if (result.files.isNotEmpty) {
                                                  final filePath =
                                                      result.files.first.path;
                                                  if (filePath != null &&
                                                      filePath
                                                          .trim()
                                                          .isNotEmpty &&
                                                      context.mounted) {
                                                    selectedAudioFilePath
                                                            .value =
                                                        filePath;
                                                  } else if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          l10n.recordingFileAccessError,
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                }
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        l10n.recordingFileSelectError(
                                                          e.toString(),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } finally {
                                                isSelectingFile.value = false;
                                              }
                                            },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                          horizontal: 12,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (isSelectingFile.value) ...[
                                                  const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(AppColors.starGold),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Flexible(
                                                    child: Text(
                                                      l10n.recordingProcessingAudioFile,
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.starGold,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ] else ...[
                                                  Icon(
                                                    selectedAudioFilePath
                                                                .value !=
                                                            null
                                                        ? Icons.check_circle
                                                        : Icons.upload_file,
                                                    color:
                                                        selectedAudioFilePath
                                                                .value !=
                                                            null
                                                        ? AppColors.starGold
                                                        : AppColors
                                                              .universe
                                                              .textComet,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      selectedAudioFilePath
                                                                  .value !=
                                                              null
                                                          ? l10n.recordingFileSelected
                                                          : l10n.recordingSelectAudioFile,
                                                      style: TextStyle(
                                                        color:
                                                            selectedAudioFilePath
                                                                    .value !=
                                                                null
                                                            ? AppColors.starGold
                                                            : AppColors
                                                                  .universe
                                                                  .textComet,
                                                        fontSize: 16,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (!isSelectingFile.value &&
                                                selectedAudioFilePath.value !=
                                                    null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Text(
                                                  selectedAudioFilePath.value!
                                                      .split('/')
                                                      .last,
                                                  style: TextStyle(
                                                    color: AppColors
                                                        .universe
                                                        .textComet,
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // Discard Button
                              if (state.phase == RecordingPhase.recording ||
                                  state.phase == RecordingPhase.paused ||
                                  state.phase == RecordingPhase.error)
                                TextButton.icon(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor:
                                            AppColors.universe.voidBackground,
                                        shape: RoundedRectangleBorder(
                                          side: BorderSide(
                                            color:
                                                AppColors.universe.glassBorder,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        title: Text(
                                          l10n.recordingDiscardDialogTitle,
                                          style: TextStyle(
                                            color: AppColors
                                                .universe
                                                .textStarlight,
                                          ),
                                        ),
                                        content: Text(
                                          l10n.recordingDiscardDialogMessage,
                                          style: TextStyle(
                                            color: AppColors.universe.textComet,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => ctx.pop(false),
                                            child: Text(
                                              l10n.recordingCancelButton,
                                              style: TextStyle(
                                                color: AppColors
                                                    .universe
                                                    .textComet,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => ctx.pop(true),
                                            child: Text(
                                              l10n.recordingDiscardConfirmButton,
                                              style: const TextStyle(
                                                color: AppColors.correctionRed,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      await controller.cancelAndDiscard();
                                      if (context.mounted) context.pop();
                                    }
                                  },
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: AppColors.universe.textComet,
                                  ),
                                  label: Text(
                                    l10n.recordingDiscardButtonLabel,
                                    style: TextStyle(
                                      color: AppColors.universe.textComet,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 24),

                              // More Settings アコーディオン
                              AnimatedContainer(
                                key: moreSettingsKey,
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: showMoreSettings.value
                                      ? AppColors.starGold.withValues(
                                          alpha: 0.08,
                                        )
                                      : const Color(
                                          0xFF1A1C2E,
                                        ).withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: showMoreSettings.value
                                        ? AppColors.starGold.withValues(
                                            alpha: 0.5,
                                          )
                                        : AppColors.universe.glassBorder,
                                    width: showMoreSettings.value ? 1.5 : 1.0,
                                  ),
                                  boxShadow: [
                                    if (showMoreSettings.value)
                                      BoxShadow(
                                        color: AppColors.starGold.withValues(
                                          alpha: 0.15,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                                child: InkWell(
                                  onTap: () {
                                    final willExpand = !showMoreSettings.value;
                                    showMoreSettings.value = willExpand;
                                    if (willExpand) {
                                      Future.delayed(
                                        const Duration(milliseconds: 300),
                                        () {
                                          final ctx =
                                              moreSettingsKey.currentContext;
                                          if (ctx != null && ctx.mounted) {
                                            Scrollable.ensureVisible(
                                              ctx,
                                              alignment: 0.0,
                                              duration: const Duration(
                                                milliseconds: 350,
                                              ),
                                              curve: Curves.easeOutCubic,
                                            );
                                          }
                                        },
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.settings_outlined,
                                              color: showMoreSettings.value
                                                  ? AppColors.starGold
                                                  : AppColors
                                                        .universe
                                                        .textComet,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              l10n.recordingSettingsSectionTitle,
                                              style: TextStyle(
                                                color: showMoreSettings.value
                                                    ? AppColors.starGold
                                                    : AppColors
                                                          .universe
                                                          .textComet,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Icon(
                                          showMoreSettings.value
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: showMoreSettings.value
                                              ? AppColors.starGold
                                              : AppColors.universe.textComet,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 250),
                                crossFadeState: showMoreSettings.value
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                firstChild: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF131525,
                                    ).withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.starGold.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      TextField(
                                        controller: titleCtl,
                                        enabled: !isBusy,
                                        style: TextStyle(
                                          color:
                                              AppColors.universe.textStarlight,
                                        ),
                                        decoration: glassInputDecoration(
                                          l10n.recordingTitleFieldLabel,
                                          Icons.title,
                                          hintText:
                                              l10n.recordingTitleFieldHint,
                                        ),
                                        onChanged: controller.setTitle,
                                      ),
                                      const SizedBox(height: 16),
                                      buildToggleRow(
                                        icon: Icons.play_circle_outline,
                                        title: l10n
                                            .recordingAutoStartAnalysisTitle,
                                        subtitle: l10n
                                            .recordingAutoStartAnalysisSubtitle,
                                        value: state.autoStartAnalysis,
                                        onChanged: (val) => controller
                                            .setAutoStartAnalysis(val),
                                      ),
                                      const SizedBox(height: 12),
                                      buildToggleRow(
                                        icon: Icons.chat_bubble_outline,
                                        title: l10n
                                            .recordingRealtimeTranscribeTitle,
                                        subtitle: asrModelErrored
                                            ? l10n.recordingAsrModelErrorPrefix(
                                                friendlyAsrModelErrorMessage,
                                              )
                                            : l10n
                                                  .recordingRealtimeTranscribeSubtitle,
                                        subtitleColor: asrModelErrored
                                            ? AppColors.correctionRed
                                            : null,
                                        titleTrailing: asrModelUpdating
                                            ? SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      value: asrModelState
                                                          .progress,
                                                      color: AppColors
                                                          .universe
                                                          .textComet,
                                                    ),
                                              )
                                            : null,
                                        trailing: buildAsrTrailingAction(
                                          modelState: asrModelState,
                                          locked: realtimeLocked,
                                          onDownloadTap:
                                              confirmAndDownloadAsrModel,
                                          onPauseTap: () => ref
                                              .read(
                                                asrModelManagerProvider
                                                    .notifier,
                                              )
                                              .pauseDownload(
                                                recordingLanguage,
                                              ),
                                          onResumeTap: () =>
                                              resumeAsrModelWithErrorDialog(
                                                context,
                                                ref,
                                                recordingLanguage,
                                              ),
                                        ),
                                        onTileTap: realtimeLocked
                                            ? showRealtimeLockedDialog
                                            : asrModelDownloadable
                                            ? confirmAndDownloadAsrModel
                                            : null,
                                        value: state.realtimeTranscribe,
                                        dimmed: realtimeLocked,
                                        onChanged: (val) async {
                                          if (realtimeLocked) {
                                            await showRealtimeLockedDialog();
                                            return;
                                          }
                                          final result = await controller
                                              .setRealtimeTranscribe(val);
                                          if (!context.mounted) return;
                                          await showRealtimeToggleFailure(
                                            result,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      _RecordingLanguageRow(
                                        languageLabel:
                                            recordingLanguageFromCode(
                                              recordingLanguage,
                                            ).englishName,
                                        onTap: isBusy
                                            ? null
                                            : () => showModalBottomSheet(
                                                context: context,
                                                isScrollControlled: true,
                                                backgroundColor:
                                                    Colors.transparent,
                                                builder: (_) =>
                                                    const LanguageSelectionSheet(
                                                      mode: LanguageSheetMode
                                                          .recording,
                                                    ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                                secondChild: const SizedBox(
                                  width: double.infinity,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 5. Upload Button (Bottom)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.universe.glassBorder),
                      ),
                      color: AppColors.universe.voidBackground.withValues(
                        alpha: 0.8,
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                !isBusy &&
                                        !state.isRecording &&
                                        (state.canUpload ||
                                            selectedAudioFilePath.value != null)
                                    ? () async {
                                    // ファイル選択・録音アップロードのどちらも、
                                    // コース未選択のままでは自動分析が始まらないので
                                    // 先に必ずコースを確定させる。
                                    if (!await ensureCourseSelected()) return;

                                    if (selectedAudioFilePath.value != null) {
                                      // ファイル選択がある場合
                                      await controller.uploadAudioFile(
                                        selectedAudioFilePath.value!,
                                      );
                                      selectedAudioFilePath.value =
                                          null; // 完了後にリセット
                                    } else {
                                      // 通常の録音アップロード
                                      if (state.canUpload) {
                                        await controller.upload();
                                      }
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.starGold,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  AppColors.universe.glassWhiteLow,
                              disabledForegroundColor:
                                  AppColors.universe.textComet,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isBusy
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        l10n.recordingUploadingStatus,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    l10n.recordingUploadButtonLabel,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ==========================================
              // Tab 2: Live (Realtime transcript + reactions/notes)
              // ==========================================
              _LiveTab(state: state, controller: controller),

              // ==========================================
              // (旧) Memo (Manual Entry) - MVPのためコメントアウト、参考として残置
              // ==========================================
              /*
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // 1. Title (Shared)
                          TextField(
                            controller: titleCtl,
                            style: TextStyle(color: AppColors.universe.textStarlight),
                            decoration: glassInputDecoration('Note title', Icons.title),
                            onChanged: controller.setTitle,
                          ),
                          const SizedBox(height: 12),

                          // 2. Course (Shared)
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.universe.glassBorder),
                            ),
                            child: ListTile(
                              leading: Icon(
                                selectedCourse != null ? iconData : Icons.folder_outlined,
                                color: selectedCourse != null ? displayIconColor : AppColors.universe.textComet,
                              ),
                              title: Text('Course', style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
                              subtitle: Text(
                                selectedCourse != null ? selectedCourse.displayTitle : 'No course selected',
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.universe.textStarlight, fontWeight: FontWeight.bold),
                              ),
                              trailing: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              onTap: openCoursePicker,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 3. Large Text Area
                          Container(
                            height: 300,
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.universe.glassBorder),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: memoCtl,
                              maxLines: null, // 無制限
                              expands: true,
                              style: TextStyle(color: AppColors.universe.textStarlight, height: 1.5),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Write your thoughts here...',
                                hintStyle: TextStyle(color: AppColors.universe.textComet),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 4. Save Button (Bottom)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
                      color: AppColors.universe.voidBackground.withValues(alpha:0.8),
                    ),
                    child: ElevatedButton(
                      onPressed: memoCtl.text.trim().isNotEmpty ? () {
                        // TODO: テキスト保存処理の実装
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Memo saved! (Fake)')),
                        );
                        context.pop();
                      } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.starGold, // メモ保存は緑とか？
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Note', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              */

              // ==========================================
              // Tab 3: Test (Tier 1 simulate-recording harness, isTestMode only)
              // ==========================================
              if (isTestMode)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: const SimulateRecordingTab(),
                  ),
                ),
            ],
          ),

          // 完了時のオーバーレイ (Upload完了時など)
          if (isDonePhase)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.growthGreen,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.recordingDoneOverlayTitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusArea extends StatelessWidget {
  const _StatusArea({required this.state, required this.controller});

  final RecordingState state;
  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.phase == RecordingPhase.requestingPermission) {
      return Text(
        l10n.recordingRequestingPermissionStatus,
        style: TextStyle(color: AppColors.universe.textComet),
      );
    }

    if (state.phase == RecordingPhase.uploading) {
      return Column(
        children: [
          const CircularProgressIndicator(color: AppColors.starGold),
          const SizedBox(height: 12),
          Text(
            l10n.recordingUploadingStatus,
            style: TextStyle(color: AppColors.universe.textStarlight),
          ),
        ],
      );
    }

    if (state.phase == RecordingPhase.error) {
      return Column(
        children: [
          Text(
            state.errorMessage ?? l10n.recordingGenericErrorFallback,
            style: const TextStyle(color: AppColors.correctionRed),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: controller.openSettingsIfNeeded,
                child: Text(
                  l10n.recordingOpenSettingsButton,
                  style: const TextStyle(color: AppColors.starGold),
                ),
              ),
              TextButton(
                onPressed: controller.resetAfterError,
                child: Text(
                  l10n.recordingTryAgainButton,
                  style: TextStyle(color: AppColors.universe.textStarlight),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (state.phase == RecordingPhase.paused) {
      return _StatusPill(
        icon: Icons.pause_circle_filled,
        color: AppColors.alertAmber,
        label: l10n.recordingStatusPaused,
      );
    }

    if (state.phase == RecordingPhase.recording) {
      return _StatusPill(
        icon: Icons.fiber_manual_record,
        color: AppColors.correctionRed,
        label: l10n.recordingStatusRecording,
      );
    }

    return Text(
      l10n.recordingStatusReady,
      style: TextStyle(color: AppColors.universe.textComet),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「Recording Language」設定行。タップするとLanguageSelectionSheetが開き、
/// 言語を選べる。以前は言語ごとに別々のASRモデルがあったため、ここに
/// ダウンロード状況を表示していたが、今は全言語共通でWhisperを使うため、
/// モデル状態はRealtime Transcribeタイル側([buildAsrStatusIndicator])に
/// 表示するようになった。
class _RecordingLanguageRow extends StatelessWidget {
  const _RecordingLanguageRow({required this.languageLabel, required this.onTap});

  final String languageLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C2E).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: ListTile(
        tileColor: Colors.transparent,
        onTap: onTap,
        enabled: onTap != null,
        leading: Icon(Icons.translate, color: AppColors.universe.textComet),
        title: Text(
          l10n.recordingLanguageRowTitle,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          l10n.recordingLanguageRowSubtitle,
          maxLines: 3,
          style: TextStyle(color: AppColors.universe.textComet, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              languageLabel,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.universe.textComet,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Live Tab (見た目確認用のハリボテ。永続化・実データ取得は一切無し)
// =============================================================

// リアクション3ボタン用。メモ("note")は自由入力でボタンは無いため、
// 文字列リテラル("note")として直接扱う(_momentDisplay/RecordingController参照)。
enum _MomentType { interesting, difficult, revisit }

String _formatMmSs(int sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// リアクション/メモ種別ごとのアイコン・色・ラベル(ボタンとタイムラインで共有)。
/// `moment_type`はSupabase/ローカルDBどちらもenumやCHECK制約の無いプレーンな
/// text列(将来種類が増える前提)なので、DB由来の値は生Stringで受け取り、
/// 未知の値でも例外を投げず汎用表示にフォールバックする。
(IconData, Color, String) _momentDisplay(
  String momentType,
  AppLocalizations l10n,
) {
  switch (momentType) {
    case 'interesting':
      return (
        Icons.star_rounded,
        AppColors.starGold,
        l10n.recordingMomentFunLabel,
      );
    case 'difficult':
      return (
        Icons.help_rounded,
        AppColors.cosmicBlue,
        l10n.recordingMomentDifficultLabel,
      );
    case 'revisit':
      return (
        Icons.bookmark_rounded,
        AppColors.growthGreen,
        l10n.recordingMomentRevisitLabel,
      );
    case 'note':
      return (
        Icons.edit_note_rounded,
        AppColors.universe.textComet,
        l10n.recordingMomentNoteLabel,
      );
    default:
      return (
        Icons.emoji_objects_rounded,
        AppColors.universe.textComet,
        momentType,
      );
  }
}

class _LiveTab extends HookConsumerWidget {
  const _LiveTab({required this.state, required this.controller});

  final RecordingState state;
  final RecordingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteCtl = useTextEditingController();
    final lectureId = state.currentLectureId;
    // 録音中/一時停止中のみ操作可能。タブ自体はそれ以外のフェーズでも表示する。
    final canInteract =
        state.phase == RecordingPhase.recording ||
        state.phase == RecordingPhase.paused;

    final moments = lectureId != null
        ? (ref.watch(lectureMomentsProvider(lectureId)).value ??
              const <LectureMoment>[])
        : const <LectureMoment>[];

    void addMoment(_MomentType type) {
      controller.addReaction(type.name);
    }

    void submitNote() {
      final text = noteCtl.text.trim();
      if (text.isEmpty) return;
      controller.addNote(text);
      noteCtl.clear();
    }

    void deleteMoment(String id) {
      controller.deleteMoment(id);
    }

    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final listCount = moments.length;
        final timelineHeight = listCount == 0
            ? 20.0
            : (listCount < 4
                  ? listCount * 44.0 + (listCount - 1) * 8.0
                  : 3.5 * 44.0 + 3 * 8.0);

        if (state.realtimeTranscribe) {
          // 下部要素（Padding[Top 20 + Bottom 36] + BottomSafeArea + Timeline + ReactionRow + NoteInputRow + Gaps）の高さ合計
          final bottomFixedArea =
              56.0 +
              bottomSafeArea +
              timelineHeight +
              12.0 +
              64.0 +
              12.0 +
              48.0 +
              12.0;
          final availableTranscriptHeight =
              constraints.maxHeight - bottomFixedArea;
          const minTranscriptHeight = 160.0;
          final transcriptHeight =
              availableTranscriptHeight < minTranscriptHeight
              ? minTranscriptHeight
              : availableTranscriptHeight;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(20, 20, 20, 36 + bottomSafeArea),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    SizedBox(
                      height: transcriptHeight,
                      child: _LiveTranscriptPanel(
                        phase: state.phase,
                        lectureId: lectureId,
                        canInteract: canInteract,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MomentsTimeline(
                      moments: moments,
                      isExpanded: false,
                      canInteract: canInteract,
                      onDelete: deleteMoment,
                    ),
                    const SizedBox(height: 12),
                    _ReactionRow(onTap: addMoment, canInteract: canInteract),
                    const SizedBox(height: 12),
                    _NoteInputRow(
                      controller: noteCtl,
                      onSubmit: submitNote,
                      enabled: canInteract,
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          // Realtime OFF の場合
          final fixedAreaOff =
              56.0 + bottomSafeArea + 52.0 + 12.0 + 64.0 + 12.0 + 48.0 + 12.0;
          final availableTimelineHeight = constraints.maxHeight - fixedAreaOff;
          const minTimelineHeight = 180.0;
          final timelineHeightOff = availableTimelineHeight < minTimelineHeight
              ? minTimelineHeight
              : availableTimelineHeight;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(20, 20, 20, 36 + bottomSafeArea),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    const _RealtimeOffHint(),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: timelineHeightOff,
                      child: _MomentsTimeline(
                        moments: moments,
                        isExpanded: true,
                        canInteract: canInteract,
                        onDelete: deleteMoment,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReactionRow(onTap: addMoment, canInteract: canInteract),
                    const SizedBox(height: 12),
                    _NoteInputRow(
                      controller: noteCtl,
                      onSubmit: submitNote,
                      enabled: canInteract,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      },
    );
  }
}

/// 節電のため端末側の文字起こしを止めていた区間に差し込む案内行。
///
/// 録音そのものは止まっていない(サーバー側には全区間が送られている)ことと、
/// 待てば正式な文字起こしで埋まることを伝えるのが目的。ここで何も出さないと、
/// ユーザーには「その時間だけ録れていなかった」ようにしか見えない。
class _SkippedGapNotice extends StatelessWidget {
  const _SkippedGapNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.battery_saver_rounded,
            size: 14,
            color: AppColors.universe.textComet,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.recordingLiveSkippedGapNotice,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Liveタブのテキスト行の色/字体を、出どころに応じて3段階で分ける:
///
/// 1. サーバー確定稿(最終的な正解) — 一番明るい[textStarlight]、通常体
/// 2. オンデバイス確定(まだサーバーに追い越されていない下書き) — 少し灰色の
///    [textComet]、通常体。「確定はしているが、まだ本物ではない」ことを示す
/// 3. オンデバイス暫定(endpoint検知前) — 2よりさらに薄い[textComet]、斜体
///
/// サーバー確定とオンデバイス確定は以前どちらも同じ色で描かれており、
/// 画面をスクロールして戻った時にどこからがサーバー版の「本当の文字起こし」
/// なのか判別できなかった。
TextStyle _liveTranscriptTextStyle({required bool isFinal, required bool isOnDevice}) {
  if (!isFinal) {
    return TextStyle(
      color: AppColors.universe.textComet.withValues(alpha: 0.65),
      fontStyle: FontStyle.italic,
      fontSize: 14,
      height: 1.4,
    );
  }
  return TextStyle(
    color: isOnDevice ? AppColors.universe.textComet : AppColors.universe.textStarlight,
    fontStyle: FontStyle.normal,
    fontSize: 14,
    height: 1.4,
  );
}

class _RecordingStatusBadge extends StatelessWidget {
  const _RecordingStatusBadge({required this.phase});

  final RecordingPhase phase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    IconData icon;
    Color color;
    String label;
    switch (phase) {
      case RecordingPhase.recording:
        icon = Icons.fiber_manual_record;
        color = AppColors.correctionRed;
        label = l10n.recordingStatusRecording;
      case RecordingPhase.paused:
        icon = Icons.pause_circle_filled;
        color = AppColors.alertAmber;
        label = l10n.recordingStatusPaused;
      default:
        return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _LiveTranscriptPanel extends HookConsumerWidget {
  const _LiveTranscriptPanel({
    required this.phase,
    required this.lectureId,
    required this.canInteract,
  });

  final RecordingPhase phase;
  final String? lectureId;
  final bool canInteract;

  static const double _bottomThresholdPx = 24;

  /// これより短い省略区間には案内を出さない。[kAsrLivePreBufferSeconds]と
  /// 同じ値にすること — ワーカー側がその秒数だけ音声をリングバッファで
  /// 救っているため、これ未満の区間は「案内を省いている」のではなく
  /// 「本当に何も欠けていない」。しきい値をこれより大きくすると、実際には
  /// 音声が欠けているのに案内が出ない区間ができてしまう。
  static const double _minGapNoticeSec = kAsrLivePreBufferSeconds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scrollController = useScrollController();
    final isFollowing = useState(true);

    final lectureId = this.lectureId;
    final snapshot = lectureId != null
        ? ref.watch(liveTranscriptProvider(lectureId)).value
        : null;
    final sentences = snapshot?.sentences ?? const <LiveTranscriptSentence>[];

    // サーバー版(lecture_transcripts)とオンデバイス版(LiveAsrController)を
    // 時刻順に連結する。サーバー版は常に確定済みなのでisFinal:true固定。
    //
    // サーバー版が既に文字起こし済みの区間をオンデバイス版が二重に表示
    // しないよう、サーバー側が実際に文字起こしを終えている範囲の終端
    // (coverageEndSec、chunkのstart_time + audio_durationから算出、
    // 無音チャンクも含む)より前のオンデバイスセグメントは表示から除外する。
    // サーバー版はいずれその区間を追い越して確定させるので、それより前の
    // オンデバイス分は「もう不要な下書き」として捨ててよい。
    //
    // ★ 以前は「サーバー側の文の開始時刻の最大値」をwatermarkとして
    // 使っていたが、これだと最後の文の"開始"より後ろ(=その文がカバーして
    // いる区間)がまだ未カバー扱いになってしまい、節電ラベルが本物の
    // テキストの間に挟まって残る不具合があった。
    final serverWatermark = snapshot?.coverageEndSec;
    final onDeviceSegments = ref.watch(liveAsrControllerProvider);
    final visibleOnDeviceSegments = serverWatermark == null
        ? onDeviceSegments
        : onDeviceSegments
              .where((s) => s.timestampSec >= serverWatermark)
              .toList();
    // 節電のため端末側の文字起こしを止めていた区間。サーバー側が既に
    // 追い越した(watermarkより手前で閉じている)区間は、もうテキストが
    // 埋まっているのでプレースホルダを出す必要がない。
    // 短すぎる区間(タブを一瞬だけ切り替えた等)もノイズになるので出さない。
    final skippedGaps = ref
        .watch(liveAsrStatusProvider.select((s) => s.gaps))
        .where((gap) {
          final end = gap.endSec;
          if (end != null && end - gap.startSec < _minGapNoticeSec) return false;
          if (serverWatermark == null) return true;
          return end == null || end > serverWatermark;
        })
        .toList();

    final combined =
        <({double timeSec, String text, bool isFinal, bool isGap, bool isOnDevice})>[
          for (final s in sentences)
            (
              timeSec: s.startSec,
              text: s.text,
              isFinal: true,
              isGap: false,
              isOnDevice: false,
            ),
          for (final s in visibleOnDeviceSegments)
            (
              timeSec: s.timestampSec,
              text: s.text,
              isFinal: s.isFinal,
              isGap: false,
              isOnDevice: true,
            ),
          for (final gap in skippedGaps)
            (
              timeSec: gap.startSec,
              text: '',
              isFinal: true,
              isGap: true,
              isOnDevice: false,
            ),
        ]..sort((a, b) => a.timeSec.compareTo(b.timeSec));

    void scrollToBottom() {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }

    // 新しい文が届いた時、追従中(isFollowing)なら自動で最下部までスクロールする。
    useEffect(() {
      if (!isFollowing.value || combined.isEmpty) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToBottom());
      return null;
    }, [combined.length]);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.podcasts_rounded,
                  size: 16,
                  color: AppColors.starGold,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.recordingLiveTranscriptHeader,
                  style: TextStyle(
                    color: AppColors.starGold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                _RecordingStatusBadge(phase: phase),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.universe.glassBorder),
          // 文字起こしは数秒に一度しか増えないため、その間も動き続ける
          // 「聞こえてるよ」の手がかりをテキストの上に常時出す。
          if (phase == RecordingPhase.recording ||
              phase == RecordingPhase.paused) ...[
            LiveListeningIndicator(phase: phase),
            Divider(height: 1, color: AppColors.universe.glassBorder),
          ],
          Expanded(
            child: Stack(
              children: [
                combined.isEmpty
                    ? Center(
                        child: Text(
                          l10n.recordingWaitingForAudio,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification &&
                              notification.dragDetails != null) {
                            // ユーザー自身の指によるドラッグ(プログラム的スクロールは除外)
                            isFollowing.value = false;
                          } else if (notification is ScrollEndNotification) {
                            final metrics = notification.metrics;
                            if (metrics.pixels >=
                                metrics.maxScrollExtent - _bottomThresholdPx) {
                              isFollowing.value = true;
                            }
                          }
                          return false;
                        },
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: combined.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, i) {
                            final row = combined[i];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatMmSs(row.timeSec.round()),
                                  style: TextStyle(
                                    color: AppColors.universe.textComet,
                                    fontSize: 11,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: row.isGap
                                      ? _SkippedGapNotice()
                                      : Text(
                                          row.text,
                                          style: _liveTranscriptTextStyle(
                                            isFinal: row.isFinal,
                                            isOnDevice: row.isOnDevice,
                                          ),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                if (!isFollowing.value && combined.isNotEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      color: AppColors.starGold,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          scrollToBottom();
                          isFollowing.value = true;
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // AIチャットはApple審査対応のため一時的に非表示(Coming Soon的な
          // 未完成機能を見せないため)。再度有効化する際はこのブロックと
          // 冒頭の ai_chat_sheet.dart のimportのコメントアウトを外すこと。
          /*
          Divider(height: 1, color: AppColors.universe.glassBorder),
          Opacity(
            opacity: canInteract ? 1.0 : 0.4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: AppColors.universe.voidBackground.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: canInteract ? () => showAiChatSheet(context) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.universe.glassBorder),
                          ),
                          child: Text(
                            'Ask AI about this lecture...',
                            style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.starGold,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canInteract ? () => showAiChatSheet(context) : null,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          */
        ],
      ),
    );
  }
}

class _RealtimeOffHint extends StatelessWidget {
  const _RealtimeOffHint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.universe.textComet,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.recordingRealtimeOffHint,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.onTap, required this.canInteract});

  final void Function(_MomentType type) onTap;
  final bool canInteract;

  static const _options = <_MomentType>[
    _MomentType.interesting,
    _MomentType.difficult,
    _MomentType.revisit,
  ];

  Widget _button(_MomentType type, AppLocalizations l10n) {
    final (icon, color, _) = _momentDisplay(type.name, l10n);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Opacity(
          opacity: canInteract ? 1.0 : 0.4,
          child: Material(
            color: AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: canInteract ? () => onTap(type) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.universe.glassBorder),
                ),
                child: Column(
                  children: [
                    Icon(icon, size: 22, color: color),
                    const SizedBox(height: 4),
                    Text(
                      type.label(l10n),
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(children: [for (final type in _options) _button(type, l10n)]);
  }
}

extension on _MomentType {
  String label(AppLocalizations l10n) => switch (this) {
    _MomentType.interesting => l10n.recordingReactionFunLabel,
    _MomentType.difficult => l10n.recordingReactionDifficultLabel,
    _MomentType.revisit => l10n.recordingReactionRevisitLabel,
  };
}

class _NoteInputRow extends StatelessWidget {
  const _NoteInputRow({
    required this.controller,
    required this.onSubmit,
    required this.enabled,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            style: TextStyle(color: AppColors.universe.textStarlight),
            decoration: InputDecoration(
              hintText: l10n.recordingNoteInputHint,
              hintStyle: TextStyle(color: AppColors.universe.textComet),
              filled: true,
              fillColor: AppColors.universe.glassWhiteLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.universe.glassBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.starGold),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: enabled ? onSubmit : null,
          icon: const Icon(Icons.send_rounded),
          color: AppColors.starGold,
        ),
      ],
    );
  }
}

class _MomentsTimeline extends StatelessWidget {
  const _MomentsTimeline({
    required this.moments,
    required this.canInteract,
    required this.onDelete,
    this.isExpanded = false,
  });

  final List<LectureMoment> moments;
  final bool canInteract;
  final void Function(String id) onDelete;
  final bool isExpanded;

  static const double _tileHeight = 44;
  static const double _tileGap = 8;
  static const double _maxVisibleTiles = 3.5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (moments.isEmpty) {
      final hintWidget = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          l10n.recordingMomentsEmptyHint,
          style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
        ),
      );
      if (isExpanded) {
        return Center(child: hintWidget);
      }
      return hintWidget;
    }

    final reversed = moments.reversed.toList();
    final listView = ListView.separated(
      physics: const ClampingScrollPhysics(),
      itemCount: reversed.length,
      separatorBuilder: (_, _) => const SizedBox(height: _tileGap),
      itemBuilder: (context, i) {
        final moment = reversed[i];
        final (icon, color, label) = _momentDisplay(moment.momentType, l10n);
        return Container(
          height: _tileHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.universe.glassBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Text(
                _formatMmSs(moment.timestampSec),
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  moment.noteText ?? label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 13,
                  ),
                ),
              ),
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  color: AppColors.universe.textComet,
                  onPressed: canInteract ? () => onDelete(moment.id) : null,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (isExpanded) {
      return listView;
    }

    final count = reversed.length;
    final double height;
    if (count < 4) {
      height = count * _tileHeight + (count - 1) * _tileGap;
    } else {
      height = _maxVisibleTiles * _tileHeight + 3 * _tileGap;
    }

    return SizedBox(height: height, child: listView);
  }
}

// =============================================================
// Mic Button (録音中は脈動するリング、常時ほんのりグロー)
// =============================================================

class _MicButton extends HookWidget {
  const _MicButton({
    required this.state,
    required this.controller,
    required this.isBusy,
  });

  final RecordingState state;
  final RecordingController controller;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final isRecording = state.isRecording;
    final pulse = useAnimationController(
      duration: const Duration(milliseconds: 1600),
    );

    useEffect(() {
      if (isRecording) {
        pulse.repeat();
      } else {
        pulse.stop();
        pulse.value = 0;
      }
      return null;
    }, [isRecording]);

    final canTap =
        !isBusy &&
        (state.phase == RecordingPhase.idle ||
            state.phase == RecordingPhase.recording ||
            state.phase == RecordingPhase.paused);

    final accentColor = isRecording
        ? AppColors.correctionRed
        : AppColors.starGold;

    return GestureDetector(
      onTap: canTap ? () => controller.toggleStartStopResume() : null,
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording)
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t = pulse.value;
                  return Container(
                    width: 140 + t * 60,
                    height: 140 + t * 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.correctionRed.withValues(
                          alpha: (1 - t) * 0.5,
                        ),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.22),
                    accentColor.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(color: accentColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(
                      alpha: isRecording ? 0.45 : 0.25,
                    ),
                    blurRadius: isRecording ? 30 : 18,
                    spreadRadius: isRecording ? 4 : 1,
                  ),
                ],
              ),
              child: Icon(
                isRecording
                    ? Icons.stop_rounded
                    : (state.phase == RecordingPhase.paused
                          ? Icons.fiber_manual_record
                          : Icons.mic),
                size: 64,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// テスト専用: 保存直後のエンコードに意図的な遅延を挟むトグル。
/// [AudioRecorderService.debugEncodeDelayForTesting]参照。
/// isTestModeでのみビルドに含まれ、本番ではtree-shakingで消える。
class _DebugSlowEncodeToggle extends StatefulWidget {
  const _DebugSlowEncodeToggle();

  @override
  State<_DebugSlowEncodeToggle> createState() => _DebugSlowEncodeToggleState();
}

class _DebugSlowEncodeToggleState extends State<_DebugSlowEncodeToggle> {
  static const _delay = Duration(seconds: 20);

  bool get _enabled => AudioRecorderService.debugEncodeDelayForTesting != null;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _enabled
          ? 'Slow encode ON (+${_delay.inSeconds}s) — tap to disable'
          : 'Simulate slow encode (+${_delay.inSeconds}s)',
      icon: Icon(
        Icons.hourglass_bottom,
        color: _enabled ? AppColors.starGold : Colors.white54,
      ),
      onPressed: () {
        setState(() {
          AudioRecorderService.debugEncodeDelayForTesting =
              _enabled ? null : _delay;
        });
      },
    );
  }
}
