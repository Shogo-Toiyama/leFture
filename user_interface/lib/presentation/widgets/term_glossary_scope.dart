// lib/presentation/widgets/term_glossary_scope.dart
//
// DeepNotes / ReviewCards の本文に、講義キーワードの用語マークを付けるための
// 辞書をページから配る。本文側(MarkdownAnnotationBuilderの呼び出し元)は
// [TermGlossaryScope.maybeOf]で辞書を取り、用語がタップされたら[onTermTap]を呼ぶ。

import 'package:flutter/material.dart';

import 'package:lefture/core/utils/term_glossary.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class TermGlossaryScope extends InheritedWidget {
  const TermGlossaryScope({
    super.key,
    required this.glossary,
    required this.topicNumber,
    required super.child,
  });

  final TermGlossary glossary;

  /// 表示中のトピック。表記が重なったときにこのトピックのキーワードを優先する。
  final int? topicNumber;

  /// MarkdownBodyのValueKey/builderのmemoキーに混ぜる文字列。
  String get cacheKey => '${glossary.cacheKey}@$topicNumber';

  static TermGlossaryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TermGlossaryScope>();

  @override
  bool updateShouldNotify(TermGlossaryScope oldWidget) =>
      oldWidget.glossary != glossary || oldWidget.topicNumber != topicNumber;
}

/// 用語の定義を下から出す。
void showTermDefinitionSheet(BuildContext context, TermEntry entry) {
  final l10n = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.6;
      return Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.paper.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.paper.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.termSheetLabel,
                        style: const TextStyle(
                          color: Color(0xFFCC8D00),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.keyword,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        entry.definition,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 15,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
