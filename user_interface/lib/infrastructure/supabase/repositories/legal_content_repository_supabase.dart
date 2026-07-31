import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// A Markdown document (Privacy Policy, Terms of Service, ...) stored in
/// Supabase so its content can be updated without an app release.
class LegalDocument {
  const LegalDocument({
    required this.slug,
    required this.locale,
    required this.region,
    required this.version,
    required this.title,
    required this.contentMarkdown,
    required this.effectiveDate,
    required this.updatedAt,
  });

  final String slug;
  final String locale;
  final String region;
  final int version;
  final String title;
  final String contentMarkdown;
  final DateTime effectiveDate;
  final DateTime updatedAt;

  factory LegalDocument.fromMap(Map<String, dynamic> map) {
    return LegalDocument(
      slug: map['slug'] as String,
      locale: map['locale'] as String,
      region: map['region'] as String,
      version: map['version'] as int,
      title: map['title'] as String,
      contentMarkdown: map['content_markdown'] as String,
      effectiveDate: DateTime.parse(map['effective_date'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class LegalContentRepositorySupabase {
  static const _table = 'legal_documents';

  /// Locale shown when [locale] has no translated row yet for [region].
  static const _fallbackLocale = 'en';

  /// Fetches the document for [slug] in [locale] for [region] (the app's
  /// legal/regulatory region, see [kAppLegalRegion]), falling back to
  /// [_fallbackLocale] if that translation doesn't exist yet for [region].
  Future<LegalDocument> getDocument(String slug, String locale, String region) async {
    final row = await supabase
        .from(_table)
        .select()
        .eq('slug', slug)
        .eq('locale', locale)
        .eq('region', region)
        .maybeSingle();
    if (row != null) return LegalDocument.fromMap(row);

    final fallbackRow = await supabase
        .from(_table)
        .select()
        .eq('slug', slug)
        .eq('locale', _fallbackLocale)
        .eq('region', region)
        .single();
    return LegalDocument.fromMap(fallbackRow);
  }
}
