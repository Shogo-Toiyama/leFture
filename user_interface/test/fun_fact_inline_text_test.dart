import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/fun_fact_inline_text.dart';

void main() {
  group('FunFactInlineText Widget', () {
    testWidgets('renders inline chips for web citations', (tester) async {
      final sources = ['https://example.com/source1', 'https://example.com/source2'];
      final text = 'Brisket stalls at 160°F⟦1⟧ due to cooling⟦2⟧.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FunFactInlineText(
              text: text,
              sources: sources,
            ),
          ),
        ),
      );

      // Verify that chips with '1' and '2' are found in the tree
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
    });

    testWidgets('handles text without citations gracefully', (tester) async {
      final text = 'No citations in this text.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FunFactInlineText(
              text: text,
              sources: const [],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.open_in_new), findsNothing);
      expect(find.text('No citations in this text.'), findsOneWidget);
    });
  });
}
