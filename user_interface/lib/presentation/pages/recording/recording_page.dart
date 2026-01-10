import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';

class RecordingPage extends ConsumerWidget {
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

    final isRecording = state.phase == RecordingPhase.recording;
    final isBusy = state.phase == RecordingPhase.requestingPermission ||
        state.phase == RecordingPhase.stopping ||
        state.phase == RecordingPhase.uploading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Lecture'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _format(state.elapsedSeconds),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 24),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording
                    ? const Color.fromARGB(35, 244, 67, 54)
                    : const Color.fromARGB(20, 33, 150, 243),
              ),
              child: Icon(
                isRecording ? Icons.stop : Icons.mic,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),

            if (state.phase == RecordingPhase.uploading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Uploading...'),
            ] else if (state.phase == RecordingPhase.queued) ...[
              Text(
                state.errorMessage ?? 'Queued, will upload when online.',
                textAlign: TextAlign.center,
              ),
            ] else if (state.phase == RecordingPhase.uploaded) ...[
              const Text('Uploaded!'),
            ] else if (state.phase == RecordingPhase.error) ...[
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

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        if (isRecording) {
                          await controller.stopAndUpload();
                        } else {
                          await controller.start();
                        }
                      },
                child: Text(isRecording ? 'Stop & Upload' : 'Start Recording'),
              ),
            ),

            const SizedBox(height: 12),
            if (state.localPath != null)
              Text(
                'Local: ${state.localPath}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
