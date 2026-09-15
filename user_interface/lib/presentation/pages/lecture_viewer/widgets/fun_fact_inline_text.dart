import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Fun Factの本文に含まれるWeb文献引用記法 (例: ⟦1⟧, ⟦1, 2⟧) を検出し、
/// タップ可能なソースボタン (WidgetSpan) としてインライン表示するウィジェット。
class FunFactInlineText extends StatelessWidget {
  const FunFactInlineText({
    super.key,
    required this.text,
    required this.sources,
    this.style,
  });

  final String text;
  final List<String> sources;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(?:⟦|〚|\[\[)\s*(\d+[\d\s,，\-–—−]*)\s*(?:⟧|〛|\]\])');
    var lastIndex = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: style,
        ));
      }

      final inner = match.group(1) ?? '';
      final numMatches = RegExp(r'\d+').allMatches(inner);

      for (final numMatch in numMatches) {
        final numStr = numMatch.group(0);
        final num = int.tryParse(numStr ?? '');
        if (num != null && num > 0 && num <= sources.length) {
          final url = sources[num - 1];
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _InlineSourceChip(
              number: num,
              url: url,
            ),
          ));
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: style,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
    );
  }
}

class _InlineSourceChip extends StatelessWidget {
  const _InlineSourceChip({
    required this.number,
    required this.url,
  });

  final int number;
  final String url;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    var launched = false;
    if (uri != null) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.lectureViewerFunFactLinkOpenFailedSnackbar)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppColors.starGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.starGold.withValues(alpha: 0.45),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$number',
                style: const TextStyle(
                  color: AppColors.starGold,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.open_in_new,
                size: 9,
                color: AppColors.starGold.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
