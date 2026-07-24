import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// A Markdown document (Privacy Policy, Terms of Service, ...) stored in
/// Supabase so its content can be updated without an app release.
class LegalDocument {
  const LegalDocument({
    required this.slug,
    required this.title,
    required this.contentMarkdown,
    required this.updatedAt,
  });

  final String slug;
  final String title;
  final String contentMarkdown;
  final DateTime updatedAt;

  factory LegalDocument.fromMap(Map<String, dynamic> map) {
    return LegalDocument(
      slug: map['slug'] as String,
      title: map['title'] as String,
      contentMarkdown: map['content_markdown'] as String,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class LegalContentRepositorySupabase {
  static const _table = 'legal_documents';

  Future<LegalDocument> getDocument(String slug) async {
    final row = await supabase.from(_table).select().eq('slug', slug).single();
    return LegalDocument.fromMap(row);
  }
}
