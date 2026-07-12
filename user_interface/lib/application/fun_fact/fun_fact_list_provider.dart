import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

part 'fun_fact_list_provider.g.dart';

/// 最新のFunFact一覧（最大5件、ローカルDB経由でオフライン優先)
@riverpod
Stream<List<FunFact>> recentFunFacts(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Stream.empty();
  return ref.watch(funFactRepositoryDriftProvider).watchRecentFunFacts(uid, limit: 5);
}
