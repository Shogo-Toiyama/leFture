import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/core/legal/app_legal_region.dart';
import 'package:lefture/infrastructure/supabase/repositories/legal_content_repository_supabase.dart';

final legalContentRepositoryProvider = Provider<LegalContentRepositorySupabase>((ref) {
  return LegalContentRepositorySupabase();
});

/// Fetches a legal document (e.g. 'privacy_policy', 'terms_of_service') by
/// slug from Supabase, in the app's current display language (falling back
/// to English if that translation doesn't exist yet) for [kAppLegalRegion].
/// Re-fetches whenever the display language changes.
final legalDocumentProvider = FutureProvider.family<LegalDocument, String>((ref, slug) {
  final locale = ref.watch(displayLanguageControllerProvider);
  return ref.watch(legalContentRepositoryProvider).getDocument(slug, locale, kAppLegalRegion);
});
