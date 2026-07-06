import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';

part 'fun_fact_list_provider.g.dart';

/// 最新のFunFact一覧（最大5件）
@riverpod
Future<List<FunFact>> recentFunFacts(Ref ref) async {
  final repo = ref.watch(funFactRepositoryProvider);
  return repo.listRecent(limit: 5);
}
