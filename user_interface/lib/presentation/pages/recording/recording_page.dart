// import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart'; // 色追加
import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';
import '../dev_tools/simulate_recording_tab.dart';
import '../dev_tools/test_mode_flag.dart';
import 'widgets/course_picker_sheet.dart';

class RecordingPage extends HookConsumerWidget {
  const RecordingPage({super.key, this.initialTab});
  
  // URLパラメータなどでタブ指定を受け取れるように拡張
  final String? initialTab;

  String _format(int sec) {
    final h = (sec ~/ 3600).toString();
    final m = ((sec ~/ 60) % 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // タブコントローラー (Voice / Memo、isTestModeの時だけTestタブが加わる)
    final tabController = useTabController(initialLength: isTestMode ? 3 : 2);
    final memoCtl = useTextEditingController();
    useListenable(memoCtl);
    final showMoreSettings = useState(false);
    final autoStartAnalysis = useState(true);
    final realtimeTranscribe = useState(false);
    
    // 初期タブの設定 (noteなら1番目)
    useEffect(() {
      if (initialTab == 'note') {
        tabController.animateTo(1);
      }
      return null;
    }, []);

    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);

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
      required ValueChanged<bool> onChanged,
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
    final isRecording = state.isRecording;
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
            Tab(icon: Icon(Icons.edit_note)),
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
                            ),
                            child: ListTile(
                              leading: Icon(
                                selectedCourse != null ? iconData : Icons.folder_outlined,
                                color: selectedCourse != null ? displayIconColor : AppColors.universe.textComet,
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 64,
                              fontWeight: FontWeight.w200,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 40),

                          // 4. Big Mic Button (Center)
                          GestureDetector(
                            onTap: (isBusy || (state.phase != RecordingPhase.idle && state.phase != RecordingPhase.recording && state.phase != RecordingPhase.paused))
                                ? null
                                : () => controller.toggleStartStopResume(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRecording
                                    ? AppColors.correctionRed.withValues(alpha: 0.2) 
                                    : AppColors.starGold.withValues(alpha: 0.1), 
                                border: Border.all(
                                  color: isRecording ? AppColors.correctionRed : AppColors.starGold,
                                  width: 2,
                                ),
                                boxShadow: [
                                  if (isRecording)
                                    BoxShadow(
                                      color: AppColors.correctionRed.withValues(alpha:0.5),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                ],
                              ),
                              child: Icon(
                                isRecording ? Icons.stop_rounded : 
                                (state.phase == RecordingPhase.paused ? Icons.fiber_manual_record : Icons.mic),
                                size: 64,
                                color: isRecording ? AppColors.correctionRed : AppColors.starGold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Status Text
                          _StatusArea(state: state, controller: controller),

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
                          InkWell(
                            onTap: () => showMoreSettings.value = !showMoreSettings.value,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    showMoreSettings.value
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: AppColors.universe.textComet,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
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
                                  value: autoStartAnalysis.value,
                                  onChanged: (val) => autoStartAnalysis.value = val,
                                ),
                                const SizedBox(height: 12),
                                buildToggleRow(
                                  icon: Icons.chat_bubble_outline,
                                  title: 'Realtime transcribe',
                                  subtitle: 'Transcribe audio stream in realtime as you record.',
                                  value: realtimeTranscribe.value,
                                  onChanged: (val) => realtimeTranscribe.value = val,
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
                      onPressed: state.canUpload && !isBusy ? () => controller.upload() : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.starGold,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                        disabledForegroundColor: AppColors.universe.textComet,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Upload Recording', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),

              // ==========================================
              // Tab 2: Memo (Manual Entry)
              // ==========================================
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
          TextButton(
            onPressed: controller.openSettingsIfNeeded,
            child: const Text('Open Settings', style: TextStyle(color: AppColors.starGold)),
          ),
        ],
      );
    }

    if (state.phase == RecordingPhase.paused) {
      return Text('Paused', style: TextStyle(color: AppColors.alertAmber, fontWeight: FontWeight.bold));
    }

    if (state.phase == RecordingPhase.recording) {
      return const Text('Recording...', style: TextStyle(color: AppColors.correctionRed, fontWeight: FontWeight.bold));
    }

    return Text('Ready to record', style: TextStyle(color: AppColors.universe.textComet));
  }
}