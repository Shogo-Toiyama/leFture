import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

part 'announcement_provider.g.dart';

/// 未完了のうち最新のアナウンスメント（無ければnull）。ローカルDB経由でオフライン優先。
@riverpod
Stream<Announcement?> latestAnnouncement(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(null);
  return ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncements(
        uid,
        completedAfter: DateTime.now().subtract(const Duration(minutes: 5)),
      )
      .map((list) {
        // AnnouncementBarには完了済みのものは非表示にするため、未完了のみフィルタリングする
        final activeList = list.where((a) => !a.isCompleted).toList();
        return activeList.isEmpty ? null : activeList.first;
      });
}

/// 未完了、または直近5分以内に完了したアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
/// 30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。
@riverpod
Stream<List<Announcement>> activeAnnouncements(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Stream.empty();

  final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
  final stream = ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncements(uid, completedAfter: cutoff);

  // 30秒ごとにinvalidateSelf()を呼び出し、5分経過したデータを自動クリーンアップする
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(() {
    timer.cancel();
  });

  return stream;
}
