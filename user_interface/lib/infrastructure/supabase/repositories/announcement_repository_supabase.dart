import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'announcement_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
AnnouncementRepositorySupabase announcementRepository(Ref ref) {
  return AnnouncementRepositorySupabase();
}

class AnnouncementRepositorySupabase {
  static const _table = 'announcements';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// 未完了(completed_atがNull)のうち、最新の1件を取得
  /// (将来的には期限が近いものを優先する等のロジックに差し替える想定)
  Future<Announcement?> getLatestActive() async {
    final uid = _requireUid();

    final row = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .isFilter('completed_at', null)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return Announcement.fromMap(row);
  }

  /// 未完了のアナウンスメント全件（新しい順）
  Future<List<Announcement>> listActive() async {
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .isFilter('completed_at', null)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return rows.map((e) => Announcement.fromMap(e)).toList();
  }

  /// 指定レクチャーのアナウンスメント一覧（講義内での発生順、論理削除除外）
  Future<List<Announcement>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);

    return rows.map((e) => Announcement.fromMap(e)).toList();
  }

  /// 指定レクチャー群（コース内の全レクチャー等）に紐づく、未完了のうち最新の1件
  Future<Announcement?> getLatestActiveForLectureIds(List<String> lectureIds) async {
    if (lectureIds.isEmpty) return null;
    final uid = _requireUid();

    final row = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .inFilter('lecture_id', lectureIds)
        .isFilter('completed_at', null)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return Announcement.fromMap(row);
  }

  /// 指定レクチャー群に紐づく、未完了のアナウンスメント一覧（新しい順）
  Future<List<Announcement>> listActiveForLectureIds(List<String> lectureIds) async {
    if (lectureIds.isEmpty) return [];
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .inFilter('lecture_id', lectureIds)
        .isFilter('completed_at', null)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return rows.map((e) => Announcement.fromMap(e)).toList();
  }

  /// 指定アナウンスメントの completed_at を更新する。nullを渡すと未完了に戻る。
  Future<void> markAsCompleted(String id, DateTime? completedAt) async {
    await supabase.from(_table).update({
      'completed_at': completedAt?.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// 指定レクチャーに紐づく全アナウンスメントを論理削除する（Lecture削除時のカスケード用）
  Future<void> softDeleteForLecture(String lectureId) async {
    await supabase
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('lecture_id', lectureId);
  }
}
