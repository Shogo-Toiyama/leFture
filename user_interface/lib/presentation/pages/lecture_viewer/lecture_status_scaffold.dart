// lib/presentation/pages/lecture_viewer/lecture_status_scaffold.dart

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_state_providers.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart'; // Controller
import 'package:lecture_companion_ui/application/job/job_providers.dart'; // エラー詳細用
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/widgets/delete_confirm_dialog.dart';

import 'views/processing_view.dart';
import 'views/not_started_view.dart';
import 'views/status_view.dart';

class LectureStatusScaffold extends ConsumerWidget {
  const LectureStatusScaffold({super.key, required this.lecture});

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStateAsync = ref.watch(lectureStateProvider(lecture.id));
    final controllerState = ref.watch(lectureControllerProvider);
    final isActionLoading = controllerState.isLoading;

    ref.listen<AsyncValue<LectureUIState>>(
      lectureStateProvider(lecture.id),
      (previous, next) {
        next.whenData((state){
          if (state == LectureUIState.complete) {
            final uid = supabase.auth.currentUser?.id;
            if (uid != null) {
              ref.invalidate(lectureCompleteDataProvider(uid: uid, lectureId: lecture.id));
            }
          }
        });
      }
    );

    return Scaffold(
      body: uiStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (uiState) {
          switch (uiState) {
            case LectureUIState.loading:
            case LectureUIState.complete:
              return NotStartedView(lectureId: lecture.id);

            case LectureUIState.processing:
              return ProcessingView(lectureId: lecture.id);

            case LectureUIState.notStarted:
              return NotStartedView(lectureId: lecture.id);

            case LectureUIState.syncing:
              return const StatusView(
                icon: Icons.cloud_upload_outlined,
                title: 'Syncing Audio...',
                message: 'Please wait for the upload to complete.',
              );

            case LectureUIState.failed:
              // ★ エラーの詳細メッセージをJobから取得する
              final jobAsync = ref.watch(jobStreamProvider(lecture.id));
              final job = jobAsync.value;
              // エラーメッセージがあれば表示、なければデフォルト文言
              final errorMsg = job?.errorMessage?['message'] ?? 'Please try again later.';

              return StatusView(
                icon: Icons.error_outline,
                title: 'Analysis Failed',
                message: errorMsg.toString(), // サーバーからのエラーを表示
                isError: true,
                isLoading: isActionLoading, // ★ ボタンをクルクルさせる
                buttonIcon: Icons.refresh,
                buttonLabel: 'Retry',
                onButtonPressed: () {
                  // ★ 再試行ボタン：もう一度分析を開始する
                  ref.read(lectureControllerProvider.notifier).startAnalysis(lecture.id);
                },
              );

            case LectureUIState.noAudio:
              return StatusView(
                icon: Icons.no_photography_outlined,
                title: 'No Audio Found',
                isError: true,
                isLoading: isActionLoading, // 削除中もクルクル
                buttonIcon: Icons.delete,
                buttonLabel: 'Delete Lecture',
                onButtonPressed: () async {
                  final ok = await showConfirmDialog(
                    context: context,
                    title: 'Delete folder',
                    message: 'Are you sure you want to delete "${lecture.title}"?',
                    confirmLabel: 'Delete',
                  );
                  if (ok == true) {
                    await ref.read(lectureControllerProvider.notifier).deleteLecture(lecture.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              );
          }
        },
      ),
    );
  }
}