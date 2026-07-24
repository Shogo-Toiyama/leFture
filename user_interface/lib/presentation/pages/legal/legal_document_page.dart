// lib/presentation/pages/legal/legal_document_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/application/legal/legal_content_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';

/// Generic "Paper"-themed reader for a Markdown legal document fetched from
/// Supabase (see [LegalContentRepositorySupabase]). Both the Privacy Policy
/// and Terms of Service pages are just this widget pointed at a different
/// `slug` — only the content differs, the layout is shared.
class LegalDocumentPage extends ConsumerWidget {
  const LegalDocumentPage({
    super.key,
    required this.slug,
    required this.fallbackTitle,
  });

  /// Row key in the `legal_documents` Supabase table, e.g. 'privacy_policy'.
  final String slug;

  /// Shown as the app bar title while the document (and its own title) is
  /// still loading.
  final String fallbackTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final documentAsync = ref.watch(legalDocumentProvider(slug));

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      appBar: AppBar(
        backgroundColor: AppColors.paper.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.paper.textInk),
        title: Text(
          documentAsync.asData?.value.title ?? fallbackTitle,
          style: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: documentAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.starGold),
          ),
          error: (error, stackTrace) => _ErrorState(
            onRetry: () => ref.invalidate(legalDocumentProvider(slug)),
          ),
          data: (document) => RefreshIndicator(
            color: AppColors.starGold,
            onRefresh: () async => ref.invalidate(legalDocumentProvider(slug)),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.legalDocumentLastUpdated(DateFormat.yMMMd(l10n.localeName).format(document.updatedAt)),
                    style: TextStyle(color: AppColors.paper.textPencil, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  MarkdownBody(
                    data: document.contentMarkdown,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: TextStyle(color: AppColors.paper.textInk, fontSize: 16, height: 1.6),
                      h1: TextStyle(color: AppColors.paper.textInk, fontSize: 24, fontWeight: FontWeight.bold),
                      h2: TextStyle(color: AppColors.paper.textInk, fontSize: 20, fontWeight: FontWeight.bold),
                      h3: TextStyle(color: AppColors.paper.textInk, fontSize: 18, fontWeight: FontWeight.bold),
                      listBullet: TextStyle(color: AppColors.paper.textInk, fontSize: 16),
                      strong: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold),
                      a: const TextStyle(color: AppColors.deepGold, decoration: TextDecoration.underline),
                      blockquoteDecoration: BoxDecoration(
                        color: AppColors.paper.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(left: BorderSide(color: AppColors.starGold, width: 3)),
                      ),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.paper.line)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: AppColors.paper.textPencil, size: 40),
            const SizedBox(height: 16),
            Text(
              l10n.legalDocumentLoadErrorTitle,
              style: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.legalDocumentLoadErrorSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.paper.textPencil),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.starGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l10n.commonRetryButton),
            ),
          ],
        ),
      ),
    );
  }
}
