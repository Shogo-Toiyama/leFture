import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:lefture/domain/entities/deep_note_figure.dart';

/// 図解のHTMLをWebKitで事前に読み込み、正確な高さを測定して保持するプリローダー。
class DeepNoteFigurePreloader {
  DeepNoteFigurePreloader._();
  static final DeepNoteFigurePreloader instance = DeepNoteFigurePreloader._();

  final Map<String, WebViewController> _controllers = {};
  final Map<String, double> _cachedHeights = {};
  final Map<String, ValueNotifier<double>> _heightNotifiers = {};
  final Set<String> _loadingIds = {};

  ValueNotifier<double> getHeightNotifier(String figureId, double initialHeight) {
    return _heightNotifiers.putIfAbsent(
      figureId,
      () => ValueNotifier<double>(_cachedHeights[figureId] ?? initialHeight),
    );
  }

  double? getCachedHeight(String figureId) => _cachedHeights[figureId];

  WebViewController? getController(String figureId) => _controllers[figureId];

  /// 図解リストを一括プリロードする
  void preloadAll(List<DeepNoteFigure> figures) {
    if (kIsWeb) return;
    for (final figure in figures) {
      preload(figure);
    }
  }

  /// 単一の図解を事前読み込み
  void preload(DeepNoteFigure figure) {
    if (kIsWeb) return;
    if (_controllers.containsKey(figure.id) || _loadingIds.contains(figure.id)) {
      return;
    }

    _loadingIds.add(figure.id);

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel(
          'HeightReporter',
          onMessageReceived: (JavaScriptMessage message) {
            final h = double.tryParse(message.message);
            // 異常値(画面全体のviewport巨大値など)を防止し、妥当な高さのみ採用
            if (h != null && h > 30 && h < 3000) {
              final finalHeight = h;
              _cachedHeights[figure.id] = finalHeight;
              if (_heightNotifiers.containsKey(figure.id)) {
                _heightNotifiers[figure.id]!.value = finalHeight;
              }
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              measureHeight(figure.id);
            },
          ),
        );

      final fullHtml = wrapHtml(figure.htmlContent);
      controller.loadHtmlString(fullHtml);
      _controllers[figure.id] = controller;
    } catch (_) {
      _loadingIds.remove(figure.id);
    }
  }

  /// カード要素（.deepnote-figure-card）の真の高さを測定してFlutterへ通知
  void measureHeight(String figureId) {
    final controller = _controllers[figureId];
    controller?.runJavaScript('''
      (function() {
        function send() {
          // documentElementではなく、カード本体の要素から正確な高さを取得
          var el = document.querySelector('.deepnote-figure-card') || 
                   document.body.firstElementChild || 
                   document.body;
          if (!el) return;
          var rect = el.getBoundingClientRect();
          var h = Math.ceil(rect.height || el.offsetHeight || 0);
          if (h > 30 && window.HeightReporter) {
            window.HeightReporter.postMessage(h.toString());
          }
        }
        send();
        setTimeout(send, 100);
        setTimeout(send, 300);
        setTimeout(send, 700);
        if (window.ResizeObserver) {
          var target = document.querySelector('.deepnote-figure-card') || document.body;
          new ResizeObserver(send).observe(target);
        }
      })();
    ''');
  }

  static String wrapHtml(String rawHtml) {
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      width: 100%;
      overflow: hidden;
      -webkit-user-select: none;
      user-select: none;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    .deepnote-figure-card {
      margin: 0 auto !important; /* 余計な外側縦マージンによる白い余白を排除 */
    }
    svg {
      max-width: 100%;
      height: auto;
      display: block;
      margin: 0 auto;
    }
  </style>
</head>
<body>
  $rawHtml
</body>
</html>''';
  }

  /// 講義を閉じた際などにキャッシュをクリア
  void clear() {
    _controllers.clear();
    _cachedHeights.clear();
    _heightNotifiers.clear();
    _loadingIds.clear();
  }
}

/// DeepNotesの図解（HTML/SVG）を表示するカードウィジェット。
///
/// 外側の余計な二重枠線や「図解1」などのチップ・タイトルを完全撤廃し、
/// 生成された図解そのものを余白なく美しくレンダリングする。
class DeepNoteFigureCard extends StatefulWidget {
  const DeepNoteFigureCard({
    super.key,
    required this.figure,
  });

  final DeepNoteFigure figure;

  @override
  State<DeepNoteFigureCard> createState() => _DeepNoteFigureCardState();
}

class _DeepNoteFigureCardState extends State<DeepNoteFigureCard> {
  late final ValueNotifier<double> _heightNotifier;
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final preloader = DeepNoteFigurePreloader.instance;
    preloader.preload(widget.figure);
    // 初期値は控えめにして白い巨大な余白の発生を防止
    _heightNotifier = preloader.getHeightNotifier(widget.figure.id, 200);
    _controller = preloader.getController(widget.figure.id);

    // 画面にウィジェットがマウントされた直後、実画面幅で再度正確に高さを測定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        preloader.measureHeight(widget.figure.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _controller == null) {
      return const SizedBox.shrink();
    }

    // アノテーション（文字ハイライト/メモ）の文字座標系に一切干渉させない
    return SelectionContainer.disabled(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        width: double.infinity,
        child: ValueListenableBuilder<double>(
          valueListenable: _heightNotifier,
          builder: (context, height, _) {
            return SizedBox(
              height: height,
              child: WebViewWidget(
                controller: _controller!,
                // スクロールジェスチャーを親のScrollViewへ100%透過させ、スクロールの重さ・引っかかりを排除
                gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              ),
            );
          },
        ),
      ),
    );
  }
}

/// flutter_markdown 内の `![figure](figure:<index>)` タグを検出し、
/// 該当する [DeepNoteFigure] を [DeepNoteFigureCard] としてレンダリングするビルダー。
class DeepNoteFigureElementBuilder extends MarkdownElementBuilder {
  DeepNoteFigureElementBuilder({
    required this.figures,
  });

  final List<DeepNoteFigure> figures;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final src = element.attributes['src'] ?? '';
    if (src.startsWith('figure:')) {
      final index = int.tryParse(src.replaceFirst('figure:', '')) ?? 0;
      final figure = figures.cast<DeepNoteFigure?>().firstWhere(
            (f) => f?.figureIndex == index,
            orElse: () => null,
          );
      if (figure != null) {
        return DeepNoteFigureCard(
          key: ValueKey('figure_${figure.id}'),
          figure: figure,
        );
      }
      return const SizedBox.shrink();
    }
    return null;
  }
}
