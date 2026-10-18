// SelectionAreaは、タッチ端末では横ドラッグを「ドラッグして選択」に使う認識器を
// 内蔵しており、iOS以外ではそれが即座にジェスチャーアリーナを勝ち取る。祖先の
// 横スワイプと同居させたときにスワイプ側が勝てているかは目で見ないと分かりにくい
// ので、機構ごとここで固定しておく。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/presentation/widgets/selection_swipe_priority.dart';

void main() {
  Widget pagerWith(Widget Function(String label) buildPage, PageController c) {
    return MaterialApp(
      home: Scaffold(
        body: PageView(
          controller: c,
          children: [for (final label in ['page-0', 'page-1']) buildPage(label)],
        ),
      ),
    );
  }

  group('SwipePrioritySelectionArea', () {
    testWidgets('本文の上の横スワイプでも祖先のPageViewがめくれる', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        pagerWith(
          (label) =>
              Center(child: SwipePrioritySelectionArea(child: Text(label))),
          controller,
        ),
      );

      // テキストのど真ん中から指を動かす。SelectionAreaに奪われていれば
      // ここでスクロール位置は1pxも動かない。
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('page-0')),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-60, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.position.pixels, greaterThan(0.0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });

    testWidgets('長押しではめくれず、コピー可能な選択が始まる', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        pagerWith(
          (label) =>
              Center(child: SwipePrioritySelectionArea(child: Text(label))),
          controller,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('page-0')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.page, 0);
      // 標準の選択ツールバー(コピー等)が出ていれば、選択はSelectionAreaが取れている。
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });

  group('SwipePrioritySelectionArea の「質問」', () {
    testWidgets('メニューの先頭に「質問」が出て、選んだ文章が渡る', (tester) async {
      final asked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwipePrioritySelectionArea(
                askLabel: 'Ask',
                onAsk: asked.add,
                child: const Text('heaps are trees'),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('heaps are trees')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Ask'), findsOneWidget);
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      expect(asked.single, isNotEmpty);
      expect('heaps are trees', contains(asked.single));
    });

    testWidgets('渡さなければ、標準のメニューのまま', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwipePrioritySelectionArea(child: Text('heaps are trees')),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('heaps are trees')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Ask'), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });

  group('SelectionAwareHorizontalDragRecognizer', () {
    test('shouldDeferがtrueの間はポインタを受け取らない', () {
      var defer = false;
      final recognizer = SelectionAwareHorizontalDragRecognizer(
        shouldDefer: () => defer,
      )..onStart = (_) {};
      addTearDown(recognizer.dispose);

      const event = PointerDownEvent(pointer: 1);
      expect(recognizer.isPointerAllowed(event), isTrue);

      defer = true;
      expect(recognizer.isPointerAllowed(event), isFalse);
    });

    // レビューカードはドラッグが始まると本文のSelectionAreaを一旦外す(遷移アニメ
    // 中の二重マウントを避けるため)。認識器をRawGestureDetectorに持たせると
    // そこで破棄されてスワイプが即死するので、ページ側で保持してListenerから
    // addPointerしている。その不変条件を固定する。
    testWidgets('SelectionAreaが外れてもページ側が持つ認識器はドラッグを追い続ける', (
      tester,
    ) async {
      var dragging = false;
      var updates = 0;
      var cancelled = false;

      final recognizer = SelectionAwareHorizontalDragRecognizer(
        shouldDefer: () => false,
      );
      addTearDown(recognizer.dispose);

      late StateSetter setOuterState;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuterState = setState;
                recognizer
                  ..onStart = (_) {
                    dragging = true;
                    // 実アプリと同じく、ドラッグ開始でSelectionAreaを外す。
                    setOuterState(() {});
                  }
                  ..onUpdate = (_) {
                    updates++;
                  }
                  ..onCancel = () => cancelled = true;

                final body = Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: recognizer.addPointer,
                  child: const Center(child: Text('body')),
                );
                return dragging
                    ? body
                    : SelectionArea(child: body);
              },
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('body')),
      );
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dragging, isTrue, reason: 'SelectionAreaより先に勝てていない');
      expect(updates, greaterThan(1), reason: 'Widgetが外れた時点で追跡が切れている');
      expect(cancelled, isFalse);
    });
  });
}
