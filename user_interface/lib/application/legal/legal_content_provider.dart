import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/infrastructure/supabase/repositories/legal_content_repository_supabase.dart';

final legalContentRepositoryProvider = Provider<LegalContentRepositorySupabase>((ref) {
  return LegalContentRepositorySupabase();
});

/// Fetches a legal document (e.g. 'privacy_policy', 'terms_of_service') by
/// slug from Supabase.
final legalDocumentProvider = FutureProvider.family<LegalDocument, String>((ref, slug) {
  return ref.watch(legalContentRepositoryProvider).getDocument(slug);
});
