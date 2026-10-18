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

  Future<void> openSheet(
    WidgetTester tester, {
    ChatWorld world = ChatWorld.universe,
    String? threadId,
    bool withSettings = false,
  }) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
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
            ),
          ),
        ),
      ),
    );
    l10n = AppLocalizations.of(tester.element(find.byType(TextButton)));
    await tester.tap(find.text('open'));
    // 下から出てくる動きが終わるまで
    await settle(tester, 400);
  }

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AnimatedContainer).first).height;

  final conversation = [
    chatRow('U1', 'user', 'What is a heap?', createdAt: '2026-10-18T00:00:01Z'),
    chatRow(
      'A1',
      'assistant',
      'A heap is a tree.',
      createdAt: '2026-10-18T00:00:02Z',
    ),
  ];

  testWidgets('開くと新しい会話の画面で、半分の高さ。つまみを押すと全画面になる', (tester) async {
    await openSheet(tester);
    expect(find.text(l10n.aiChatNewConversation), findsWidgets);
    final half = sheetHeight(tester);
    await tester.tapAt(Offset(215, 900 - half + 14));
    await settle(tester, 300);
    expect(sheetHeight(tester), greaterThan(half));
  });

  testWidgets('上へ引き上げると全画面、下へ引くと半分に戻り、もう一度引くと閉じる', (tester) async {
    await openSheet(tester);
    final half = sheetHeight(tester);
    final grab = Offset(215, 900 - half + 14);
    await tester.dragFrom(grab, const Offset(0, -120));
    await settle(tester, 300);
    final full = sheetHeight(tester);
    expect(full, greaterThan(half));

    await tester.dragFrom(Offset(215, 900 - full + 14), const Offset(0, 120));
    await settle(tester, 300);
    expect(sheetHeight(tester), closeTo(half, 1));

    await tester.dragFrom(Offset(215, 900 - half + 14), const Offset(0, 120));
    await settle(tester, 400);
    expect(find.byType(AiChatSheet), findsNothing);
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
    expect(find.text(l10n.aiChatOpenInLecture), findsOneWidget);
  });

  testWidgets('AIの設定のボタンは、入口が渡されたときだけ出る', (tester) async {
    await openSheet(tester);
    expect(find.byTooltip(l10n.aiSettingsButton), findsNothing);
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
