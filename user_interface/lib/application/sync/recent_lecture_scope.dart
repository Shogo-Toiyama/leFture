import 'dart:math' as math;

import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// 子データ(トピック/Deep Note/復習カード/キーワード/Fun Fact/お知らせ)の
/// 全件Pullを、ユーザーの全講義ではなく「直近[recentLectureCount]講義」に
/// 絞るための範囲。
///
/// 講義の行そのもの(lectures)とコースは軽いので今まで通り全件Pullする。
/// 重いのは子データ(実測で全件Pullの約98%)なので、そこだけを絞る。
/// 範囲外の古い講義の子データは、その講義を開いた時に
/// [LectureContentSync]が取りに行く。
///
/// 1回のbootstrapで複数のSyncServiceが同じ範囲を使うため、IDの取得は
/// 1インスタンスにつき1回だけ行う(メモ化)。どのエンティティが実際に
/// この範囲で全件Pullしたかも記録し、全て揃った時だけ呼び出し元が
/// 「直近講義の子データは取得済み」と記録できるようにする。
class RecentLectureScope {
  RecentLectureScope();

  /// Homeの「最近の講義」(10件)より余裕を持たせた件数。
  static const int recentLectureCount = 20;

  Future<List<String>>? _ids;
  final Set<String> _fullPulledEntityTypes = {};

  /// 授業日(lecture_datetime)の新しい順に、削除されていない講義のID。
  /// ローカルの一覧表示(watchAllLectures)と同じ並び順。
  Future<List<String>> recentLectureIds(String userId) =>
      _ids ??= _fetchRecentLectureIds(userId);

  void markFullPulled(String entityType) => _fullPulledEntityTypes.add(entityType);

  bool hasFullPulledAll(Iterable<String> entityTypes) =>
      entityTypes.every(_fullPulledEntityTypes.contains);

  static Future<List<String>> _fetchRecentLectureIds(String userId) async {
    final List<dynamic> rows = await supabase
        .from('lectures')
        .select('id')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('lecture_datetime', ascending: false, nullsFirst: false)
        .limit(recentLectureCount)
        .timeout(networkTimeout);
    return rows.map((r) => r['id'] as String).toList();
  }
}

/// PostgRESTのURL長を抑えるため、`lecture_id in (...)`のIDをこの件数ずつに
/// 分けて取得する。
const int _lectureIdChunkSize = 50;

/// [table]から、[userId]の行のうち[lectureIds]のいずれかに属する行を全て取得する。
Future<List<dynamic>> fetchRowsForLectures(
  String table,
  String userId,
  List<String> lectureIds,
) async {
  if (lectureIds.isEmpty) return const [];
  final out = <dynamic>[];
  for (var i = 0; i < lectureIds.length; i += _lectureIdChunkSize) {
    final chunk = lectureIds.sublist(
      i,
      math.min(i + _lectureIdChunkSize, lectureIds.length),
    );
    final List<dynamic> rows = await supabase
        .from(table)
        .select()
        .eq('user_id', userId)
        .inFilter('lecture_id', chunk)
        .timeout(networkTimeout);
    out.addAll(rows);
  }
  return out;
}

/// プロフィールの記録(保存・いいね・よくない)に出る行の条件。
/// `metadata.saved == true` または `metadata.reaction in (like, dislike)`。
const String flaggedRowsFilter =
    'metadata->>saved.eq.true,metadata->>reaction.in.(like,dislike)';

/// [table]から、[userId]の保存・リアクション済みの行を講義に関係なく全て取得する。
Future<List<dynamic>> fetchFlaggedRows(String table, String userId) async {
  final List<dynamic> rows = await supabase
      .from(table)
      .select()
      .eq('user_id', userId)
      .or(flaggedRowsFilter)
      .timeout(networkTimeout);
  return rows;
}
