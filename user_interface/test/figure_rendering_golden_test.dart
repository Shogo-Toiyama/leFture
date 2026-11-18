import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

// 英語と日本語の両方の字形を持つmacOSのフォント。Arial.ttfには日本語が無く、□になる。
// ゴールデン画像はこのフォントで作っているので、無い環境(Linux等)では比較せずスキップする。
final _fontFile = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontMissing = !_fontFile.existsSync();

  setUpAll(() async {
    final fontFile = _fontFile;
    if (fontFile.existsSync()) {
      final fontData = fontFile.readAsBytesSync().buffer.asByteData();
      // HTMLのCSSが指定する名前すべてに同じフォントを当てる。
      // 'FlutterTest'は名前の無い文字(SVGの<text>など)に使われるテスト用フォントで、
      // そのままだと字形がすべて黒い四角になる。
      for (final family in [
        'FlutterTest',
        'Roboto',
        'Arial',
        'Helvetica',
        'Helvetica Neue',
        'Segoe UI',
        'sans-serif',
        'system-ui',
        '-apple-system',
        'BlinkMacSystemFont',
        'Hiragino Sans',
        'Hiragino Kaku Gothic ProN',
        'Noto Sans JP',
        'Yu Gothic',
      ]) {
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
    testWidgets('Render ${tc['name']} with HtmlWidget', skip: fontMissing, (tester) async {
      final file = File(tc['path']!);
      if (!file.existsSync()) {
        fail('File not found: ${file.path}');
      }
      // SVGの<text>はフォント名を持たず、fontFamily: nullのまま描かれる。実機では
      // 端末のシステムフォントになるが、テストではエンジン組み込みのテスト用フォント
      // (字形がすべて黒い四角)になり、FontLoaderでは置き換えられない。
      // 実機に近づけるため、テストでだけ<svg>にfont-familyを付ける(子の<text>が引き継ぐ)。
      final htmlContent = file
          .readAsStringSync()
          .replaceAll('<svg ', '<svg font-family="Arial" ');

      // Configure screen size to typical mobile viewport (iPhone 14/15 size: 400x900)
      await tester.binding.setSurfaceSize(const Size(400, 900));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
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
