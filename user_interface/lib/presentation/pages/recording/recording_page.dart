import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'dart:async';

import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';
import '../../../application/lecture_folders/folder_breadcrumb_provider.dart';
import 'widgets/folder_picker_sheet.dart';

class RecordingPage extends HookConsumerWidget {
  const RecordingPage({super.key});

  String _format(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);

    ref.listen<RecordingState>(recordingControllerProvider, (previous, next) {
      if (next.phase == RecordingPhase.uploaded && previous?.phase != RecordingPhase.uploaded) {
        // 少し余韻を持たせてから閉じる
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            context.go(AppRoutes.dashboard); 
          }
        });
      }
    });

    final titleCtl = useTextEditingController(text: state.title);
    useEffect(() {
      if (titleCtl.text != state.title) {
        titleCtl.text = state.title ?? 'New Lecture';
        titleCtl.selection = TextSelection.collapsed(offset: titleCtl.text.length);
      }
      return null;
    }, [state.title]);

    final isBusy = state.isBusy;
    final isRecording = state.isRecording;

    final folderChainAsync = ref.watch(folderBreadcrumbProvider(state.folderId));
    final folderLabel = folderChainAsync.maybeWhen(
      data: (chain) =>
          chain.isEmpty ? 'Home' : 'Home / ${chain.map((c) => c.name).join(' / ')}',
      orElse: () => '...',
    );

    String primaryLabel() {
      switch (state.phase) {
        case RecordingPhase.idle:
          return 'Start';
        case RecordingPhase.recording:
          return 'Stop';
        case RecordingPhase.paused:
          return 'Resume';
        default:
          return 'Start';
      }
    }

    return PopScope(
      canPop: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0;
          if (vx > 200) {
            context.go(AppRoutes.dashboard);
          }
        },
        child: Scaffold(
          body: Stack(
            children: [
              Scaffold(
                appBar: AppBar(
                  title: const Text('Record Lecture'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => context.go(AppRoutes.dashboard),
                  ),
                ),
                body: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Title
                            TextField(
                              controller: titleCtl,
                              enabled: !isBusy,
                              decoration: const InputDecoration(
                                labelText: 'Lecture title',
                                hintText: 'e.g., CS 101 - Week 3',
                              ),
                              onChanged: controller.setTitle,
                            ),
                            const SizedBox(height: 12),

                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.folder_outlined),
                              title: const Text('Folder'),
                              subtitle: Text(
                                folderLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.arrow_drop_down),
                              onTap: isBusy
                                  ? null
                                  : () async {
                                      final result =
                                          await showModalBottomSheet<FolderPickerResult>(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => FolderPickerSheet(
                                          initialSelectedFolderId: state.folderId,
                                        ),
                                      );

                                      if (result == null || !result.confirmed) return;
                                      controller.setFolderId(result.folderId);
                                    },
                            ),

                            if (state.metadataWarning != null) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  state.metadataWarning!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                                ),
                              ),
                            ],

                            const SizedBox(height: 24),

                            // Timer
                            Text(
                              _format(state.elapsedSeconds),
                              style: Theme.of(context).textTheme.displaySmall,
                            ),
                            const SizedBox(height: 18),

                            // Mic icon
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRecording
                                    ? const Color.fromARGB(35, 244, 67, 54)
                                    : const Color.fromARGB(20, 33, 150, 243),
                              ),
                              child: Icon(
                                isRecording ? Icons.mic : Icons.mic_none,
                                size: 60,
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Status
                            _StatusArea(state: state, controller: controller),

                            const Spacer(),

                            // Buttons (2)
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: isBusy || (state.phase != RecordingPhase.idle && state.phase != RecordingPhase.recording && state.phase != RecordingPhase.paused)
                                        ? null
                                        : () => controller.toggleStartStopResume(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: state.phase == RecordingPhase.recording ? Colors.red : 
                                                      state.phase == RecordingPhase.paused ? Theme.of(context).colorScheme.secondary :
                                                      Theme.of(context).colorScheme.primary,
                                    ),
                                    child: Text(primaryLabel()),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    // Uploadは Paused のときだけ有効
                                    onPressed: state.canUpload && !isBusy
                                        ? () => controller.upload()
                                        : null,
                                    child: const Text('Upload'),
                                  ),
                                ),
                              ],
                            ),

                            if (state.phase == RecordingPhase.recording || 
                                state.phase == RecordingPhase.paused ||
                                state.phase == RecordingPhase.error) ...[
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: () async {
                                  // 確認ダイアログを出す
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Discard Recording?'),
                                      content: const Text('This will delete the current recording. This action cannot be undone.'),
                                      actions: [
                                        TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
                                        TextButton(
                                          onPressed: () => ctx.pop(true),
                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                          child: const Text('Discard'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await controller.cancelAndDiscard();
                                    if (context.mounted) context.go(AppRoutes.dashboard);
                                  }
                                },
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                label: const Text('Discard Recording', style: TextStyle(color: Colors.grey)),
                              ),
                            ],
                            
                            // ★削除: "New Recording" ボタンのブロックは削除しました。
                            
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),

              if (state.phase == RecordingPhase.uploaded)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'Recording Done!',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      )
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
      return const Text('Requesting microphone permission...');
    }

    if (state.phase == RecordingPhase.uploading) {
      return const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Uploading...'),
        ],
      );
    }

    if (state.phase == RecordingPhase.queued) {
      return Text(
        state.errorMessage ?? 'Queued, will upload when online.',
        textAlign: TextAlign.center,
      );
    }

    if (state.phase == RecordingPhase.uploaded) {
      return const Text('Uploaded!');
    }

    if (state.phase == RecordingPhase.error) {
      return Column(
        children: [
          Text(
            state.errorMessage ?? 'Error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: controller.openSettingsIfNeeded,
            child: const Text('Open Settings'),
          ),
        ],
      );
    }

    if (state.phase == RecordingPhase.paused) {
      return const Text('Paused. You can resume or upload.');
    }

    if (state.phase == RecordingPhase.recording) {
      return const Text('Recording...');
    }

    return const SizedBox.shrink();
  }
}
