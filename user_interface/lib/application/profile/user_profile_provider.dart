import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/user_profile.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';

part 'user_profile_provider.g.dart';

/// ログイン中ユーザーの user_profiles レコード
@riverpod
Future<UserProfile?> currentUserProfile(Ref ref) async {
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.getCurrentProfile();
}
