// presentation/pages/dev_tools/simulate_recording_tab.dart
//
// Tier 1 テストハーネス本体（Testタブ）。
// 実マイクの代わりに、スマホ内の既存の講義音声(m4a/mp3/wav等、何でも良い)を
// ファイルピッカーで選び、本番と同じ形式に変換した上でRecordingControllerに
// 流し込む。録音〜チャンク分割〜アップロード〜/start-analysis発火まで、
// 本番と全く同じコードパスを実データで再現する。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../application/course/course_list_provider.dart';
import '../../../application/recording/recording_controller.dart';
import '../../../application/recording/recording_state.dart';
import '../../themes/app_colors.dart';
import '../recording/widgets/course_picker_sheet.dart';
import 'audio_fixture_converter.dart';
import 'fixture_audio_recorder_service.dart';

class SimulateRecordingTab extends StatefulWidget {
  const SimulateRecordingTab({super.key});

  @override
  State<SimulateRecordingTab> createState() => _SimulateRecordingTabState();
}

enum _Stage { idle, converting, ready, running }

class _SimulateRecordingTabState extends State<SimulateRecordingTab> {
  final _speedController = TextEditingController(text: '1.0');

  _Stage _stage = _Stage.idle;
  String? _pickedSourcePath;
  String? _convertedPcmPath;
  String? _errorMessage;
  String? _selectedCourseId;
  FixtureAudioRecorderService? _fixtureService;

  @override
  void dispose() {
    _fixtureService?.cancelPump();
    _fixtureService?.dispose();
    _speedController.dispose();
    super.dispose();
  }

  Future<void> _pickAndConvert() async {
    setState(() {
      _errorMessage = null;
    });

    final sourcePath = await pickAudioFile();
    if (sourcePath == null) return;

    setState(() {
      _pickedSourcePath = sourcePath;
      _stage = _Stage.converting;
    });

    try {
      final pcmPath = await convertToFixturePcm(sourcePath);
      if (!mounted) return;
      setState(() {
        _convertedPcmPath = pcmPath;
        _stage = _Stage.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Conversion failed: $e';
        _stage = _Stage.idle;
      });
    }
  }

  void _start() {
    final path = _convertedPcmPath;
    if (path == null) return;

    final speed = double.tryParse(_speedController.text.trim()) ?? 1.0;

    setState(() {
      _fixtureService = FixtureAudioRecorderService(
        fixturePcmPath: path,
        speedMultiplier: speed <= 0 ? 1.0 : speed,
      );
      _stage = _Stage.running;
    });
  }

  void _reset() {
    _fixtureService?.cancelPump();
    setState(() {
      _fixtureService = null;
      _pickedSourcePath = null;
      _convertedPcmPath = null;
      _stage = _Stage.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: switch (_stage) {
        _Stage.idle || _Stage.converting => _PickForm(
            stage: _stage,
            pickedSourcePath: _pickedSourcePath,
            errorMessage: _errorMessage,
            onPick: _pickAndConvert,
          ),
        _Stage.ready => _ReadyForm(
            speedController: _speedController,
            selectedCourseId: _selectedCourseId,
            onCourseSelected: (courseId) => setState(() => _selectedCourseId = courseId),
            onStart: _start,
            onPickDifferentFile: _reset,
          ),
        _Stage.running => ProviderScope(
            overrides: [
              audioRecorderServiceProvider.overrideWithValue(_fixtureService!),
            ],
            child: _SimulationRunner(
              fixtureService: _fixtureService!,
              selectedCourseId: _selectedCourseId,
              onFinished: _reset,
            ),
          ),
      },
    );
  }
}

class _PickForm extends StatelessWidget {
  const _PickForm({
    required this.stage,
    required this.pickedSourcePath,
    required this.errorMessage,
    required this.onPick,
  });

  final _Stage stage;
  final String? pickedSourcePath;
  final String? errorMessage;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final isConverting = stage == _Stage.converting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tier 1テスト: 手元の講義音声ファイルを選ぶと、マイクの代わりに'
          '流し込んで録音〜アップロード〜バックエンド処理を丸ごと検証できます。',
        ),
        const SizedBox(height: 24),
        if (isConverting) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          Text('Converting: ${pickedSourcePath ?? ''}', textAlign: TextAlign.center),
        ] else
          ElevatedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.audio_file_outlined),
            label: const Text('Pick lecture audio file'),
          ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}

class _ReadyForm extends ConsumerWidget {
  const _ReadyForm({
    required this.speedController,
    required this.selectedCourseId,
    required this.onCourseSelected,
    required this.onStart,
    required this.onPickDifferentFile,
  });

  final TextEditingController speedController;
  final String? selectedCourseId;
  final ValueChanged<String?> onCourseSelected;
  final VoidCallback onStart;
  final VoidCallback onPickDifferentFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseListProvider).asData?.value ?? const [];
    final matches = courses.where((c) => c.id == selectedCourseId);
    final selectedCourse = matches.isEmpty ? null : matches.first;

    Future<void> pickCourse() async {
      final result = await showModalBottomSheet<CoursePickerResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CoursePickerSheet(initialSelectedCourseId: selectedCourseId),
      );
      if (result != null && result.confirmed) {
        onCourseSelected(result.courseId);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('✅ Conversion done. Ready to simulate.'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: pickCourse,
          icon: Icon(
            Icons.school_outlined,
            color: selectedCourse != null ? AppColors.starGold : null,
          ),
          label: Text(
            selectedCourse?.displayTitle ?? 'No course selected (tap to choose)',
          ),
        ),
        if (selectedCourse == null) ...[
          const SizedBox(height: 6),
          const Text(
            'Without a course, /start-analysis will NOT auto-fire after upload '
            '(matches production behavior).',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: speedController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Speed multiplier (1.0 = real-time, recommended to avoid Groq rate limits)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onStart,
          child: const Text('Start Simulated Recording'),
        ),
        TextButton(
          onPressed: onPickDifferentFile,
          child: const Text('Pick a different file'),
        ),
      ],
    );
  }
}

/// audioRecorderServiceProvider がオーバーライドされたネストしたProviderScopeの中で
/// 実際にRecordingControllerを操作する部分。
class _SimulationRunner extends ConsumerStatefulWidget {
  const _SimulationRunner({
    required this.fixtureService,
    required this.selectedCourseId,
    required this.onFinished,
  });

  final FixtureAudioRecorderService fixtureService;
  final String? selectedCourseId;
  final VoidCallback onFinished;

  @override
  ConsumerState<_SimulationRunner> createState() => _SimulationRunnerState();
}

class _SimulationRunnerState extends ConsumerState<_SimulationRunner> {
  bool _uploadTriggered = false;

  @override
  void initState() {
    super.initState();
    // 録音ボタンを押したのと同じ呼び出しで開始する（コース選択があれば先に反映しておく）
    Future.microtask(() async {
      await ref.read(recordingControllerProvider.notifier).setCourseId(widget.selectedCourseId);
      await ref.read(recordingControllerProvider.notifier).toggleStartStopResume();
    });

    // fixture音声を流し終えたら、Uploadボタンを押したのと同じ呼び出しを自動で行う
    widget.fixtureService.done.then((_) {
      if (!mounted || _uploadTriggered) return;
      _uploadTriggered = true;
      ref.read(recordingControllerProvider.notifier).upload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lecture ID: ${state.currentLectureId ?? '-'}'),
        const SizedBox(height: 8),
        Text('Course ID: ${state.courseId ?? '(none)'}'),
        const SizedBox(height: 8),
        Text('Phase: ${state.phase.name}'),
        const SizedBox(height: 8),
        Text('Elapsed: ${state.elapsedSeconds}s'),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            'Error: ${state.errorMessage}',
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 24),
        if (state.phase == RecordingPhase.queued)
          Text(
            state.courseId != null
                ? '✅ 全チャンク送信キューに登録済み。UploadManagerが送信し終えると自動で /start-analysis が発火します。'
                : '⚠️ コース未選択のため、送信完了後も /start-analysis は自動発火しません(本番と同じ挙動)。',
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () async {
            widget.fixtureService.cancelPump();
            await ref.read(recordingControllerProvider.notifier).cancelAndDiscard();
            widget.onFinished();
          },
          child: const Text('Cancel (discard this simulation)'),
        ),
      ],
    );
  }
}
