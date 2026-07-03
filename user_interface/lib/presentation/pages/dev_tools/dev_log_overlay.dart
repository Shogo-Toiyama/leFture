// presentation/pages/dev_tools/dev_log_overlay.dart
//
// isTestMode時のみ、画面下部に直近のログ(DevLog.lines)を常時表示する
// オーバーレイ。ターミナル/DevToolsが繋がっていない実機単体のテストでも、
// どこで処理が止まっているかをその場で確認できるようにするためのもの。
//
// core/utils/dev_log.dart のバッファ自体はテスト機能に依存しない汎用
// ユーティリティだが、この「常に画面に出す」見た目の部分だけはテスト専用
// なのでdev_tools/に置く。

import 'package:flutter/material.dart';

import '../../../core/utils/dev_log.dart';

class DevLogOverlay extends StatefulWidget {
  const DevLogOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<DevLogOverlay> createState() => _DevLogOverlayState();
}

class _DevLogOverlayState extends State<DevLogOverlay> {
  bool _expanded = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.black.withValues(alpha: 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.bug_report, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Dev Log',
                            style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Icon(
                            _expanded ? Icons.expand_more : Icons.expand_less,
                            color: Colors.greenAccent,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_expanded)
                    SizedBox(
                      height: 200,
                      child: ValueListenableBuilder<List<String>>(
                        valueListenable: DevLog.lines,
                        builder: (context, lines, _) {
                          _scrollToBottomNextFrame();
                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: lines.length,
                            itemBuilder: (context, i) => Text(
                              lines[i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
