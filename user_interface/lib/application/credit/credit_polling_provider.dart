import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show StreamProvider;
import '../auth/auth_provider.dart';
import '../job/job_providers.dart';
import '../recording/recording_controller.dart';
import '../recording/recording_state.dart';
import 'credit_providers.dart';

part 'credit_polling_provider.g.dart';

/// バックエンド処理中 (status IN ('PENDING', 'RUNNING')) なジョブが存在するかを監視するProvider
final hasActiveProcessingJobsProvider = StreamProvider<bool>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield false;
    return;
  }
  final repo = ref.watch(jobRepositoryProvider);
  while (true) {
    final hasActive = await repo.hasActiveProcessingJobs(user.id);
    yield hasActive;
    await Future.delayed(const Duration(seconds: 10));
  }
});

/// クレジット情報のポーリングおよび更新を一元管理するサービスクラス
class CreditPollingService {
  CreditPollingService(this._ref) {
    _init();
  }

  final Ref _ref;
  Timer? _timer;
  int _activePageCount = 0;
  Duration? _currentInterval;

  void _init() {
    _ref.listen<RecordingState>(
      recordingControllerProvider,
      (previous, next) => _evaluatePolling(),
    );
    _ref.listen<AsyncValue<bool>>(
      hasActiveProcessingJobsProvider,
      (previous, next) => _evaluatePolling(),
    );
    _evaluatePolling();
  }

  /// クレジット関連Providerを一括invalidate（最新に更新）する共通メソッド
  Future<void> invalidateCreditData() async {
    _ref.invalidate(creditSummaryProvider);
    _ref.invalidate(creditUsageHistoryProvider);
  }

  /// 手動リフレッシュ用（データ取得完了まで待機）
  Future<void> refreshCreditData() async {
    invalidateCreditData();
    await Future.wait([
      _ref.read(creditSummaryProvider.future),
      _ref.read(creditUsageHistoryProvider.future),
    ]);
  }

  /// クレジット詳細ページ表示時のポーリング要求登録
  void startPagePolling() {
    _activePageCount++;
    _evaluatePolling();
  }

  /// クレジット詳細ページ非表示時のポーリング要求解除
  void stopPagePolling() {
    if (_activePageCount > 0) {
      _activePageCount--;
      _evaluatePolling();
    }
  }

  void _evaluatePolling() {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      _stopTimer();
      return;
    }

    final recordingState = _ref.read(recordingControllerProvider);
    final isRecording =
        recordingState.isRecording || recordingState.phase == RecordingPhase.uploading;
    final hasProcessingJobs =
        _ref.read(hasActiveProcessingJobsProvider).value ?? false;
    final isPageActive = _activePageCount > 0;

    final shouldPoll = isRecording || hasProcessingJobs || isPageActive;

    if (!shouldPoll) {
      _stopTimer();
      return;
    }

    // 優先間隔の設定：
    // - クレジット詳細ページ表示中: 5秒間隔
    // - 録音中 OR バックエンド処理中: 20秒間隔
    final requiredInterval = isPageActive
        ? const Duration(seconds: 5)
        : const Duration(seconds: 20);

    if (_timer != null && _timer!.isActive && _currentInterval == requiredInterval) {
      return;
    }

    _startTimer(requiredInterval);
  }

  void _startTimer(Duration interval) {
    _stopTimer();
    _currentInterval = interval;
    _timer = Timer.periodic(interval, (_) {
      invalidateCreditData();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _currentInterval = null;
  }

  void dispose() {
    _stopTimer();
  }
}

@Riverpod(keepAlive: true, dependencies: [RecordingController])
CreditPollingService creditPolling(Ref ref) {
  final service = CreditPollingService(ref);
  ref.onDispose(service.dispose);
  return service;
}
