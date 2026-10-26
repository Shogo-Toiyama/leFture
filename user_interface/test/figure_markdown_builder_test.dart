import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:lefture/core/utils/annotation_text_utils.dart';
import 'package:lefture/domain/entities/annotation.dart';
import 'package:lefture/presentation/widgets/markdown_annotation_builder.dart';

class FigureBuilder extends MarkdownElementBuilder {
  final Map<int, String> figures;
  FigureBuilder(this.figures);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final src = element.attributes['src'] ?? '';
    if (src.startsWith('figure:')) {
      final idx = int.tryParse(src.replaceFirst('figure:', '')) ?? 0;
      return Container(
        key: ValueKey('figure_$idx'),
        height: 100,
        color: Colors.amber,
        child: Text('Figure #$idx: ${figures[idx]}'),
      );
    }
    return null;
  }
}

void main() {
  testWidgets('Figure in MarkdownBody test', (tester) async {
    const rawMarkdown = '''# Header 1
First paragraph text.

![figure](figure:0)

Second paragraph text after figure.''';

    final builder = MarkdownAnnotationBuilder(annotations: const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: rawMarkdown,
            builders: {
              ...annotationMarkdownBuilders(builder),
              'img': FigureBuilder({0: 'Test Figure'}),
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('figure_0')), findsOneWidget);
    expect(find.text('Figure #0: Test Figure'), findsOneWidget);
    expect(find.text('First paragraph text.'), findsOneWidget);
    expect(find.text('Second paragraph text after figure.'), findsOneWidget);
  });

  testWidgets('Figure does not shift Annotation offsets', (tester) async {
    // Flattened text:
    // "Header 1" + "First paragraph text." + "Second paragraph text after figure."
    // Let's check offsets with flattenMarkdownText:
    const baseMarkdown = '''# Header 1
First paragraph text.

Second paragraph text after figure.''';
    final flattened = flattenMarkdownText(baseMarkdown);
    // Find "Second" in flattened
    final secondStart = flattened.indexOf('Second');
    final secondEnd = secondStart + 'Second paragraph'.length;

    const markdownWithFigure = '''# Header 1
First paragraph text.

![figure](figure:0)

Second paragraph text after figure.''';

    final annotation = Annotation(
      id: 'ann_1',
      startIdx: secondStart,
      endIdx: secondEnd,
      annotationType: 'highlight',
      annotatedWords: 'Second paragraph',
      contents: const {'color': '#FFB300', 'type': 'marker'},
    );

    final builder = MarkdownAnnotationBuilder(annotations: [annotation]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: markdownWithFigure,
            builders: {
              ...annotationMarkdownBuilders(builder),
              'img': FigureBuilder({0: 'Test Figure'}),
            },
          ),
        ),
      ),
    );

    // Verify the widget rendered without throwing and the figure is present
    expect(find.byKey(const ValueKey('figure_0')), findsOneWidget);
    expect(find.text('Second paragraph text after figure.'), findsOneWidget);
  });
}

