import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontFile = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (fontFile.existsSync()) {
      final fontData = fontFile.readAsBytesSync().buffer.asByteData();
      for (final family in ['Roboto', 'Arial', 'sans-serif', '-apple-system', 'BlinkMacSystemFont']) {
        final loader = FontLoader(family)..addFont(Future.value(fontData));
        await loader.load();
      }
    }
  });

  final baseDir = Directory.current.parent;
  final resultsDir = Directory('${baseDir.path}/contents_generation/test_codes/deepnote_diagram_test/results');

  // Test targets
  final testCases = [
    {
      'name': 'run2_case1_moores_law',
      'path': '${resultsDir.path}/run_2_haiku_low_mobile_focused/case_1_Moore\'s_La_claude_haiku_5_5.html',
    },
    {
      'name': 'run2_case2_gpt_device',
      'path': '${resultsDir.path}/run_2_haiku_low_mobile_focused/case_2_GPT_Device_claude_haiku_5_5.html',
    },
    {
      'name': 'run2_case4_action_potential',
      'path': '${resultsDir.path}/run_2_haiku_low_mobile_focused/case_4_活動電位のフェーズ_claude_haiku_5_5.html',
    },
    {
      'name': 'run7_case1_cache_hierarchy',
      'path': '${resultsDir.path}/run_7_haiku_reasoning_low_no_cache/case_1_claude_haiku_5_5.html',
    },
    {
      'name': 'run7_case3_distributed_system',
      'path': '${resultsDir.path}/run_7_haiku_reasoning_low_no_cache/case_3_claude_haiku_5_5.html',
    },
  ];

  for (final tc in testCases) {
    testWidgets('Render ${tc['name']} with HtmlWidget', (tester) async {
      final file = File(tc['path']!);
      if (!file.existsSync()) {
        fail('File not found: ${file.path}');
      }
      final htmlContent = file.readAsStringSync();

      // Configure screen size to typical mobile viewport (iPhone 14/15 size: 400x900)
      await tester.binding.setSurfaceSize(const Size(400, 900));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Arial',
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: HtmlWidget(
                  htmlContent,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Output golden image
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${tc['name']}.png'),
      );
    });
  }
}
