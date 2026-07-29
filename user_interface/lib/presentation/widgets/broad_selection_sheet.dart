import 'package:flutter/material.dart';
import 'package:lefture/core/utils/annotation_text_utils.dart';
import 'package:lefture/core/utils/sid_citation.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// 広範囲選択時に、選択された範囲に含まれる各引用区間を提示し、
/// ユーザーが閲覧したいトランスクリプトセクションを選択できるボトムシート（ホワイトテーマ）。
class BroadSelectionSheet extends StatelessWidget {
  const BroadSelectionSheet({
    super.key,
    required this.options,
  });

  final List<BroadSelectionOption> options;

  static Future<SidCitation?> show(
    BuildContext context, {
    required List<BroadSelectionOption> options,
  }) {
    return showModalBottomSheet<SidCitation>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => BroadSelectionSheet(options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ドラッグハンドル
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.broadSelectionSheetTitle,
              style: const TextStyle(
                color: Color(0xFF1E1E2C),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.broadSelectionSheetDescription,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final option = options[index];
                  return _buildOptionTile(context, option);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context, BroadSelectionOption option) {
    final text = option.sectionPlainText;
    final selStart = option.selectedStartInSection;
    final selEnd = option.selectedEndInSection;

    List<InlineSpan> spans = [];

    if (selStart != null &&
        selEnd != null &&
        selStart >= 0 &&
        selEnd <= text.length &&
        selStart < selEnd) {
      // ハイライト領域が文の後半にある場合でも必ず見えるように、選択箇所の前後を中心にスニペットを作成
      int snippetStart = 0;
      bool hasLeadingEllipsis = false;

      if (selStart > 25) {
        snippetStart = selStart - 25;
        hasLeadingEllipsis = true;
      }

      int snippetEnd = (snippetStart + 120 < text.length)
          ? snippetStart + 120
          : text.length;
      if (snippetEnd < selEnd) {
        snippetEnd = text.length;
      }
      bool hasTrailingEllipsis = snippetEnd < text.length;

      final snippetText = text.substring(snippetStart, snippetEnd);
      final localSelStart = selStart - snippetStart;
      final localSelEnd = selEnd - snippetStart;

      if (hasLeadingEllipsis) {
        spans.add(const TextSpan(
          text: '... ',
          style: TextStyle(color: Colors.black45, fontSize: 13, fontWeight: FontWeight.bold),
        ));
      }

      if (localSelStart > 0) {
        spans.add(TextSpan(
          text: snippetText.substring(0, localSelStart),
          style: const TextStyle(color: Colors.black87, fontSize: 13),
        ));
      }

      spans.add(TextSpan(
        text: snippetText.substring(localSelStart, localSelEnd),
        style: const TextStyle(
          color: Color(0xFF856404), // 濃いアンバー文字
          backgroundColor: Color(0xFFFFF3CD), // 柔らかい黄色ハイライト背景
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFFFC107),
          fontSize: 13,
        ),
      ));

      if (localSelEnd < snippetText.length) {
        spans.add(TextSpan(
          text: snippetText.substring(localSelEnd),
          style: const TextStyle(color: Colors.black87, fontSize: 13),
        ));
      }

      if (hasTrailingEllipsis) {
        spans.add(const TextSpan(
          text: ' ...',
          style: TextStyle(color: Colors.black45, fontSize: 13, fontWeight: FontWeight.bold),
        ));
      }
    } else {
      spans.add(TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black87, fontSize: 13),
      ));
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop(option.citation);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA), // 明るいホワイト/ライトグレーカード
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFE9ECEF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.text_snippet_rounded,
                  color: Color(0xFF495057),
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: spans),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
