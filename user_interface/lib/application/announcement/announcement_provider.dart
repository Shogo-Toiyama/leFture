import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';

part 'announcement_provider.g.dart';

/// 未完了のうち最新のアナウンスメント（無ければnull）
@riverpod
Future<Announcement?> latestAnnouncement(Ref ref) async {
  final repo = ref.watch(announcementRepositoryProvider);
  return repo.getLatestActive();
}

/// 未完了のアナウンスメント全件（新しい順）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
@riverpod
class ActiveAnnouncements extends _$ActiveAnnouncements {
  @override
  Future<List<Announcement>> build() async {
    final repo = ref.watch(announcementRepositoryProvider);
    return repo.listActive();
  }

  /// 指定アナウンスメントの完了/未完了をトグルして楽観的に状態を更新する。
  Future<void> toggleComplete(Announcement announcement) async {
    final repo = ref.read(announcementRepositoryProvider);
    final newCompletedAt = announcement.isCompleted ? null : DateTime.now();

    // 楽観的UI更新: ローカル状態のみ書き換え
    state = AsyncData(
      (state.value ?? []).map((a) {
        if (a.id == announcement.id) {
          return a.copyWith(completedAt: () => newCompletedAt);
        }
        return a;
      }).toList(),
    );

    // Supabase にも非同期で書き込む
    await repo.markAsCompleted(announcement.id, newCompletedAt);

    // latestAnnouncement（AnnouncementBar用）は再フェッチで最新を反映
    ref.invalidate(latestAnnouncementProvider);
  }
}
