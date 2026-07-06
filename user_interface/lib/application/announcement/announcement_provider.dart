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

/// 未完了のアナウンスメント全件（新しい順）
@riverpod
Future<List<Announcement>> activeAnnouncements(Ref ref) async {
  final repo = ref.watch(announcementRepositoryProvider);
  return repo.listActive();
}
