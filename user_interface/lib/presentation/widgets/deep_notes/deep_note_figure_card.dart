import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:lefture/domain/entities/deep_note_figure.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

enum FigureRenderMode {
  both,
  webViewOnly,
  htmlWidgetOnly,
}

/// DeepNotesの図解（HTML/SVG）を表示するカードウィジェット。
///
/// 検証・比較のため、[flutter_widget_from_html] と [webview_flutter] の2方式を
/// 上下に並べて表示し、トグルで切り替えることも可能。
/// 本文テキストの選択・アノテーション座標系を壊さないよう、全体が
/// [SelectionContainer.disabled] で完全に保護されている。
class DeepNoteFigureCard extends StatefulWidget {
  const DeepNoteFigureCard({
    super.key,
    required this.figure,
    this.initialMode = FigureRenderMode.both,
  });

  final DeepNoteFigure figure;
  final FigureRenderMode initialMode;

  @override
  State<DeepNoteFigureCard> createState() => _DeepNoteFigureCardState();
}

class _DeepNoteFigureCardState extends State<DeepNoteFigureCard> {
  late FigureRenderMode _mode;
  WebViewController? _webViewController;
  double _webViewHeight = 220;
  bool _isWebViewReady = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _initWebView();
  }

  void _initWebView() {
    // Web環境や一部テスト環境ではwebview_flutterが未対応の場合があるため保護
    if (kIsWeb) return;

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel(
          'HeightReporter',
          onMessageReceived: (JavaScriptMessage message) {
            final h = double.tryParse(message.message);
            if (h != null && h > 30 && mounted) {
              setState(() {
                _webViewHeight = h + 16;
                _isWebViewReady = true;
              });
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              _reportHeight();
            },
          ),
        );

      final fullHtml = _wrapHtml(widget.figure.htmlContent);
      controller.loadHtmlString(fullHtml);
      _webViewController = controller;
    } catch (_) {
      // WebView初期化不可環境ではHtmlWidgetフォールバック
    }
  }

  void _reportHeight() {
    _webViewController?.runJavaScript('''
      (function() {
        function send() {
          var h = Math.max(
            document.body.scrollHeight,
            document.documentElement.scrollHeight,
            document.body.offsetHeight
          );
          if (window.HeightReporter) {
            window.HeightReporter.postMessage(h.toString());
          }
        }
        send();
        setTimeout(send, 300);
        setTimeout(send, 800);
        if (window.ResizeObserver) {
          new ResizeObserver(send).observe(document.body);
        }
      })();
    ''');
  }

  String _wrapHtml(String rawHtml) {
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
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
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

  @override
  Widget build(BuildContext context) {
    // アノテーション（文字ハイライト/メモ）の文字座標系に一切干渉させない
    return SelectionContainer.disabled(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー: タイトル & 比較トグル
            _buildHeader(context),

            // レンダリング部
            if (_mode == FigureRenderMode.both) ...[
              _buildSection(
                title: 'A. flutter_widget_from_html',
                subtitle: 'ネイティブFlutterウィジェット描画（CSS/SVG marker一部制限）',
                badgeColor: Colors.amber.shade700,
                child: _buildHtmlWidget(),
              ),
              const Divider(height: 1, thickness: 1.5, color: Color(0xFFE5E7EB)),
              _buildSection(
                title: 'B. webview_flutter',
                subtitle: '内蔵WebKitブラウザ完全描画（CSS/SVG marker 100%忠実再現）',
                badgeColor: Colors.blue.shade700,
                child: _buildWebView(),
              ),
            ] else if (_mode == FigureRenderMode.htmlWidgetOnly) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildHtmlWidget(),
              ),
            ] else if (_mode == FigureRenderMode.webViewOnly) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildWebView(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.starGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '図解 #${widget.figure.figureIndex + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB48A26),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.figure.title.isNotEmpty ? widget.figure.title : '図解',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 比較表示モード切替タブ
          Row(
            children: [
              _buildModeChip('上下比較', FigureRenderMode.both),
              const SizedBox(width: 6),
              _buildModeChip('WebViewのみ', FigureRenderMode.webViewOnly),
              const SizedBox(width: 6),
              _buildModeChip('HtmlWidgetのみ', FigureRenderMode.htmlWidgetOnly),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, FigureRenderMode mode) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : const Color(0xFF4B5563),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required Color badgeColor,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildHtmlWidget() {
    return HtmlWidget(
      widget.figure.htmlContent,
      renderMode: RenderMode.column,
      textStyle: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildWebView() {
    if (_webViewController == null) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        color: const Color(0xFFF9FAFB),
        child: const Text(
          'WebViewはモバイル実機(iOS/Android)で動作します',
          style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
        ),
      );
    }

    return SizedBox(
      height: _webViewHeight,
      child: Stack(
        children: [
          WebViewWidget(controller: _webViewController!),
          if (!_isWebViewReady)
            Container(
              color: Colors.white.withValues(alpha: 0.6),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// flutter_markdown 内の `![figure](figure:<index>)` タグを検出し、
/// 該当する [DeepNoteFigure] を [DeepNoteFigureCard] としてレンダリングするビルダー。
class DeepNoteFigureElementBuilder extends MarkdownElementBuilder {
  DeepNoteFigureElementBuilder({
    required this.figures,
    this.initialMode = FigureRenderMode.both,
  });

  final List<DeepNoteFigure> figures;
  final FigureRenderMode initialMode;

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
          initialMode: initialMode,
        );
      }
      return const SizedBox.shrink();
    }
    return null;
  }
}

