import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fun_fact_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
FunFactRepositorySupabase funFactRepository(Ref ref) {
  return FunFactRepositorySupabase();
}

class FunFactRepositorySupabase {
  static const _table = 'fun_facts';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// 最新のFunFactを最大[limit]件取得
  Future<List<FunFact>> listRecent({int limit = 5}) async {
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map((e) => FunFact.fromMap(e)).toList();
  }

  /// 指定レクチャーのFunFact一覧（新しい順）
  Future<List<FunFact>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .order('created_at', ascending: false);

    return rows.map((e) => FunFact.fromMap(e)).toList();
  }

  /// metadataにreactionを設定して更新
  Future<void> updateReaction(String id, String? reaction) async {
    final uid = _requireUid();

    final row = await supabase
        .from(_table)
        .select('metadata')
        .eq('id', id)
        .eq('user_id', uid)
        .single();

    final currentMetadata = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    if (reaction != null) {
      currentMetadata['reaction'] = reaction;
    } else {
      currentMetadata.remove('reaction');
    }

    await supabase
        .from(_table)
        .update({
          'metadata': currentMetadata,
        })
        .eq('id', id)
        .eq('user_id', uid);
  }
}
