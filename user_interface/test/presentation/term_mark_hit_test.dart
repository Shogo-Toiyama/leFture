import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/term_glossary.dart';
import 'package:lefture/domain/entities/keyword.dart';
import 'package:lefture/presentation/widgets/markdown_annotation_builder.dart';

void main() {
  testWidgets('hitsTermMark is true only on a term mark', (tester) async {
    final glossary = buildTermGlossary([
      Keyword(
        id: 'k1',
        topicNumber: 1,
        keyword: 'Stack (stack)',
        definition: 'def',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]);
    TermEntry? tapped;
    final builder = MarkdownAnnotationBuilder(
      annotations: const [],
      terms: glossary,
      onTermTap: (e) => tapped = e,
    );
    addTearDown(builder.dispose);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return Align(
                alignment: Alignment.topLeft,
                child: MarkdownBody(
                  data: 'The stack grows down and nothing else matters here',
                  builders: annotationMarkdownBuilders(builder),
                ),
              );
            },
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final origin = paragraph.localToGlobal(Offset.zero);
    Offset at(int index) {
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          )
          .first;
      return origin + box.toRect().center;
    }

    // "stack" starts at index 4; "nothing" at 21.
    expect(hitsTermMark(ctx, at(5)), isTrue);
    expect(hitsTermMark(ctx, at(22)), isFalse);

    await tester.tapAt(at(5));
    expect(tapped?.id, 'k1');
  });
}
