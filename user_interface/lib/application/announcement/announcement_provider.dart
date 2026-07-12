import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

part 'announcement_provider.g.dart';

/// 未完了のうち最新のアナウンスメント（無ければnull）。ローカルDB経由でオフライン優先。
@riverpod
Stream<Announcement?> latestAnnouncement(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(null);
  return ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncements(uid)
      .map((list) => list.isEmpty ? null : list.first);
}

/// 未完了のアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
/// Streamなので、完了/未完了のトグル(Drift経由の即時ローカル更新)がそのまま
/// 反映される — 以前のような楽観的UI用の手動state書き換えは不要。
@riverpod
Stream<List<Announcement>> activeAnnouncements(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Stream.empty();
  return ref.watch(announcementRepositoryDriftProvider).watchActiveAnnouncements(uid);
}
