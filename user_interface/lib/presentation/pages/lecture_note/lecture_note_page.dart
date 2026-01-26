// lib/presentation/pages/lecture_note/lecture_note_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_data.dart';

class LectureNotePage extends StatelessWidget {
  const LectureNotePage({
    super.key,
    required this.lecture,
    required this.segment,
  });

  final Lecture lecture;
  final LectureSegment segment;

  /// 引用タグ (例: ⟦s000123⟧) を除去するヘルパー
  String _cleanContent(String content) {
    // 正規表現で ⟦...⟧ のパターンを空文字に置換
    return content.replaceAll(RegExp(r'⟦s.*?⟧'), '');
  }

  @override
  Widget build(BuildContext context) {
    // Markdownの本文を作成（Detail + FunFact）
    final markdownContent = StringBuffer();
    markdownContent.writeln(_cleanContent(segment.detailContent));
    
    if (segment.funFact != null && segment.funFact!.isNotEmpty) {
      markdownContent.writeln('\n---\n'); // 区切り線
      markdownContent.writeln(_cleanContent(segment.funFact!));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Topic ${segment.idx}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              lecture.title ?? 'Untitled Lecture',
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // トピックタイトル
            Text(
              segment.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            
            // Markdown本文
            MarkdownBody(
              data: markdownContent.toString(),
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                h1: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                h2: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
                blockquote: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                blockquoteDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
                ),
              ),
            ),
            const SizedBox(height: 80), // 下部余白
          ],
        ),
      ),
    );
  }
}