import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_chat_sheet.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_page_context.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_sheet_handle.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

import '../../../application/chat/fake_chat_repository.dart';

Map<String, dynamic> threadRow(String id, String? title, String at) => {
  'id': id,
  'title': title,
  'mode': 'chat',
  'context_lecture_id': null,
  'last_message_at': at,
  'created_at': at,
};

void main() {
  late FakeChatRepository repo;
  late AppDatabase db;
  late ProviderContainer container;
  late AppLocalizations l10n;
  var settingsOpened = 0;

  setUp(() {
    repo = FakeChatRepository();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatCacheDriftProvider.overrideWithValue(ChatCacheDrift(db)),
        // プランは読み込めていない扱い(注意書きは出ない)
        creditSummaryProvider.overrideWith(
          (ref) async => throw StateError('offline'),
        ),
      ],
    );
    chatReconnectPollInterval = const Duration(milliseconds: 10);
    settingsOpened = 0;
  });

  tearDown(() async {
    await container.read(chatConversationProvider.notifier).settle();
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester, [int ms = 200]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(Duration(milliseconds: ms));
  }

  late BuildContext homeContext;
  var mainTaps = 0;

  Future<void> openSheet(
    WidgetTester tester, {
    ChatWorld world = ChatWorld.universe,
    String? threadId,
    bool withSettings = false,
  }) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mainTaps = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorObservers: [chatSheetKeeper],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              homeContext = context;
              return Scaffold(
                body: Stack(
                  children: [
                    // メイン画面の上のほう(シートが80%までなら見えている)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: TextButton(
                          onPressed: () => mainTaps++,
                          child: const Text('main'),
                        ),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () => showAiChatSheet(
                          context,
                          world: world,
                          threadId: threadId,
                          onOpenAiSettings: withSettings
                              ? () => settingsOpened++
                              : null,
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    l10n = AppLocalizations.of(tester.element(find.text('open')));
    await tester.tap(find.text('open'));
    // 下から出てくる動きが終わるまで
    await settle(tester, 400);
  }

  /// 画面の使える高さ(上の安全領域なし → 高さ - 8)。
  const available = 900.0 - 8;

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(aiChatSheetFrameKey)).height;

  double fraction(WidgetTester tester) => sheetHeight(tester) / available;

  /// つまみ(シートの一番上)のあたり。
  Offset holder(WidgetTester tester) {
    final top = tester.getTopLeft(find.byKey(aiChatSheetFrameKey)).dy;
    return Offset(215, top + 20);
  }

  /// つまみを持って、素早く(約2500px/秒)上へ / 下へ動かして離す。
  Future<void> fling(WidgetTester tester, String direction) async {
    final sign = direction == 'up' ? -1.0 : 1.0;
    final g = await tester.startGesture(holder(tester));
    for (var i = 1; i <= 6; i++) {
      await g.moveBy(
        Offset(0, sign * 25),
        timeStamp: Duration(milliseconds: 10 * i),
      );
    }
    await g.up(timeStamp: const Duration(milliseconds: 70));
  }

  final conversation = [
    chatRow('U1', 'user', 'What is a heap?', createdAt: '2026-10-18T00:00:01Z'),
    chatRow(
      'A1',
      'assistant',
      'A heap is a tree.',
      createdAt: '2026-10-18T00:00:02Z',
    ),
  ];

  testWidgets('開くと新しい会話の画面で、80%の高さ', (tester) async {
    await openSheet(tester);
    expect(find.text(l10n.aiChatNewConversation), findsWidgets);
    expect(fraction(tester), closeTo(.8, .005));
  });

  testWidgets('80%までは、後ろのメイン画面を触れる', (tester) async {
    await openSheet(tester);
    expect(find.byType(AiChatSheet), findsOneWidget);
    await tester.tap(find.text('main'));
    await tester.pump();
    expect(mainTaps, 1);
    // チャットは開いたまま
    expect(find.byType(AiChatSheet), findsOneWidget);
  });

  testWidgets('つまみを持っている間は、指に合わせて動き、離した高さで止まる', (tester) async {
    await openSheet(tester);
    final start = sheetHeight(tester);
    final gesture = await tester.startGesture(holder(tester));
    await gesture.moveBy(const Offset(0, -10));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    // 動きを待たずに、指の分(下へ100-10=90)だけ小さくなっている
    expect(sheetHeight(tester), closeTo(start - 90, 1));

    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(sheetHeight(tester), closeTo(start - 50, 1));

    // ゆっくり離したら、そこで止まる
    await gesture.up();
    await settle(tester, 400);
    expect(sheetHeight(tester), closeTo(start - 50, 1));
  });

  testWidgets('80%から上へ引き上げても、指から外れずに付いていく(80%で引っかからない)', (tester) async {
    await openSheet(tester);
    final start = sheetHeight(tester);
    final g = await tester.startGesture(holder(tester));
    // 1フレームずつ進めて、80%をまたぐ(後ろの幕が出る)ところを通す
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    expect(sheetHeight(tester), closeTo(start + 80, 1));
    await g.up();
    await settle(tester, 400);
    expect(sheetHeight(tester), closeTo(start + 80, 1));
  });

  testWidgets('100%から下へ素早く払うと、80%をまたいでも閉じる', (tester) async {
    await openSheet(tester);
    await fling(tester, 'up');
    await settle(tester, 400);
    expect(fraction(tester), closeTo(1, .005));
    final g = await tester.startGesture(holder(tester));
    for (var i = 1; i <= 8; i++) {
      await g.moveBy(
        const Offset(0, 30),
        timeStamp: Duration(milliseconds: 10 * i),
      );
      await tester.pump();
    }
    await g.up(timeStamp: const Duration(milliseconds: 90));
    await settle(tester, 400);
    expect(find.byType(AiChatSheet), findsNothing);
  });

  testWidgets('裏のページが変わると、その画面の世界の色に切り替わる', (tester) async {
    await openSheet(tester);
    Color sheetColor() =>
        (tester.widget<DecoratedBox>(find.byKey(aiChatSheetFrameKey)).decoration
                as BoxDecoration)
            .color!;
    expect(sheetColor(), ChatColors.universe.sheet);
    final token = Object();
    container
        .read(chatPageContextStackProvider.notifier)
        .register(token, const ChatPageContext(world: ChatWorld.paper));
    await tester.pump();
    expect(sheetColor(), ChatColors.paper.sheet);
    container.read(chatPageContextStackProvider.notifier).unregister(token);
    await tester.pump();
    expect(sheetColor(), ChatColors.universe.sheet);
  });

  testWidgets('50%でも30%でも、離した位置で止まる', (tester) async {
    await openSheet(tester);
    final startFraction = fraction(tester);
    for (final target in [.5, .3, .65]) {
      final delta = (startFraction - target) * available;
      final now = fraction(tester);
      final move = (now - target) * available;
      final g = await tester.startGesture(holder(tester));
      await g.moveBy(Offset(0, move));
      await g.up();
      await settle(tester, 400);
      expect(fraction(tester), closeTo(target, .01), reason: 'delta $delta');
    }
  });

  testWidgets('80%を超えると、メイン画面は暗くなって触れない。暗いところを押すと30%に下がる', (tester) async {
    await openSheet(tester);
    final g = await tester.startGesture(holder(tester));
    await g.moveBy(const Offset(0, -80));
    await g.up();
    await settle(tester, 400);
    expect(fraction(tester), greaterThan(.85));

    // メイン画面は触れない
    await tester.tap(find.text('main'), warnIfMissed: false);
    await tester.pump();
    expect(mainTaps, 0);

    // 暗いところ(シートの外)を押すと30%まで下がる
    await tester.tapAt(const Offset(215, 20));
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.3, .005));
    // 30%になれば、メイン画面をまた触れる
    await tester.tap(find.text('main'));
    await tester.pump();
    expect(mainTaps, 1);
  });

  testWidgets('つまみをタップ: 80%なら30%、30%なら80%', (tester) async {
    await openSheet(tester);
    await tester.tapAt(holder(tester));
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.3, .005));
    await tester.tapAt(holder(tester));
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.8, .005));
  });

  testWidgets('50%より少し高い(55%)ところからのタップは30%に下がる', (tester) async {
    await openSheet(tester);
    final g = await tester.startGesture(holder(tester));
    await g.moveBy(Offset(0, (fraction(tester) - .55) * available));
    await g.up();
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.55, .01));
    await tester.tapAt(holder(tester));
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.3, .005));
  });

  testWidgets('15%より下まで下げて離すと閉じる', (tester) async {
    await openSheet(tester);
    final g = await tester.startGesture(holder(tester));
    await g.moveBy(Offset(0, (fraction(tester) - .1) * available));
    await g.up();
    await settle(tester, 400);
    expect(find.byType(AiChatSheet), findsNothing);
  });

  testWidgets('ヘッダーより低くまで下げても、はみ出さない(つまみとヘッダーだけが見える)', (tester) async {
    await openSheet(tester);
    final g = await tester.startGesture(holder(tester));
    await g.moveBy(Offset(0, (fraction(tester) - .03) * available));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(fraction(tester), closeTo(.03, .01));
    await g.up();
    await settle(tester, 400);
  });

  testWidgets('15%より上で離したら閉じない', (tester) async {
    await openSheet(tester);
    final g = await tester.startGesture(holder(tester));
    await g.moveBy(Offset(0, (fraction(tester) - .2) * available));
    await g.up();
    await settle(tester, 400);
    expect(find.byType(AiChatSheet), findsOneWidget);
    expect(fraction(tester), closeTo(.2, .01));
  });

  testWidgets('素早く上へスワイプしたら100%', (tester) async {
    await openSheet(tester);
    await fling(tester, 'up');
    await settle(tester, 500);
    expect(fraction(tester), closeTo(1.0, .005));
  });

  testWidgets('素早く下へスワイプしたら閉じる。100%からでも閉じる', (tester) async {
    await openSheet(tester);
    await fling(tester, 'down');
    await settle(tester, 500);
    expect(find.byType(AiChatSheet), findsNothing);

    // 100%まで上げてから、素早く下へ
    await tester.tap(find.text('open'));
    await settle(tester, 400);
    await fling(tester, 'up');
    await settle(tester, 500);
    expect(fraction(tester), closeTo(1.0, .005));
    await fling(tester, 'down');
    await settle(tester, 500);
    expect(find.byType(AiChatSheet), findsNothing);
  });

  testWidgets('×で閉じる。閉じたあとはメイン画面を触れる', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byTooltip(l10n.aiChatClose));
    await settle(tester, 400);
    expect(find.byType(AiChatSheet), findsNothing);
    await tester.tap(find.text('main'));
    expect(mainTaps, 1);
  });

  testWidgets('キーボードが出たら、その上いっぱいまで広がる', (tester) async {
    await openSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester, 300);
    final rect = tester.getRect(find.byKey(aiChatSheetFrameKey));
    expect(rect.bottom, closeTo(900 - 300, .5));
    expect(rect.top, closeTo(8, .5));
  });

  testWidgets('開いているときにもう一度開くと、重ねずに選択だけが足される', (tester) async {
    await openSheet(tester);
    unawaited(
      showAiChatSheet(
        homeContext,
        world: ChatWorld.universe,
        selection: const ChatSelection(text: 'a binary heap'),
      ),
    );
    await settle(tester, 300);
    expect(find.byType(AiChatSheet), findsOneWidget);
    expect(find.text('a binary heap'), findsOneWidget);
  });

  testWidgets('低く下げていた(30%)ところに足されたら、入力欄が見える高さ(80%)まで上がる', (tester) async {
    await openSheet(tester);
    await tester.tapAt(holder(tester));
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.3, .005));
    unawaited(
      showAiChatSheet(
        homeContext,
        world: ChatWorld.universe,
        selection: const ChatSelection(text: 'x'),
      ),
    );
    await settle(tester, 400);
    expect(fraction(tester), closeTo(.8, .005));
  });

  testWidgets('別のページを開いても、チャットは最上位に残る', (tester) async {
    await openSheet(tester);
    unawaited(
      Navigator.of(homeContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('next page'))),
        ),
      ),
    );
    await settle(tester, 500);
    expect(find.text('next page'), findsOneWidget);
    expect(find.byType(AiChatSheet), findsOneWidget);
    // チャットの上にページが重なっていない(チャットのボタンを押せる)
    expect(
      find.byTooltip(l10n.aiChatClose).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('チャットから開いたシート(出典など)は、チャットより上に出る', (tester) async {
    await openSheet(tester);
    unawaited(
      showModalBottomSheet<void>(
        context: homeContext,
        builder: (_) => const SizedBox(height: 200, child: Text('popup')),
      ),
    );
    await settle(tester, 500);
    expect(find.text('popup').hitTestable(), findsOneWidget);
  });

  testWidgets('履歴を開いて会話を選ぶと、その会話に切り替わる', (tester) async {
    repo.threadRows = [
      threadRow('T1', 'Heaps', '2026-10-18T00:00:02Z'),
      threadRow('T2', null, '2026-10-17T00:00:02Z'),
    ];
    repo.serverRows['T1'] = conversation;
    await openSheet(tester);
    await tester.tap(find.byTooltip(l10n.aiChatHistory));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.text(l10n.aiChatHistory), findsWidgets);
    expect(find.text('Heaps'), findsOneWidget);
    expect(find.text(l10n.aiChatThreadUntitled), findsOneWidget);

    await tester.tap(find.text('Heaps'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    expect(find.text('A heap is a tree.'), findsOneWidget);
    expect(container.read(chatConversationProvider).threadId, 'T1');
    // ヘッダーには会話の名前が出る(「新しい会話」ではない)
    expect(find.text('Heaps'), findsOneWidget);
    expect(find.text(l10n.aiChatNewConversation), findsNothing);
  });

  testWidgets('続きの会話で開くと、ヘッダーに会話の名前が出る', (tester) async {
    repo.threadRows = [threadRow('T1', 'Heaps', '2026-10-18T00:00:02Z')];
    repo.serverRows['T1'] = conversation;
    await openSheet(tester, threadId: 'T1');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.text('A heap is a tree.'), findsOneWidget);
    expect(find.text('Heaps'), findsOneWidget);
  });

  testWidgets('長い会話を開くと、最初から最新の発言(下端)が見えている', (tester) async {
    repo.serverRows['T1'] = [
      for (var i = 0; i < 30; i++)
        chatRow(
          '${i.isEven ? 'U' : 'A'}$i',
          i.isEven ? 'user' : 'assistant',
          'message number $i',
          createdAt: '2026-10-18T00:00:${(i + 10).toString().padLeft(2, '0')}Z',
        ),
    ];
    await openSheet(tester, threadId: 'T1');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('message number 29'), findsOneWidget);
    expect(find.text('message number 0'), findsNothing);
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(list.position.pixels, closeTo(list.position.maxScrollExtent, 1));

    // シートを引き上げても、下端(最新の発言)のまま
    final g = await tester.startGesture(holder(tester));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -25));
      await tester.pump();
    }
    await g.up();
    await settle(tester, 400);
    expect(find.text('message number 29'), findsOneWidget);
    expect(list.position.pixels, closeTo(list.position.maxScrollExtent, 1));
  });

  testWidgets('履歴で名前を変えて、削除できる', (tester) async {
    repo.threadRows = [threadRow('T1', 'Heaps', '2026-10-18T00:00:02Z')];
    await openSheet(tester);
    await tester.tap(find.byTooltip(l10n.aiChatHistory));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);

    await tester.tap(find.byTooltip(l10n.aiChatRename));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Priority queues');
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    expect(repo.renamedThreads, [('T1', 'Priority queues')]);

    await tester.tap(find.byTooltip(l10n.aiChatDelete));
    await settle(tester);
    expect(find.text(l10n.aiChatDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.aiChatDelete).last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    expect(repo.deletedThreads, ['T1']);
  });

  testWidgets('「新しい会話」で、今の会話が空に戻る', (tester) async {
    repo.serverRows['T1'] = conversation;
    await openSheet(tester, threadId: 'T1');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    expect(find.text('A heap is a tree.'), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.aiChatNewConversation));
    await settle(tester);
    expect(find.text('A heap is a tree.'), findsNothing);
    expect(container.read(chatConversationProvider).threadId, isNull);
  });

  testWidgets('出典を押すと抜粋のシートが出る(講義へ行くボタンつき)', (tester) async {
    final row = chatRow(
      'A1',
      'assistant',
      'Heaps are trees⟦1⟧',
      createdAt: '2026-10-18T00:00:02Z',
    );
    row['citations'] = [
      {
        'n': 1,
        'source_type': 'deep_note',
        'label': 'CS 161 / Lecture 7 / Deep Note: Heaps',
        'lecture_id': 'L1',
        'snippet': 'A heap keeps the smallest item on top.',
      },
    ];
    repo.serverRows['T1'] = [
      chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
      row,
    ];
    await openSheet(tester, threadId: 'T1');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    await tester.tap(find.text('Heaps'));
    await settle(tester);
    expect(find.text('A heap keeps the smallest item on top.'), findsOneWidget);
    // 出典のシートはチャットより上に出ていて、押せる
    expect(
      find.text(l10n.aiChatOpenInLecture).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('AIの設定のボタンは、いつも出る(入口が渡されなければ設定のシートを開く)', (tester) async {
    await openSheet(tester);
    expect(find.byTooltip(l10n.aiSettingsButton), findsOneWidget);
  });

  testWidgets('AIの設定のボタンを押すと、入口が呼ばれる', (tester) async {
    await openSheet(tester, withSettings: true);
    await tester.tap(find.byTooltip(l10n.aiSettingsButton));
    expect(settingsOpened, 1);
  });

  testWidgets('紙の画面の世界でも開く', (tester) async {
    await openSheet(tester, world: ChatWorld.paper);
    expect(find.byType(AiChatSheet), findsOneWidget);
  });
}
