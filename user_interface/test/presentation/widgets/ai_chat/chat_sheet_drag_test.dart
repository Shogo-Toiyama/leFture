// showChatSheetのdragFromHeaderOnly: シートの中のPDFビューア(や拡大した画像)は
// 一本指のドラッグで動き、シートを動かすのはつまみと見出しだけ。
// 以前はシート全体の縦ドラッグ(18pxで決まる)が、ビューアのパン(36pxで決まる)より
// 先にドラッグを取り、一本指ではPDFをスクロールできなかった。
// pdfrxはテストでは動かない(pdfium)ので、同じジェスチャーの仕組みを持つ
// InteractiveViewer(pdfrxのビューアの元)で確かめる。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';

void main() {
  late TransformationController viewer;

  Future<void> openSheet(WidgetTester tester, {required bool dragFromHeaderOnly}) async {
    viewer = TransformationController();
    addTearDown(viewer.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    showChatSheet<void>(
      context,
      ChatColors.universe,
      (_) => SizedBox(
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ChatSheetHeader(
              colors: ChatColors.universe,
              icon: Icons.description_outlined,
              badge: 'PDF',
              title: 'Doc',
            ),
            Expanded(
              child: InteractiveViewer(
                transformationController: viewer,
                constrained: false,
                child: const SizedBox(
                  width: 800,
                  height: 3000,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
      dragFromHeaderOnly: dragFromHeaderOnly,
    );
    await tester.pumpAndSettle();
  }

  bool sheetIsOpen() => find.text('Doc').evaluate().isNotEmpty;
  double viewerOffsetY() => viewer.value.getTranslation().y;

  group('dragFromHeaderOnly: true', () {
    testWidgets('中身を一本指で上下に動かせて、シートは閉じない', (tester) async {
      await openSheet(tester, dragFromHeaderOnly: true);

      await tester.drag(find.byType(InteractiveViewer), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(viewerOffsetY(), -200);

      await tester.drag(find.byType(InteractiveViewer), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(viewerOffsetY(), -50);
      expect(sheetIsOpen(), isTrue);
    });

    testWidgets('見出しを少し引いて離すと元の位置に戻る', (tester) async {
      await openSheet(tester, dragFromHeaderOnly: true);
      final before = tester.getTopLeft(find.text('Doc'));

      await tester.drag(find.text('Doc'), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(sheetIsOpen(), isTrue);
      expect(tester.getTopLeft(find.text('Doc')), before);
      expect(viewerOffsetY(), 0);
    });

    testWidgets('見出しを大きく引くと閉じる', (tester) async {
      await openSheet(tester, dragFromHeaderOnly: true);
      await tester.drag(find.text('Doc'), const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(sheetIsOpen(), isFalse);
    });

    testWidgets('見出しを下へ払うと閉じる', (tester) async {
      await openSheet(tester, dragFromHeaderOnly: true);
      await tester.fling(find.text('Doc'), const Offset(0, 120), 1500);
      await tester.pumpAndSettle();
      expect(sheetIsOpen(), isFalse);
    });

    testWidgets('つまみを大きく引いても閉じる', (tester) async {
      await openSheet(tester, dragFromHeaderOnly: true);
      // つまみは見出しのすぐ上
      final handle = tester.getTopLeft(find.text('Doc')) - const Offset(0, 30);
      await tester.dragFrom(handle, const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(sheetIsOpen(), isFalse);
    });

    testWidgets('閉じるボタンで閉じる', (tester) async {
      await openSheet(tester, dragFromHeaderOnly: true);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(sheetIsOpen(), isFalse);
    });
  });

  testWidgets('dragFromHeaderOnly: false(既定)では、中身のドラッグもシートが取る', (tester) async {
    await openSheet(tester, dragFromHeaderOnly: false);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(viewerOffsetY(), 0);
  });
}
