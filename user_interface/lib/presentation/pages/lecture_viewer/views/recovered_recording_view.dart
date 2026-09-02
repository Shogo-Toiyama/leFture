// lib/presentation/pages/lecture_viewer/views/recovered_recording_view.dart
//
// 「録音を止め忘れた/アプリがキルされた/クラッシュした」場合に端末へ
// 取り残された録音(Recording Recovery)を、ユーザーが確認してから
// 分析開始/削除を選べるようにするカード。LectureOverlayCardが
// (orphanRecordingsProviderにこの講義が含まれている場合)NotStartedViewの
// 代わりにこれを表示する。
//
// 表示の優先順位は「不安の解消」: まず「録音は無事です」をはっきり出し、
// 次にいつ録られたものかを示し、実際に聴いて確認できるようにしてから
// アクションを選ばせる。

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/lecture_moments_provider.dart';
import 'package:lefture/application/recording/live_transcript_provider.dart';
import 'package:lefture/application/recording/recovery/recovery_models.dart';
import 'package:lefture/application/recording/recovery/recovery_providers.dart';
import 'package:lefture/core/utils/moment_display_utils.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/domain/entities/lecture_moment.dart';
import 'package:lefture/domain/entities/live_transcript_sentence.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lefture/presentation/widgets/orphan_delete_confirm.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/audio_player_bar.dart';
import 'package:lefture/presentation/widgets/playback_speed_menu.dart';

class RecoveredRecordingView extends HookConsumerWidget {
  const RecoveredRecordingView({super.key, required this.orphan});

  final OrphanRecording orphan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final displayLanguageCode = ref.watch(displayLanguageControllerProvider);

    final lecture = ref.watch(recoveryLectureProvider(orphan.lectureId)).value;
    final encodeState =
        ref.watch(recoveryEncodeStateProvider(orphan.lectureId)).value ?? RecoveryEncodeState.initial;

    final momentsAsync = ref.watch(lectureMomentsProvider(orphan.lectureId));
    final moments = momentsAsync.value ?? const <LectureMoment>[];
    final liveTranscriptAsync = ref.watch(liveTranscriptProvider(orphan.lectureId));
    final sentences = liveTranscriptAsync.value?.sentences ?? const [];

    final player = useMemoized(() => AudioPlayer());
    final position = useState(Duration.zero);
    final duration = useState(orphan.duration);
    final playerState = useState(PlayerState.stopped);
    final playbackSpeed = useState(1.0);

    final isConfirming = useState(false);
    final isUploadingOnly = useState(false);
    final isDeleting = useState(false);

    // エンコードが完了した瞬間にm4aを読み込む。
    useEffect(() {
      if (encodeState.status == RecoveryEncodeStatus.ready) {
        player
            .setReleaseMode(ReleaseMode.stop)
            .then((_) => player.setSource(DeviceFileSource(orphan.m4aPath)));
      }
      return null;
    }, [encodeState.status]);

    useEffect(() {
      final dSub = player.onDurationChanged.listen((d) {
        if (d > Duration.zero) duration.value = d;
      });
      final pSub = player.onPositionChanged.listen((p) => position.value = p);
      final sSub = player.onPlayerStateChanged.listen((s) {
        playerState.value = s;
        if (s == PlayerState.completed) {
          player.stop();
          position.value = Duration.zero;
        }
      });
      return () {
        dSub.cancel();
        pSub.cancel();
        sSub.cancel();
        player.dispose();
      };
    }, [player]);

    Future<void> confirmAnalysis() async {
      // ★ このlectureId自身に対して操作するため、成功後の
      // orphanRecordingsProvider.refresh()がこの講義を一覧から除外し、
      // LectureOverlayCardがこのWidgetをNotStartedViewへ差し替える(=この
      // Widgetが破棄される)ことがある。破棄後もref経由の操作は行わずに
      // 済むよう、必要なオブジェクトの参照は破壊的操作の前に確保しておく。
      final service = ref.read(recordingRecoveryServiceProvider);
      final orphanNotifier = ref.read(orphanRecordingsProvider.notifier);

      isConfirming.value = true;
      try {
        await service.confirmAnalysis(orphan.lectureId);
        await orphanNotifier.refresh();
        if (context.mounted) isConfirming.value = false;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.notStartedErrorPrefix(e.toString()))));
          isConfirming.value = false;
        }
      }
    }

    Future<void> uploadOnly() async {
      // ★ confirmAnalysis()と同じ理由(orphanRecordingsProvider.refresh()で
      // このWidgetが破棄されうる)で、破壊的操作の前にオブジェクト参照を確保する。
      final service = ref.read(recordingRecoveryServiceProvider);
      final orphanNotifier = ref.read(orphanRecordingsProvider.notifier);

      isUploadingOnly.value = true;
      try {
        await service.uploadOnly(orphan.lectureId);
        await orphanNotifier.refresh();
        if (context.mounted) isUploadingOnly.value = false;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.notStartedErrorPrefix(e.toString()))));
          isUploadingOnly.value = false;
        }
      }
    }

    Future<void> delete() async {
      final confirmed = await confirmOrphanHardDelete(context);
      if (!confirmed) return;

      // ★ discard()はこの画面が今まさに表示している講義を削除するため、
      // 削除完了と同時にLectureViewerPage側のlectureProvider(lectureId)が
      // nullを検知し、このWidgetごと「Lecture not found」画面に差し替えて
      // しまう(=破棄される)。破棄された後にcontext.pop()やref.read()を
      // 呼ぶと例外になり、しかもその例外がcatch節でも同じ理由で握りつぶされる
      // ため、「Homeのバナーが更新されないまま・遷移もされないまま固まる」
      // バグになっていた。破棄されても使い続けられるオブジェクト
      // (service/notifier/router)を先に確保し、以降はcontext/refを経由しない。
      final service = ref.read(recordingRecoveryServiceProvider);
      final orphanNotifier = ref.read(orphanRecordingsProvider.notifier);
      // 確認ダイアログの直後(=まだ確実にmounted)で同期的に取得するので安全。
      // 取得したGoRouterインスタンス自体はこのWidgetの生死と無関係に使える
      // ため、後続のawaitを跨いでも問題ない。
      // ignore: use_build_context_synchronously
      final router = GoRouter.of(context);

      isDeleting.value = true;
      try {
        await service.discard(orphan.lectureId);
        await orphanNotifier.refresh();
        router.go(AppRoutes.home);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.notStartedErrorPrefix(e.toString()))));
          isDeleting.value = false;
        }
      }
    }

    Widget buildAudioSection() {
      switch (encodeState.status) {
        case RecoveryEncodeStatus.pending:
        case RecoveryEncodeStatus.encoding:
          final percent = ((encodeState.progress ?? 0.0) * 100).round().clamp(0, 100);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.recoveryEncodingLabel(percent),
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: encodeState.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.universe.glassWhiteLow,
                  color: AppColors.starGold,
                ),
              ),
            ],
          );
        case RecoveryEncodeStatus.failed:
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.correctionRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.recoveryEncodingFailedTitle,
                  style: const TextStyle(color: AppColors.correctionRed, fontWeight: FontWeight.w600),
                ),
                if (encodeState.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    encodeState.errorMessage!,
                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 11.5),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      ref.read(recordingRecoveryServiceProvider).ensureEncoded(orphan);
                    },
                    child: Text(l10n.recoveryEncodingFailedRetryButton),
                  ),
                ),
              ],
            ),
          );
        case RecoveryEncodeStatus.ready:
          return _CompactAudioPlayer(
            position: position.value,
            duration: duration.value,
            isPlaying: playerState.value == PlayerState.playing,
            playbackSpeed: playbackSpeed.value,
            moments: moments,
            onPlayPause: () async {
              if (playerState.value == PlayerState.playing) {
                await player.pause();
              } else {
                await player.resume();
              }
            },
            onSeek: (value) async {
              position.value = value;
              await player.seek(value);
            },
            onRewind10: () async {
              final target = position.value - const Duration(seconds: 10);
              final actualTarget = target < Duration.zero ? Duration.zero : target;
              position.value = actualTarget;
              await player.seek(actualTarget);
            },
            onForward10: () async {
              final target = position.value + const Duration(seconds: 10);
              final actualTarget = target > duration.value ? duration.value : target;
              position.value = actualTarget;
              await player.seek(actualTarget);
            },
            onSpeedSelected: (speed) async {
              playbackSpeed.value = speed;
              await player.setPlaybackRate(speed);
            },
          );
      }
    }

    final startedAtText = lecture?.lectureDatetime != null
        ? DateFormat.yMMMEd(displayLanguageCode).add_Hm().format(lecture!.lectureDatetime!.toLocal())
        : null;
    final isRealtime = lecture?.isRealtime == true;
    final languageLabel = lecture == null
        ? null
        : recordingLanguageFromCode(
            lecture.recordingLanguage ?? kAutoDetectLanguageCode,
          ).getNativeName(displayLanguageCode);
    final manualTitle = lecture?.title?.trim();
    // 3つのアクション(削除/アップロードのみ/分析開始)は互いに排他 — どれか
    // 実行中は他を押せないようにする。
    final anyActionInProgress = isConfirming.value || isUploadingOnly.value || isDeleting.value;
    final canConfirm = encodeState.status == RecoveryEncodeStatus.ready && !anyActionInProgress;
    final canUploadOnly = encodeState.status == RecoveryEncodeStatus.ready && !anyActionInProgress;

    final showDetails = useState(false);
    final displayTitle = (manualTitle != null && manualTitle.isNotEmpty)
        ? manualTitle
        : l10n.lectureViewerUntitledLecture;

    // タイトル/コースの編集。LectureEditSheetはdomain層のLecture(courseListとの
    // 突き合わせなどに必要)を要求するため、Drift行(recoveryLectureProvider)とは
    // 別にlectureProviderも見る — こちらもローカルDB由来なので、まだ
    // Supabaseに一度も同期していない孤児講義でも問題なく動く。
    final domainLecture = ref.watch(lectureProvider(orphan.lectureId)).value;

    // 編集シートでコースを選べても、実際どこに所属しているかがカード上で
    // 見えなかったため、常時表示エリアに出す(以前あった開始日時はアコー
    // ディオン側へ移動)。
    final courses = ref.watch(courseListProvider).value ?? const [];
    final assignedCourseId = domainLecture?.courseId;
    final assignedCourse = courses.where((c) => c.id == assignedCourseId).firstOrNull;
    final courseTitleText = assignedCourseId == null
        ? l10n.lectureEditSheetNoCourseLabel
        // courseListがまだロード中でこの回だけ見つからない場合、「コース未設定」
        // と誤解させないよう、その時だけタイトル自体を一旦空にしておく
        // (次のビルドでcourseListが届けば正しい名前に置き換わる)。
        : assignedCourse?.courseTitle;
    final courseColor = assignedCourse != null
        ? CourseStyleHelper.hexToColor(assignedCourse.color, fallback: AppColors.universe.textComet)
        : AppColors.universe.textComet;

    Future<void> editLecture() async {
      if (domainLecture == null) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LectureEditSheet(lecture: domainLecture),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.universe.voidBackground.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 10)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.growthGreen.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: AppColors.growthGreen, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.recoverySafeTitle,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.recoverySafeSubtitle,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.4),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Color(0x22FFFFFF),
                ),
              ),

              // コース & タイトルの常時表示
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (courseTitleText != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 13,
                          color: courseColor,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            courseTitleText,
                            style: TextStyle(
                              color: courseColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (domainLecture != null)
                        IconButton(
                          onPressed: editLecture,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: AppColors.universe.textComet,
                          tooltip: l10n.recoveryEditTooltip,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // 「詳細を見る」アコーディオン
              InkWell(
                onTap: () => showDetails.value = !showDetails.value,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        showDetails.value
                            ? l10n.recoveryHideDetails
                            : l10n.recoveryViewDetails,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        showDetails.value
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.universe.textComet,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.universe.glassWhiteLow.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.universe.glassBorder),
                    ),
                    child: Column(
                      children: [
                        if (startedAtText != null) ...[
                          _DetailRow(
                            icon: Icons.schedule,
                            label: l10n.recoveryDetailStartedAt,
                            value: startedAtText,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Color(0x22FFFFFF),
                            ),
                          ),
                        ],
                        _DetailRow(
                          icon: Icons.timer_outlined,
                          label: l10n.recoveryDetailDuration,
                          value: AudioPlayerBar.formatDuration(duration.value),
                        ),
                        if (languageLabel != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Color(0x22FFFFFF),
                            ),
                          ),
                          _DetailRow(
                            icon: Icons.translate,
                            label: l10n.recoveryDetailLanguage,
                            value: languageLabel,
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Color(0x22FFFFFF),
                          ),
                        ),
                        _DetailRow(
                          icon: isRealtime ? Icons.podcasts : Icons.podcasts_outlined,
                          label: l10n.recoveryDetailRealtime,
                          value: isRealtime
                              ? l10n.recoveryStatusOn
                              : l10n.recoveryStatusOff,
                        ),
                      ],
                    ),
                  ),
                ),
                crossFadeState: showDetails.value
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
              const SizedBox(height: 20),

              buildAudioSection(),

              if (sentences.isNotEmpty || moments.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  sentences.isNotEmpty
                      ? l10n.recoveryTranscriptSectionTitle
                      : l10n.recoveryMomentsSectionTitle,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _PartialTranscriptAndMoments(
                  sentences: sentences,
                  moments: moments,
                  onSeek: (target) async {
                    position.value = target;
                    await player.seek(target);
                  },
                ),
              ],

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: anyActionInProgress ? null : delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.correctionRed,
                        side: BorderSide(color: AppColors.correctionRed.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: isDeleting.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.correctionRed),
                            )
                          : Text(l10n.recoveryDeleteButton),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: canUploadOnly ? uploadOnly : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.universe.textStarlight,
                        side: BorderSide(color: AppColors.universe.glassBorder),
                        disabledForegroundColor: AppColors.universe.textComet.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: isUploadingOnly.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(l10n.recoveryUploadOnlyButton),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canConfirm ? confirmAnalysis : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.starGold,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                    disabledForegroundColor: AppColors.universe.textComet,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: isConfirming.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(l10n.recoveryStartAnalysisButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.universe.textComet),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: AppColors.universe.textComet,
            fontSize: 12.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 復旧カード専用の軽量プレイヤー。
/// 左右対称レイアウト、モーメントマーカー対応、FittedBoxによる極小画面保護。
class _CompactAudioPlayer extends StatelessWidget {
  const _CompactAudioPlayer({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onRewind10,
    required this.onForward10,
    required this.onSpeedSelected,
    this.moments,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double playbackSpeed;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRewind10;
  final VoidCallback onForward10;
  final ValueChanged<double> onSpeedSelected;
  final List<LectureMoment>? moments;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── プログレスバー (全幅 & モーメントマーカー対応) ─────────────
          CustomAudioProgressBar(
            position: position,
            duration: duration,
            onSeek: onSeek,
            moments: moments,
            activeColor: AppColors.starGold,
            inactiveColor: AppColors.universe.glassWhiteLow,
          ),

          const SizedBox(height: 2),

          // ── 時間情報 (左右両端) ───────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AudioPlayerBar.formatDuration(position),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  AudioPlayerBar.formatDuration(duration),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── コントロール群 (FittedBox で極小画面でも Overflow を完全防止) ──
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 左端: 再生速度ドロップダウン
                PlaybackSpeedMenu(
                  speed: playbackSpeed,
                  onSpeedSelected: onSpeedSelected,
                  isDark: true,
                ),
                const SizedBox(width: 14),

                // 中央: 10秒戻る ＆ 再生/一時停止 ＆ 10秒進む
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.replay_10_outlined,
                        color: AppColors.starGold,
                        size: 25,
                      ),
                      onPressed: onRewind10,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onPlayPause,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppColors.starGold,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(
                        Icons.forward_10_outlined,
                        color: AppColors.starGold,
                        size: 25,
                      ),
                      onPressed: onForward10,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // 右端: 左右対称バランス用の48pxスペーサー
                const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.timestampMs,
    this.sentence,
    this.moment,
  });

  final int timestampMs;
  final LiveTranscriptSentence? sentence;
  final LectureMoment? moment;
}

/// 復旧された文字起こしテキストと授業モーメントを時系列順にタイムスタンプ付きで統合表示するウィジェット。
class _PartialTranscriptAndMoments extends StatelessWidget {
  const _PartialTranscriptAndMoments({
    required this.sentences,
    required this.moments,
    required this.onSeek,
  });

  final List<LiveTranscriptSentence> sentences;
  final List<LectureMoment> moments;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final List<_TimelineEntry> entries = [];

    for (final s in sentences) {
      entries.add(_TimelineEntry(
        timestampMs: (s.startSec * 1000).round(),
        sentence: s,
      ));
    }

    for (final m in moments) {
      entries.add(_TimelineEntry(
        timestampMs: m.timestampSec * 1000,
        moment: m,
      ));
    }

    entries.sort((a, b) {
      final comp = a.timestampMs.compareTo(b.timestampMs);
      if (comp != 0) return comp;
      if (a.sentence != null && b.moment != null) return -1;
      if (a.moment != null && b.sentence != null) return 1;
      return 0;
    });

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];

          // ── モーメント行の描画 ──
          if (entry.moment != null) {
            final m = entry.moment!;
            final (icon, color, label) = MomentDisplayUtils.getMomentDisplay(m.momentType);
            final isNoteWithText = m.momentType == 'note' &&
                m.noteText != null &&
                m.noteText!.trim().isNotEmpty;
            final timeStr = AudioPlayerBar.formatDuration(Duration(seconds: m.timestampSec));

            return InkWell(
              onTap: () => onSeek(Duration(seconds: m.timestampSec)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: isNoteWithText
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, size: 16, color: color),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      m.noteText!,
                                      style: TextStyle(
                                        color: AppColors.universe.textStarlight,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: color.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 14, color: color),
                                    const SizedBox(width: 5),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── 字幕行の描画 ──
          final s = entry.sentence!;
          final sentenceMs = (s.startSec * 1000).round();
          final timeStr = AudioPlayerBar.formatDuration(Duration(milliseconds: sentenceMs));

          return InkWell(
            onTap: () => onSeek(Duration(milliseconds: sentenceMs)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.text,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
