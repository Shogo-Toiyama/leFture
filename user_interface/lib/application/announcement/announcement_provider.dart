import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/core/utils/dev_log.dart';
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

/// 全アナウンスメント（完了・未完了問わず全件、新しい順）。
@riverpod
Stream<List<Announcement>> allAnnouncements(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Stream.empty();
  return ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncements(uid, completedAfter: DateTime.fromMillisecondsSinceEpoch(0));
}

/// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
/// ページ単位(20件ずつ)で読み込む。
///
/// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
/// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
/// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
/// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
/// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。
@riverpod
class AnnouncementsPage extends _$AnnouncementsPage {
  static const int pageSize = 20;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<Announcement>> build({String status = 'active', AnnouncementType? type}) async {
    _hasMore = true;
    return _fetchPage(offset: 0, limit: pageSize);
  }

  Future<List<Announcement>> _fetchPage({required int offset, required int limit}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    final page = await ref.read(announcementRepositoryDriftProvider).fetchAnnouncementsPage(
          userId: uid,
          limit: limit,
          offset: offset,
          status: status,
          type: type,
        );
    _hasMore = page.length >= limit;
    DevLog.add(
      '📄 [AnnouncementsPage] status=$status type=${type?.name} offset=$offset limit=$limit -> '
      '${page.length}件取得 (hasMore=$_hasMore)',
    );
    return page;
  }

  /// 一覧の下端に近づいた際に呼ぶ。読み込み中、あるいはもう続きが無い場合は何もしない。
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final current = state.value;
    if (current == null) return;

    _isLoadingMore = true;
    try {
      final next = await _fetchPage(offset: current.length, limit: pageSize);
      state = AsyncData([...current, ...next]);
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 完了トグル操作をローカルstateへ即時反映する(楽観的UI。DB再取得はしない)。
  void applyLocalToggle(String id, bool completed) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final a in current)
        if (a.id == id) a.copyWith(completedAt: () => completed ? DateTime.now() : null) else a,
    ]);
  }

  /// 論理削除操作をローカルstateへ即時反映する。
  void applyLocalDelete(String id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.where((a) => a.id != id).toList());
  }

  /// 編集などDB側の内容が変わった後、現在読み込み済みの件数を保ったまま
  /// 先頭から取り直して最新化する(スクロール位置やページ数は変えない)。
  Future<void> refresh() async {
    final current = state.value;
    final count = (current == null || current.isEmpty) ? pageSize : current.length;
    final fresh = await _fetchPage(offset: 0, limit: count);
    state = AsyncData(fresh);
  }
}
