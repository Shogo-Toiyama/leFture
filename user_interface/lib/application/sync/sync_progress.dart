// lib/application/sync/sync_progress.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 同期（Pull）の進捗状況を表すイミュータブルモデル。
class SyncProgress {
  const SyncProgress({
    required this.completed,
    required this.total,
  });

  /// 完了（またはスキップ）したタスク数
  final int completed;

  /// 全タスク数（ハードコードせず動的に算出）
  final int total;

  /// 進行割合 (0.0 〜 1.0)
  double get fraction => total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);

  /// 全て完了したかどうか
  bool get isDone => total > 0 && completed >= total;

  static const initial = SyncProgress(completed: 0, total: 0);
}

class SyncProgressNotifier extends Notifier<SyncProgress> {
  @override
  SyncProgress build() => SyncProgress.initial;

  void update(SyncProgress progress) => state = progress;
  void reset() => state = SyncProgress.initial;
}

/// グローバルな同期進捗プロバイダー
final syncProgressProvider = NotifierProvider<SyncProgressNotifier, SyncProgress>(
  SyncProgressNotifier.new,
);
