
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/application/recording/recording_controller.dart';
import 'package:lecture_companion_ui/application/recording/recording_state.dart';
import 'package:lecture_companion_ui/presentation/pages/recording/recording_page.dart';

class RecordingMiniPlayer extends ConsumerWidget {

  const RecordingMiniPlayer({
    super.key, 
    required this.isVisible,
  });

  final bool isVisible;

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordingControllerProvider);
    log('👀 [MiniPlayer] Build Called. Time: ${ref.read(recordingControllerProvider).elapsedSeconds}');

    if (!isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: GestureDetector(
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (context) => const RecordingPage(),
                fullscreenDialog: true,
              ),
            );
          },
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: state.phase == RecordingPhase.recording || state.phase == RecordingPhase.paused 
                      ? const Color.fromARGB(255, 68, 51, 10)
                      : Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.phase == RecordingPhase.recording ? const Color.fromARGB(50, 244, 67, 54) :
                          state.phase == RecordingPhase.paused ? const Color.fromARGB(50, 255, 193, 7) :
                          Colors.white,
                  ),
                  child: Icon(
                    state.phase == RecordingPhase.recording ? Icons.mic :
                    state.phase == RecordingPhase.paused ? Icons.pause :
                    Icons.mic,
                    color: state.phase == RecordingPhase.recording ? Colors.red :
                          state.phase == RecordingPhase.paused ? Colors.amber :
                          Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: state.phase == RecordingPhase.recording || state.phase == RecordingPhase.paused
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.phase == RecordingPhase.recording
                              ? 'Recording...'
                              : 'Recording Paused',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          _formatDuration(state.elapsedSeconds),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Record Lecture',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}