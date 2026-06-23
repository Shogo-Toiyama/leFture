// import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import 'package:lecture_companion_ui/presentation/themes/app_colors.dart'; // 色追加
import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';
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
    // タブコントローラー (2つ: Voice / Memo)
    final tabController = useTabController(initialLength: 2);
    final memoCtl = useTextEditingController();
    useListenable(memoCtl);
    
    // 初期タブの設定 (noteなら1番目)
    useEffect(() {
      if (initialTab == 'note') {
        tabController.animateTo(1);
      }
      return null;
    }, []);

    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);

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

    // コース選択ロジック
    final courseLabel = state.courseId != null ? 'Course selected' : 'No course selected';

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
                          // 1. Title
                          TextField(
                            controller: titleCtl,
                            enabled: !isBusy,
                            style: TextStyle(color: AppColors.universe.textStarlight),
                            decoration: glassInputDecoration('Lecture title', Icons.title),
                            onChanged: controller.setTitle,
                          ),
                          const SizedBox(height: 12),

                          // 2. Course
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.universe.glassBorder),
                            ),
                            child: ListTile(
                              leading: Icon(Icons.folder_outlined, color: AppColors.universe.textComet),
                              title: Text('Course', style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
                              subtitle: LayoutBuilder(
                                builder: (context, constraints) {
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
                                  if (checkFit(courseLabel)) {
                                    return Text(courseLabel, style: style, maxLines: 1);
                                  }

                                  // B. 入らない場合、パス区切り「 / 」で分解して、左から削っていく
                                  // 例: "Home / A / B / C" -> ["Home", "A", "B", "C"]
                                  final parts = courseLabel.split(' / ');
                                  
                                  // 左端から1つずつ削って「... / 」に置き換えて試す
                                  for (int i = 1; i < parts.length; i++) {
                                    // 候補作成: "... / B / C"
                                    final candidate = '... / ${parts.sublist(i).join(' / ')}';
                                    
                                    if (checkFit(candidate)) {
                                      return Text(candidate, style: style, maxLines: 1);
                                      // 見つかったらループ終了＆表示
                                    }
                                  }

                                  // C. それでも入らない場合（最後の1フォルダすら長い場合）
                                  // 最後のフォルダ名だけで標準のellipsisを使う
                                  return Text(
                                    parts.isNotEmpty ? parts.last : courseLabel,
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
                              leading: Icon(Icons.folder_outlined, color: AppColors.universe.textComet),
                              title: Text('Course', style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
                              subtitle: Text(
                                courseLabel,
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