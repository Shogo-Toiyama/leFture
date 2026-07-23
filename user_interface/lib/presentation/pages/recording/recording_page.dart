// import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart'; // 色追加
// AIチャットはApple審査対応のため一時的に非表示。再有効化時にコメントアウトを外す。
// import 'package:lecture_companion_ui/presentation/widgets/ai_chat_sheet.dart';
import 'package:lecture_companion_ui/application/recording/lecture_moments_provider.dart';
import 'package:lecture_companion_ui/application/recording/live_transcript_provider.dart';
import 'package:lecture_companion_ui/application/asr/live_asr_controller.dart';
import 'package:lecture_companion_ui/application/recording/recording_language_controller.dart';
import 'package:lecture_companion_ui/application/asr/asr_model_manager.dart';
import 'package:lecture_companion_ui/core/services/recording_preferences.dart';
import 'package:lecture_companion_ui/domain/entities/app_language.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_moment.dart';
import 'package:lecture_companion_ui/domain/entities/live_transcript_sentence.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lecture_companion_ui/presentation/widgets/asr_model_dialog_helpers.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';
import '../dev_tools/simulate_recording_tab.dart';
import '../dev_tools/test_mode_flag.dart';
import 'widgets/course_picker_sheet.dart';

class RecordingPage extends HookConsumerWidget {
  const RecordingPage({super.key, this.initialTab, this.initialCourseId});
  
  // URLパラメータなどでタブ指定を受け取れるように拡張
  final String? initialTab;
  final String? initialCourseId;

  String _format(int sec) {
    final h = (sec ~/ 3600).toString();
    final m = ((sec ~/ 60) % 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // タブコントローラー (Voice / Live、isTestModeの時だけTestタブが加わる)
    final tabController = useTabController(initialLength: isTestMode ? 3 : 2);
    // MVPのためコメントアウト
    // final memoCtl = useTextEditingController();
    // useListenable(memoCtl);
    final showMoreSettings = useState(false);
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
          ref.read(recordingControllerProvider.notifier).setCourseId(initialCourseId);
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
        ref.read(recordingControllerProvider.notifier).requestMicPermissionEarly();
        if (RecordingPreferences().getRealtimeTranscribe()) {
          final lang = ref.read(recordingLanguageControllerProvider);
          final modelManager = ref.read(asrModelManagerProvider.notifier);
          await modelManager.ensureModelReady(lang);
          // この言語に対応するモデルが結局用意できなかった場合、Realtime
          // Transcribeが「On」のまま実体の無い機能として残ってしまう
          // (裏でモデルが動いていると誤解する原因にもなる)ため、ここで
          // 自動的にOffへ戻す。
          if (modelManager.statusForLanguage(lang).status == AsrModelStatus.failed) {
            await ref.read(recordingControllerProvider.notifier).setRealtimeTranscribe(false);
          }
        }
      });
      return null;
    }, []);

    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);

    final recordingLanguage = ref.watch(recordingLanguageControllerProvider);
    ref.watch(asrModelManagerProvider);
    final asrModelState =
        ref.read(asrModelManagerProvider.notifier).statusForLanguage(recordingLanguage);

    final coursesAsync = ref.watch(courseListProvider);
    final courses = coursesAsync.asData?.value ?? const [];
    final selectedCourse = state.courseId != null
        ? courses.any((c) => c.id == state.courseId)
            ? courses.firstWhere((c) => c.id == state.courseId)
            : null
        : null;

    final courseColor = selectedCourse != null
        ? CourseStyleHelper.hexToColor(selectedCourse.color, fallback: AppColors.starGold)
        : AppColors.starGold;
    final HSLColor hsl = HSLColor.fromColor(courseColor);
    final displayIconColor = hsl.lightness < 0.45 ? hsl.withLightness(0.55).toColor() : courseColor;
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

    final titleCtl = useTextEditingController(text: state.title);
    // タイトル同期
    useEffect(() {
      if (titleCtl.text != state.title) {
        titleCtl.text = state.title;
        // カーソル位置を維持しようとすると厄介なので、入力中は同期しない等の工夫も必要だが
        // ここでは単純に末尾へ移動
        titleCtl.selection = TextSelection.collapsed(offset: titleCtl.text.length);
      }
      return null;
    }, [state.title]);

    // 共通スタイル定義
    InputDecoration glassInputDecoration(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
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

    Widget buildToggleRow({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: SwitchListTile(
          secondary: Icon(icon, color: AppColors.universe.textComet),
          title: Text(
            title,
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 11,
            ),
          ),
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.starGold,
          activeTrackColor: AppColors.starGold.withValues(alpha: 0.3),
          inactiveThumbColor: AppColors.universe.textComet,
          inactiveTrackColor: AppColors.universe.glassWhiteLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      );
    }

    // コース選択ロジック

    Future<void> openCoursePicker() async {
      final result = await showModalBottomSheet<CoursePickerResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CoursePickerSheet(initialSelectedCourseId: state.courseId),
      );
      if (result != null && result.confirmed) {
        controller.setCourseId(result.courseId);
      }
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // 1. Course
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.universe.glassBorder),
                              boxShadow: selectedCourse != null
                                  ? [
                                      BoxShadow(
                                        color: courseColor.withValues(alpha: 0.16),
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
                                  color: (selectedCourse != null ? displayIconColor : AppColors.universe.textComet)
                                      .withValues(alpha: 0.15),
                                ),
                                child: Icon(
                                  selectedCourse != null ? iconData : Icons.folder_outlined,
                                  color: selectedCourse != null ? displayIconColor : AppColors.universe.textComet,
                                  size: 20,
                                ),
                              ),
                              title: Text('Course', style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
                              subtitle: LayoutBuilder(
                                builder: (context, constraints) {
                                  final text = selectedCourse != null
                                      ? selectedCourse.displayTitle
                                      : 'No course selected';
                                  // 1. テキストのスタイル定義
                                  final style = TextStyle(
                                    color: AppColors.universe.textStarlight,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  );

                                  // 2. 幅に入りきるか計算する関数
                                  bool checkFit(String text) {
                                    final textPainter = TextPainter(
                                      text: TextSpan(text: text, style: style),
                                      maxLines: 1,
                                      textDirection: TextDirection.ltr,
                                    )..layout(maxWidth: double.infinity);
                                    
                                    // コンテナの幅より小さければOK
                                    return textPainter.size.width <= constraints.maxWidth;
                                  }

                                  // A. そのままで入るならそのまま表示
                                  if (checkFit(text)) {
                                    return Text(text, style: style, maxLines: 1);
                                  }

                                  // B. 入らない場合、パス区切り「 / 」で分解して、左から削っていく
                                  final parts = text.split(' / ');
                                  
                                  // 左端から1つずつ削って「... / 」に置き換えて試す
                                  for (int i = 1; i < parts.length; i++) {
                                    final candidate = '... / ${parts.sublist(i).join(' / ')}';
                                    
                                    if (checkFit(candidate)) {
                                      return Text(candidate, style: style, maxLines: 1);
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
                              trailing: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              onTap: isBusy ? null : openCoursePicker,
                            ),
                          ),
                          
                          // コース未選択時の注意書き（録音開始後のみ表示）
                          if (state.courseId == null && (state.phase == RecordingPhase.recording || state.phase == RecordingPhase.paused))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.alertAmber.withValues(alpha: 0.15),
                                  border: Border.all(color: AppColors.alertAmber, width: 1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.alertAmber,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No course selected. Automated AI analysis will not start unless a course is assigned. Please select a course before or after uploading to start analysis.',
                                        style: TextStyle(
                                          color: AppColors.universe.textStarlight,
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
                              fontFeatures: const [FontFeature.tabularFigures()],
                              shadows: [
                                Shadow(
                                  color: (state.isRecording ? AppColors.correctionRed : AppColors.starGold)
                                      .withValues(alpha: state.isRecording ? 0.45 : 0.22),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),

                          // 4. Big Mic Button (Center)
                          _MicButton(state: state, controller: controller, isBusy: isBusy),
                          const SizedBox(height: 16),

                          // Status Text
                          _StatusArea(state: state, controller: controller),

                          // Select Audio File (アイドル時のみ表示)
                          if (state.phase == RecordingPhase.idle)
                            ...[
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(child: Divider(color: AppColors.universe.glassBorder)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: AppColors.universe.textComet,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: AppColors.universe.glassBorder)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.universe.glassWhiteLow,
                                  border: Border.all(
                                    color: selectedAudioFilePath.value != null
                                        ? AppColors.starGold
                                        : AppColors.universe.textComet.withValues(alpha: 0.3),
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
                                              final result = await FilePicker.pickFiles(
                                                type: FileType.audio,
                                                allowMultiple: false,
                                              );

                                              if (result == null) {
                                                // ユーザーによるキャンセル
                                                return;
                                              }

                                              if (result.files.isNotEmpty) {
                                                final filePath = result.files.first.path;
                                                if (filePath != null &&
                                                    filePath.trim().isNotEmpty &&
                                                    context.mounted) {
                                                  selectedAudioFilePath.value = filePath;
                                                } else if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Unable to access the selected file. Please try another file.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Failed to select file: $e'),
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
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (isSelectingFile.value) ...[
                                                const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(
                                                      AppColors.starGold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Text(
                                                  'Processing audio file...',
                                                  style: TextStyle(
                                                    color: AppColors.starGold,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ] else ...[
                                                Icon(
                                                  selectedAudioFilePath.value != null
                                                      ? Icons.check_circle
                                                      : Icons.upload_file,
                                                  color: selectedAudioFilePath.value != null
                                                      ? AppColors.starGold
                                                      : AppColors.universe.textComet,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  selectedAudioFilePath.value != null
                                                      ? 'File selected'
                                                      : 'Select audio file',
                                                  style: TextStyle(
                                                    color: selectedAudioFilePath.value != null
                                                        ? AppColors.starGold
                                                        : AppColors.universe.textComet,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (!isSelectingFile.value &&
                                              selectedAudioFilePath.value != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Text(
                                                selectedAudioFilePath.value!.split('/').last,
                                                style: TextStyle(
                                                  color: AppColors.universe.textComet,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                                    backgroundColor: AppColors.universe.voidBackground,
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(color: AppColors.universe.glassBorder),
                                      borderRadius: BorderRadius.circular(16)
                                    ),
                                    title: Text('Discard Recording?', style: TextStyle(color: AppColors.universe.textStarlight)),
                                    content: Text(
                                      'This will delete the current recording. This action cannot be undone.',
                                      style: TextStyle(color: AppColors.universe.textComet),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => ctx.pop(false), 
                                        child: Text('Cancel', style: TextStyle(color: AppColors.universe.textComet))
                                      ),
                                      TextButton(
                                        onPressed: () => ctx.pop(true),
                                        child: const Text('Discard', style: TextStyle(color: AppColors.correctionRed)),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await controller.cancelAndDiscard();
                                  if (context.mounted) context.pop();
                                }
                              },
                              icon: Icon(Icons.delete_outline, size: 20, color: AppColors.universe.textComet),
                              label: Text('Discard Recording', style: TextStyle(color: AppColors.universe.textComet)),
                            ),

                          const SizedBox(height: 24),

                          // More Settings アコーディオン
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.universe.glassBorder),
                            ),
                            child: InkWell(
                              onTap: () => showMoreSettings.value = !showMoreSettings.value,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.settings_outlined,
                                          color: AppColors.universe.textComet,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'More Settings',
                                          style: TextStyle(
                                            color: AppColors.universe.textComet,
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
                                      color: AppColors.universe.textComet,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 200),
                            crossFadeState: showMoreSettings.value
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            firstChild: Column(
                              children: [
                                const SizedBox(height: 12),
                                TextField(
                                  controller: titleCtl,
                                  enabled: !isBusy,
                                  style: TextStyle(color: AppColors.universe.textStarlight),
                                  decoration: glassInputDecoration('Lecture title', Icons.title),
                                  onChanged: controller.setTitle,
                                ),
                                const SizedBox(height: 16),
                                buildToggleRow(
                                  icon: Icons.play_circle_outline,
                                  title: 'Auto-start analysis',
                                  subtitle: 'Automatically start processing tasks after upload completes.',
                                  value: state.autoStartAnalysis,
                                  onChanged: (val) => controller.setAutoStartAnalysis(val),
                                ),
                                const SizedBox(height: 12),
                                buildToggleRow(
                                  icon: Icons.chat_bubble_outline,
                                  title: 'Realtime transcribe',
                                  subtitle: 'Transcribe audio stream in realtime as you record.',
                                  value: state.realtimeTranscribe,
                                  onChanged: state.phase == RecordingPhase.idle
                                      ? (val) async {
                                          if (val && asrModelState.status != AsrModelStatus.ready) {
                                            final confirmed = await showCustomDialog(
                                              context: context,
                                              title: 'Speech model required',
                                              message:
                                                  'Realtime transcription needs this language\'s on-device speech model. Download it now?',
                                              icon: Icons.download_rounded,
                                              confirmLabel: 'Download',
                                              cancelLabel: 'Cancel',
                                            );
                                            if (confirmed != true) return;
                                            controller.setRealtimeTranscribe(true);
                                            if (context.mounted) {
                                              await ensureAsrModelWithErrorDialog(context, ref, recordingLanguage);
                                            }
                                            return;
                                          }
                                          controller.setRealtimeTranscribe(val);
                                        }
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                _RecordingLanguageRow(
                                  languageLabel: recordingLanguageFromCode(recordingLanguage).englishName,
                                  modelState: asrModelState,
                                  onDownloadTap: () =>
                                      ensureAsrModelWithErrorDialog(context, ref, recordingLanguage),
                                  onPauseTap: () => ref
                                      .read(asrModelManagerProvider.notifier)
                                      .pauseDownload(recordingLanguage),
                                  onResumeTap: () =>
                                      resumeAsrModelWithErrorDialog(context, ref, recordingLanguage),
                                  onTap: isBusy
                                      ? null
                                      : () => showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (_) => const LanguageSelectionSheet(
                                              mode: LanguageSheetMode.recording,
                                            ),
                                          ),
                                ),
                              ],
                            ),
                            secondChild: const SizedBox(width: double.infinity),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 5. Upload Button (Bottom)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
                      color: AppColors.universe.voidBackground.withValues(alpha:0.8),
                    ),
                    child: ElevatedButton(
                      onPressed: !isBusy && (state.canUpload || selectedAudioFilePath.value != null)
                          ? () async {
                              if (selectedAudioFilePath.value != null) {
                                // ファイル選択がある場合
                                if (state.courseId == null) {
                                  // Course が未選択なら警告
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please select a course before uploading'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                await controller.uploadAudioFile(selectedAudioFilePath.value!);
                                selectedAudioFilePath.value = null; // 完了後にリセット
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
                        disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                        disabledForegroundColor: AppColors.universe.textComet,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isBusy
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Uploading...',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
                          : const Text(
                              'Upload Recording',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              if (isTestMode) const SimulateRecordingTab(),
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
                      const Icon(Icons.check_circle, color: AppColors.growthGreen, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Recording Done!',
                        style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 24, fontWeight: FontWeight.bold),
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
    if (state.phase == RecordingPhase.requestingPermission) {
      return Text('Requesting microphone permission...', style: TextStyle(color: AppColors.universe.textComet));
    }

    if (state.phase == RecordingPhase.uploading) {
      return Column(
        children: [
          const CircularProgressIndicator(color: AppColors.starGold),
          const SizedBox(height: 12),
          Text('Uploading...', style: TextStyle(color: AppColors.universe.textStarlight)),
        ],
      );
    }

    if (state.phase == RecordingPhase.error) {
      return Column(
        children: [
          Text(
            state.errorMessage ?? 'Error',
            style: const TextStyle(color: AppColors.correctionRed),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: controller.openSettingsIfNeeded,
                child: const Text('Open Settings', style: TextStyle(color: AppColors.starGold)),
              ),
              TextButton(
                onPressed: controller.resetAfterError,
                child: Text('Try Again', style: TextStyle(color: AppColors.universe.textStarlight)),
              ),
            ],
          ),
        ],
      );
    }

    if (state.phase == RecordingPhase.paused) {
      return const _StatusPill(icon: Icons.pause_circle_filled, color: AppColors.alertAmber, label: 'Paused');
    }

    if (state.phase == RecordingPhase.recording) {
      return const _StatusPill(icon: Icons.fiber_manual_record, color: AppColors.correctionRed, label: 'Recording...');
    }

    return Text('Ready to record', style: TextStyle(color: AppColors.universe.textComet));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.color, required this.label});

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
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

/// 「Recording Language」設定行。タップするとLanguageSelectionSheetが開き、
/// オンデバイスASRモデルのダウンロード状況(ダウンロード中/準備完了/失敗)と
/// 併せて言語を選べる。
class _RecordingLanguageRow extends StatelessWidget {
  const _RecordingLanguageRow({
    required this.languageLabel,
    required this.modelState,
    required this.onTap,
    this.onDownloadTap,
    this.onPauseTap,
    this.onResumeTap,
  });

  final String languageLabel;
  final AsrLanguageModelState modelState;
  final VoidCallback? onTap;
  // failed/unknown状態でタップするとダウンロード/リトライ。
  final VoidCallback? onDownloadTap;
  final VoidCallback? onPauseTap;
  final VoidCallback? onResumeTap;

  @override
  Widget build(BuildContext context) {
    Widget statusIndicator;
    switch (modelState.status) {
      case AsrModelStatus.checking:
        statusIndicator = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.universe.textComet),
        );
      case AsrModelStatus.downloading:
        final progress = modelState.progress;
        statusIndicator = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                    color: AppColors.starGold,
                  ),
                  if (progress != null)
                    Text(
                      '${(progress * 100).round()}',
                      style: TextStyle(fontSize: 7, color: AppColors.universe.textComet),
                    ),
                ],
              ),
            ),
            if (onPauseTap != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPauseTap,
                child: Icon(Icons.pause_circle_outline, color: AppColors.universe.textComet, size: 20),
              ),
            ],
          ],
        );
      case AsrModelStatus.paused:
        statusIndicator = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onResumeTap,
          child: Icon(Icons.play_circle_outline, color: AppColors.starGold, size: 22),
        );
      case AsrModelStatus.ready:
        statusIndicator = const Icon(Icons.check_circle, color: AppColors.growthGreen, size: 18);
      case AsrModelStatus.failed:
        statusIndicator = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDownloadTap,
          child: const Icon(Icons.download_rounded, color: AppColors.correctionRed, size: 20),
        );
      case AsrModelStatus.unknown:
        statusIndicator = onDownloadTap == null
            ? const SizedBox.shrink()
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDownloadTap,
                child: Icon(Icons.download_rounded, color: AppColors.universe.textComet, size: 20),
              );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: ListTile(
        onTap: onTap,
        enabled: onTap != null,
        leading: Icon(Icons.translate, color: AppColors.universe.textComet),
        title: Text(
          'Recording language',
          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          modelState.status == AsrModelStatus.failed
              ? '⚠️ $friendlyAsrModelErrorMessage'
              : 'On-device speech model used for live captions.',
          maxLines: 3,
          style: TextStyle(
            color: modelState.status == AsrModelStatus.failed
                ? AppColors.correctionRed
                : AppColors.universe.textComet,
            fontSize: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(languageLabel, style: TextStyle(color: AppColors.universe.textComet, fontSize: 13)),
            const SizedBox(width: 8),
            statusIndicator,
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.universe.textComet, size: 18),
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
enum _MomentType { fun, difficult, revisit }

String _formatMmSs(int sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// リアクション/メモ種別ごとのアイコン・色・ラベル(ボタンとタイムラインで共有)。
/// `moment_type`はSupabase/ローカルDBどちらもenumやCHECK制約の無いプレーンな
/// text列(将来種類が増える前提)なので、DB由来の値は生Stringで受け取り、
/// 未知の値でも例外を投げず汎用表示にフォールバックする。
(IconData, Color, String) _momentDisplay(String momentType) {
  switch (momentType) {
    case 'fun':
      return (Icons.star_rounded, AppColors.starGold, 'Fun moment');
    case 'difficult':
      return (Icons.help_rounded, AppColors.cosmicBlue, 'Difficult');
    case 'revisit':
      return (Icons.bookmark_rounded, AppColors.growthGreen, 'Revisit later');
    case 'note':
      return (Icons.edit_note_rounded, AppColors.universe.textComet, 'Note');
    default:
      return (Icons.emoji_objects_rounded, AppColors.universe.textComet, momentType);
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
        state.phase == RecordingPhase.recording || state.phase == RecordingPhase.paused;

    final moments = lectureId != null
        ? (ref.watch(lectureMomentsProvider(lectureId)).value ?? const <LectureMoment>[])
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
          final bottomFixedArea = 56.0 + bottomSafeArea + timelineHeight + 12.0 + 64.0 + 12.0 + 48.0 + 12.0;
          final availableTranscriptHeight = constraints.maxHeight - bottomFixedArea;
          const minTranscriptHeight = 160.0;
          final transcriptHeight = availableTranscriptHeight < minTranscriptHeight
              ? minTranscriptHeight
              : availableTranscriptHeight;

          final isOverflowing = availableTranscriptHeight < minTranscriptHeight;

          return SingleChildScrollView(
            physics: isOverflowing
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 20, 20, 36 + bottomSafeArea),
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
                _NoteInputRow(controller: noteCtl, onSubmit: submitNote, enabled: canInteract),
              ],
            ),
          );
        } else {
          // Realtime OFF の場合
          final fixedAreaOff = 56.0 + bottomSafeArea + 52.0 + 12.0 + 64.0 + 12.0 + 48.0 + 12.0;
          final availableTimelineHeight = constraints.maxHeight - fixedAreaOff;
          const minTimelineHeight = 180.0;
          final timelineHeightOff = availableTimelineHeight < minTimelineHeight
              ? minTimelineHeight
              : availableTimelineHeight;

          final isOverflowing = availableTimelineHeight < minTimelineHeight;

          return SingleChildScrollView(
            physics: isOverflowing
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 20, 20, 36 + bottomSafeArea),
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
                _NoteInputRow(controller: noteCtl, onSubmit: submitNote, enabled: canInteract),
              ],
            ),
          );
        }
      },
    );
  }
}

/// 録音状態バッジ。録音中は🔴Recording...、一時停止中は🟡Paused、それ以外は非表示。
class _RecordingStatusBadge extends StatelessWidget {
  const _RecordingStatusBadge({required this.phase});

  final RecordingPhase phase;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;
    switch (phase) {
      case RecordingPhase.recording:
        icon = Icons.fiber_manual_record;
        color = AppColors.correctionRed;
        label = 'Recording...';
      case RecordingPhase.paused:
        icon = Icons.pause_circle_filled;
        color = AppColors.alertAmber;
        label = 'Paused';
      default:
        return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    final isFollowing = useState(true);

    final lectureId = this.lectureId;
    final sentences = lectureId != null
        ? (ref.watch(liveTranscriptProvider(lectureId)).value ?? const <LiveTranscriptSentence>[])
        : const <LiveTranscriptSentence>[];

    // サーバー版(lecture_transcripts)とオンデバイス版(LiveAsrController)を
    // 時刻順に素朴に連結するだけ(watermarkによる賢いマージはまだ次フェーズ)。
    // サーバー版は常に確定済みなのでisFinal:true固定。
    final onDeviceSegments = ref.watch(liveAsrControllerProvider);
    final combined = <(double, String, bool)>[
      for (final s in sentences) (s.startSec, s.text, true),
      for (final s in onDeviceSegments) (s.timestampSec, s.text, s.isFinal),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

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
                Icon(Icons.podcasts_rounded, size: 16, color: AppColors.starGold),
                const SizedBox(width: 8),
                Text(
                  'LIVE TRANSCRIPT',
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
          Expanded(
            child: Stack(
              children: [
                combined.isEmpty
                    ? Center(
                        child: Text(
                          'Waiting for audio...',
                          style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
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
                            if (metrics.pixels >= metrics.maxScrollExtent - _bottomThresholdPx) {
                              isFollowing.value = true;
                            }
                          }
                          return false;
                        },
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: combined.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, i) {
                            final (sec, text, isFinal) = combined[i];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatMmSs(sec.round()),
                                  style: TextStyle(
                                    color: AppColors.universe.textComet,
                                    fontSize: 11,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    text,
                                    // 未確定(まだendpoint検知前)の行は、確定行と
                                    // 見た目で区別できるよう斜体+やや薄い色にする。
                                    style: TextStyle(
                                      color: isFinal
                                          ? AppColors.universe.textStarlight
                                          : AppColors.universe.textStarlight.withValues(alpha: 0.6),
                                      fontStyle: isFinal ? FontStyle.normal : FontStyle.italic,
                                      fontSize: 14,
                                      height: 1.4,
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
                          child: Icon(Icons.arrow_downward_rounded, size: 18, color: Colors.white),
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
          Icon(Icons.info_outline, size: 18, color: AppColors.universe.textComet),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Turn on Realtime Transcribe (More Settings, Voice tab) to see live captions and ask AI here.',
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 12, height: 1.5),
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
    _MomentType.fun,
    _MomentType.difficult,
    _MomentType.revisit,
  ];

  static const _captions = <_MomentType, String>{
    _MomentType.fun: 'Fun',
    _MomentType.difficult: 'Difficult',
    _MomentType.revisit: 'Revisit',
  };

  Widget _button(_MomentType type) {
    final (icon, color, _) = _momentDisplay(type.name);
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
                    Text(_captions[type]!, style: TextStyle(color: AppColors.universe.textComet, fontSize: 11)),
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
    return Row(children: [for (final type in _options) _button(type)]);
  }
}

class _NoteInputRow extends StatelessWidget {
  const _NoteInputRow({required this.controller, required this.onSubmit, required this.enabled});

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            style: TextStyle(color: AppColors.universe.textStarlight),
            decoration: InputDecoration(
              hintText: 'Jot a quick note...',
              hintStyle: TextStyle(color: AppColors.universe.textComet),
              filled: true,
              fillColor: AppColors.universe.glassWhiteLow,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    if (moments.isEmpty) {
      final hintWidget = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          'Tap a reaction or add a note below — it\'ll show up here.',
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
        final (icon, color, label) = _momentDisplay(moment.momentType);
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
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 13),
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

    return SizedBox(
      height: height,
      child: listView,
    );
  }
}

// =============================================================
// Mic Button (録音中は脈動するリング、常時ほんのりグロー)
// =============================================================

class _MicButton extends HookWidget {
  const _MicButton({required this.state, required this.controller, required this.isBusy});

  final RecordingState state;
  final RecordingController controller;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final isRecording = state.isRecording;
    final pulse = useAnimationController(duration: const Duration(milliseconds: 1600));

    useEffect(() {
      if (isRecording) {
        pulse.repeat();
      } else {
        pulse.stop();
        pulse.value = 0;
      }
      return null;
    }, [isRecording]);

    final canTap = !isBusy &&
        (state.phase == RecordingPhase.idle ||
            state.phase == RecordingPhase.recording ||
            state.phase == RecordingPhase.paused);

    final accentColor = isRecording ? AppColors.correctionRed : AppColors.starGold;

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
                        color: AppColors.correctionRed.withValues(alpha: (1 - t) * 0.5),
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
                    color: accentColor.withValues(alpha: isRecording ? 0.45 : 0.25),
                    blurRadius: isRecording ? 30 : 18,
                    spreadRadius: isRecording ? 4 : 1,
                  ),
                ],
              ),
              child: Icon(
                isRecording
                    ? Icons.stop_rounded
                    : (state.phase == RecordingPhase.paused ? Icons.fiber_manual_record : Icons.mic),
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