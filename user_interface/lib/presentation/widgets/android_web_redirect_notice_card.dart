import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Android(消費専用モデル)向けに、ウェブサイトでの購入を案内するNoticeカード。
/// `<gold>...</gold>` で囲まれた箇所をゴールド(黄色)の太字、
/// `<b>...</b>` で囲まれた箇所を白色の太字でハイライト表示する。
class AndroidWebRedirectNoticeCard extends StatelessWidget {
  const AndroidWebRedirectNoticeCard({
    super.key,
    required this.text,
    this.accentColor = AppColors.starGold,
  });

  final String text;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: accentColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: AnnotatedDisclosureText(
                text: text,
                accentColor: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `<gold>...</gold>` と `<b>...</b>` のタグを解析してTextSpanを構築するテキストWidget。
class AnnotatedDisclosureText extends StatelessWidget {
  const AnnotatedDisclosureText({
    super.key,
    required this.text,
    this.accentColor = AppColors.starGold,
    this.defaultStyle,
  });

  final String text;
  final Color accentColor;
  final TextStyle? defaultStyle;

  @override
  Widget build(BuildContext context) {
    final effectiveDefault = defaultStyle ??
        TextStyle(
          color: Colors.white.withValues(alpha: 0.82),
          fontSize: 13,
          height: 1.55,
          fontWeight: FontWeight.w400,
        );

    final effectiveGold = TextStyle(
      color: accentColor,
      fontWeight: FontWeight.w700,
    );

    const effectiveBold = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

    final spans = <TextSpan>[];
    final tagRegex = RegExp(r'<(gold|b)>(.*?)</\1>');
    int currentIndex = 0;

    for (final match in tagRegex.allMatches(text)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, match.start),
          style: effectiveDefault,
        ));
      }

      final tag = match.group(1);
      final content = match.group(2) ?? '';

      if (tag == 'gold') {
        spans.add(TextSpan(
          text: content,
          style: effectiveDefault.merge(effectiveGold),
        ));
      } else if (tag == 'b') {
        spans.add(TextSpan(
          text: content,
          style: effectiveDefault.merge(effectiveBold),
        ));
      }

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: effectiveDefault,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }
}
