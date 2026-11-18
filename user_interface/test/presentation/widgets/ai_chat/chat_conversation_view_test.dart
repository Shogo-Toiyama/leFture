import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer_parts.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_conversation_view.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/selection_floating_menu.dart';

import '../../../application/chat/fake_chat_repository.dart';

const _meta = ChatMetaEvent(
  threadId: 'T1',
  userMessageId: 'U1',
  assistantMessageId: 'A1',
);

void main() {
  late FakeChatRepository repo;
  late AppDatabase db;
  late ProviderContainer container;
  late AppLocalizations l10n;
  var bought = 0;
  var opened = <ChatCitation>[];

  setUp(() {
    repo = FakeChatRepository();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatCacheDriftProvider.overrideWithValue(ChatCacheDrift(db)),
      ],
    );
    chatReconnectPollInterval = const Duration(milliseconds: 10);
    bought = 0;
    opened = [];
  });

  tearDown(() async {
    await container.read(chatConversationProvider.notifier).settle();
    container.dispose();
    await db.close();
  });

  Future<void> pumpView(
    WidgetTester tester, {
    ChatWorld world = ChatWorld.universe,
    String? lectureId,
    ChatSelection? selection,
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
          home: Scaffold(
            body: ChatConversationView(
              world: world,
              lectureId: lectureId,
              lectureTitle: lectureId == null ? null : 'Heaps',
              selection: selection,
              onOpenCitation: (c, _) => opened.add(c),
              onBuyCredits: () => bought++,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    l10n = AppLocalizations.of(
      tester.element(find.byType(ChatConversationView)),
    );
  }

  /// 出発ゲートの動きが止まらないので、pumpAndSettleの代わりに少し進める
  /// (会話を開いたときの、下端へ合わせてから見せる数フレームも含む)。
  Future<void> settle(WidgetTester tester, [int ms = 200]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openThread(
    WidgetTester tester,
    List<Map<String, dynamic>> rows,
  ) async {
    repo.serverRows['T1'] = rows;
    await tester.runAsync(
      () => container.read(chatConversationProvider.notifier).openThread('T1'),
    );
    await settle(tester);
  }

  final conversation = [
    chatRow(
      'U1',
      'user',
      'What is a binary heap?',
      createdAt: '2026-10-18T00:00:01Z',
    ),
    chatRow(
      'A1',
      'assistant',
      'A **binary heap** is a complete tree.',
      createdAt: '2026-10-18T00:00:02Z',
    ),
  ];

  group('出発ゲート', () {
    testWidgets('何も話していないときは、文言と質問の候補が出る', (tester) async {
      await pumpView(tester);
      await settle(tester, 1500);
      expect(find.text(l10n.aiChatEmptyTitle), findsOneWidget);
      expect(find.text(l10n.aiChatEmptySubtitle), findsOneWidget);
      expect(find.text(l10n.aiChatSuggestionLatest), findsOneWidget);
    });

    testWidgets('質問の候補を押すと、入力欄に入る', (tester) async {
      await pumpView(tester);
      await settle(tester, 1500);
      await tester.tap(find.text(l10n.aiChatSuggestionQuiz));
      await settle(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, l10n.aiChatSuggestionQuiz);
    });

    testWidgets('講義を指定していれば、その講義向けの候補になる', (tester) async {
      await pumpView(tester, lectureId: 'L1');
      await settle(tester, 1500);
      expect(find.text(l10n.aiChatSuggestionThisLecture), findsOneWidget);
      expect(find.text(l10n.aiChatSuggestionLatest), findsNothing);
      expect(find.text(l10n.aiChatAttachedLecture('Heaps')), findsOneWidget);
    });

    testWidgets('「Ask」で選んだ文章があれば、それ向けの候補と引用の帯が出る', (tester) async {
      await pumpView(
        tester,
        selection: const ChatSelection(text: 'sift-up swaps with the parent'),
      );
      await settle(tester, 1500);
      expect(find.text(l10n.aiChatSuggestionSelection), findsOneWidget);
      expect(find.text('sift-up swaps with the parent'), findsOneWidget);
    });

    testWidgets('紙の世界でも出る', (tester) async {
      await pumpView(tester, world: ChatWorld.paper);
      await settle(tester, 1500);
      expect(find.text(l10n.aiChatEmptyTitle), findsOneWidget);
    });
  });

  group('会話の表示', () {
    testWidgets('自分の質問は吹き出し、AIの回答は直接書かれる', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      expect(find.text('What is a binary heap?'), findsOneWidget);
      // 回答の本文(太字を含むので、Text.richの中身を探す)
      expect(
        find.textContaining('binary heap', findRichText: true),
        findsWidgets,
      );
      expect(find.text(l10n.aiChatEmptyTitle), findsNothing); // 出発ゲートは消える
    });

    testWidgets('回答の下に、コピー・作り直し・「…」が出る。質問の下にはコピー・編集', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      expect(find.bySemanticsLabel(l10n.aiChatActionCopy), findsNWidgets(2));
      expect(find.bySemanticsLabel(l10n.aiChatActionEdit), findsOneWidget);
      expect(
        find.bySemanticsLabel(l10n.aiChatActionRegenerate),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(l10n.aiChatActionMore), findsOneWidget);
    });

    testWidgets('長い質問は畳まれ、「もっと見る」で開く', (tester) async {
      await pumpView(tester);
      final long = List.generate(30, (i) => 'line ${i + 1}').join('\n');
      await openThread(tester, [
        chatRow('U1', 'user', long, createdAt: '2026-10-18T00:00:01Z'),
        chatRow('A1', 'assistant', 'ok', createdAt: '2026-10-18T00:00:02Z'),
      ]);
      expect(find.text(l10n.aiChatShowMore), findsOneWidget);
      await tester.tap(find.text(l10n.aiChatShowMore));
      await settle(tester);
      expect(find.text(l10n.aiChatShowLess), findsOneWidget);
      await tester.tap(find.text(l10n.aiChatShowLess));
      await settle(tester);
      expect(find.text(l10n.aiChatShowMore), findsOneWidget);
    });

    testWidgets('短い質問は畳まれない', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      expect(find.text(l10n.aiChatShowMore), findsNothing);
    });

    testWidgets('出典のチップを押すと、その出典が開く', (tester) async {
      await pumpView(tester);
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
        },
      ];
      await openThread(tester, [
        chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
        row,
      ]);
      expect(find.text('Heaps'), findsOneWidget); // 短い名前(コース名と「Deep Note:」は外れる)
      await tester.tap(find.text('Heaps'));
      await settle(tester);
      expect(opened.single.ref, '1');
    });

    testWidgets('返答に失敗していたら、メッセージと作り直しが出る', (tester) async {
      await pumpView(tester);
      await openThread(tester, [
        chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
        chatRow(
          'A1',
          'assistant',
          '',
          status: 'error',
          createdAt: '2026-10-18T00:00:02Z',
        ),
      ]);
      expect(find.text(l10n.aiChatReplyFailed), findsOneWidget);
    });

    testWidgets('読み込みに失敗(キャッシュも無い)なら、再読み込みの導線が出る', (tester) async {
      await pumpView(tester);
      repo.serverRows['T1'] = null;
      await tester.runAsync(
        () =>
            container.read(chatConversationProvider.notifier).openThread('T1'),
      );
      await settle(tester);
      expect(find.text(l10n.aiChatLoadFailed), findsOneWidget);
    });
  });

  group('送信', () {
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
    }

    testWidgets('送ると、質問が吹き出しになり、段階の文言と停止ボタンが出る。完了で回答になる', (tester) async {
      await pumpView(tester);
      await type(tester, 'Explain sift-up');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);

      expect(repo.lastRequest!.content, 'Explain sift-up');
      expect(find.text('Explain sift-up'), findsOneWidget);
      expect(find.text(l10n.aiChatStageThinking), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.aiChatStop), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.aiChatSend), findsNothing);

      repo.controller.add(_meta);
      repo.controller.add(
        const ChatStatusEvent(
          stage: ChatStage.searching,
          detail: ['lectures'],
          query: 'sift-up',
        ),
      );
      await settle(tester);
      expect(
        find.text(l10n.aiChatStageSearchingNotesWithQuery('sift-up')),
        findsOneWidget,
      );

      repo.controller.add(const ChatDeltaEvent('It swaps with the parent.'));
      repo.controller.add(
        const ChatDoneEvent(
          status: ChatMessageStatus.complete,
          creditsCharged: 0.4,
        ),
      );
      await repo.controller.close();
      await settle(tester);

      expect(
        find.textContaining('It swaps with the parent.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(l10n.aiChatStageSearchingNotesWithQuery('sift-up')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(l10n.aiChatSend),
        findsOneWidget,
      ); // 送信ボタンに戻る
    });

    testWidgets('空の入力では送れない', (tester) async {
      await pumpView(tester);
      await type(tester, '   ');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      expect(repo.lastRequest, isNull);
    });

    testWidgets('クレジット不足で弾かれたら、案内と購入の導線が出る', (tester) async {
      await pumpView(tester);
      repo.sendError = const ChatRequestException(
        'INSUFFICIENT_CREDITS',
        'x',
        status: 402,
        detail: {'min_credits': 5},
      );
      await type(tester, 'hello');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);

      expect(
        find.text(l10n.aiChatErrorInsufficientCredits('5')),
        findsOneWidget,
      );
      expect(find.text(l10n.aiChatNotSent), findsOneWidget);
      await tester.tap(find.text(l10n.aiChatBuyCredits));
      expect(bought, 1);
    });

    testWidgets('送れなかったら、「もう一度送る」で同じ内容を送り直せる', (tester) async {
      await pumpView(tester);
      repo.sendError = const ChatRequestException('NETWORK', 'offline');
      await type(tester, 'again please');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      expect(find.text(l10n.aiChatErrorNetwork), findsOneWidget);

      repo.sendError = null;
      await tester.tap(find.text(l10n.aiChatResend));
      await settle(tester);
      expect(repo.lastRequest!.content, 'again please');
      await repo.controller.close();
      await settle(tester);
    });

    testWidgets('「閉じる」で送れなかった文を消すと、入力欄に戻る', (tester) async {
      await pumpView(tester);
      repo.sendError = const ChatRequestException(
        'CHAT_RATE_LIMITED',
        'x',
        status: 429,
      );
      await type(tester, 'too fast');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      await tester.tap(find.text(l10n.aiChatDismiss));
      await settle(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'too fast');
    });

    testWidgets('話題の講義と、選んだ文章が、送信の文脈に載る。選んだ文章は1回だけ', (tester) async {
      await pumpView(
        tester,
        lectureId: 'L1',
        selection: const ChatSelection(text: 'picked text'),
      );
      await type(tester, 'about this');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      final ctx = repo.lastRequest!.context;
      expect(ctx.lectureId, 'L1');
      expect(ctx.selectedText, 'picked text');
      await repo.controller.close();
      await settle(tester);
    });

    testWidgets('停止ボタンで止まる', (tester) async {
      await pumpView(tester);
      repo.onStop = (id) async => ChatMessage.fromMap(
        chatRow(id, 'assistant', 'partial', status: 'stopped'),
      );
      await type(tester, 'long one');
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      repo.controller.add(_meta);
      repo.controller.add(const ChatDeltaEvent('part'));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel(l10n.aiChatStop));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);

      expect(find.text(l10n.aiChatStopped), findsWidgets);
      expect(
        find.textContaining('partial', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('編集・作り直し', () {
    testWidgets('編集を押すと入力欄に読み込まれ、帯が出て、送ると後ろが消えてやり直す', (tester) async {
      await pumpView(tester);
      await openThread(tester, [
        ...conversation,
        chatRow(
          'U2',
          'user',
          'second question',
          createdAt: '2026-10-18T00:00:03Z',
        ),
        chatRow(
          'A2',
          'assistant',
          'second answer',
          createdAt: '2026-10-18T00:00:04Z',
        ),
      ]);

      // 最初の質問を編集する(後ろに1往復ある)
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionEdit).last);
      await settle(tester);
      expect(find.text(l10n.aiChatEditing('1')), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'What is a binary heap?');

      await tester.enterText(find.byType(TextField), 'What is a heap?');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);

      expect(repo.lastRequest!.replaceFromMessageId, 'U1');
      expect(repo.lastRequest!.content, 'What is a heap?');
      expect(find.text(l10n.aiChatEditing('1')), findsNothing);
      await repo.controller.close();
      await settle(tester);
    });

    testWidgets('編集をやめると、入力欄は空に戻る', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionEdit));
      await settle(tester);
      expect(find.text(l10n.aiChatEditingLast), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await settle(tester);
      expect(find.text(l10n.aiChatEditingLast), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('編集が送る前に弾かれたら、会話は元のまま、案内が出る', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionEdit));
      await settle(tester);
      repo.sendError = const ChatRequestException(
        'INSUFFICIENT_CREDITS',
        'x',
        status: 402,
      );
      await tester.enterText(find.byType(TextField), 'edited');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);

      expect(
        find.text(l10n.aiChatErrorInsufficientCredits('5')),
        findsOneWidget,
      );
      expect(find.text('What is a binary heap?'), findsOneWidget);
      expect(find.text(l10n.aiChatEditingLast), findsOneWidget); // 編集中に戻る
    });

    testWidgets('最後の回答を作り直すと、直前の質問を同じ内容で送り直す', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionRegenerate));
      await settle(tester);
      expect(repo.lastRequest!.replaceFromMessageId, 'U1');
      expect(repo.lastRequest!.content, 'What is a binary heap?');
      await repo.controller.close();
      await settle(tester);
    });

    testWidgets('作り直せるのは最後の回答だけ', (tester) async {
      await pumpView(tester);
      await openThread(tester, [
        ...conversation,
        chatRow('U2', 'user', 'q2', createdAt: '2026-10-18T00:00:03Z'),
        chatRow('A2', 'assistant', 'a2', createdAt: '2026-10-18T00:00:04Z'),
      ]);
      expect(
        find.bySemanticsLabel(l10n.aiChatActionRegenerate),
        findsOneWidget,
      );
    });
  });

  group('回答への返信', () {
    testWidgets('回答の一部を長押しで選ぶと、浮かぶメニューに「AIに聞く」が出て、入力欄に引用が入る', (tester) async {
      await pumpView(tester);
      await openThread(tester, [
        chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
        chatRow(
          'A1',
          'assistant',
          'Heaps keep the smallest element at the root.',
          createdAt: '2026-10-18T00:00:02Z',
        ),
      ]);
      final target = find.textContaining('Heaps keep', findRichText: true);
      // 文字のある所を長押しする(枠の真ん中は、行の間の空白のことがある)
      await tester.longPressAt(tester.getTopLeft(target) + const Offset(10, 8));
      await settle(tester);

      // 標準のメニューではなく、Deep Notesなどと同じ浮かぶメニュー(AIに聞く・コピーだけ)
      expect(find.byType(SelectionFloatingMenu), findsOneWidget);
      expect(find.text(l10n.cardSelectionToolbarAskLabel), findsOneWidget);
      expect(find.text(l10n.cardSelectionToolbarCopyLabel), findsOneWidget);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      await tester.tap(find.text(l10n.cardSelectionToolbarAskLabel));
      await settle(tester);

      // 入力欄の上に、選んだ文章の帯が出る
      expect(find.byIcon(Icons.format_quote_rounded), findsOneWidget);

      // 送ると、返信先の回答と選んだ文章が文脈に載る
      await tester.enterText(find.byType(TextField), 'why?');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      final ctx = repo.lastRequest!.context;
      expect(ctx.replyToMessageId, 'A1');
      expect(ctx.selectedText, isNotEmpty);
      expect(
        'Heaps keep the smallest element at the root.',
        contains(ctx.selectedText!),
      );
      await repo.controller.close();
      await settle(tester);
    });

    testWidgets('生成中の回答は選べない(完了してから)', (tester) async {
      await pumpView(tester);
      await openThread(tester, [
        chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
        chatRow(
          'A1',
          'assistant',
          'still writing',
          status: 'streaming',
          createdAt: '2026-10-18T00:00:02Z',
        ),
      ]);
      await tester.longPress(
        find.textContaining('still writing', findRichText: true),
      );
      await settle(tester);
      expect(find.byType(SelectionFloatingMenu), findsNothing);
    });

    testWidgets('「コピー」で、選んだ文章がコピーされ、メニューが閉じる', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpView(tester);
      await openThread(tester, [
        chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
        chatRow(
          'A1',
          'assistant',
          'Heaps keep the smallest element at the root.',
          createdAt: '2026-10-18T00:00:02Z',
        ),
      ]);
      final target = find.textContaining('Heaps keep', findRichText: true);
      await tester.longPressAt(tester.getTopLeft(target) + const Offset(10, 8));
      await settle(tester);
      await tester.tap(find.text(l10n.cardSelectionToolbarCopyLabel));
      await settle(tester);

      expect(copied, hasLength(1));
      expect(copied.single, isNotEmpty);
      expect(
        'Heaps keep the smallest element at the root.',
        contains(copied.single),
      );
      expect(find.byType(SelectionFloatingMenu), findsNothing);
      // 入力欄には何も入らない
      expect(find.byIcon(Icons.format_quote_rounded), findsNothing);
    });
  });

  group('報告', () {
    testWidgets('「…」→ 報告 → 種類と内容を入れて送ると、受付コードが出る', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionMore));
      await settle(tester);
      await tester.tap(find.text(l10n.aiChatActionReport));
      await settle(tester);

      expect(find.text(l10n.aiReportCategoryInappropriate), findsOneWidget);
      // 内容が空のうちは送れない
      final submit = find.widgetWithText(FilledButton, l10n.aiReportSubmit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.tap(find.text(l10n.aiReportCategoryIncorrect));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).last,
        'The answer is wrong.',
      );
      await tester.pump();
      await tester.tap(submit);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);

      expect(repo.reports, hasLength(1));
      final sent = repo.reports.single;
      expect(sent.category, 'incorrect');
      expect(sent.message, 'The answer is wrong.');
      expect(sent.report!['source'], 'ai_chat');
      expect(sent.report!['message_id'], 'A1');
      expect(sent.report!['thread_id'], 'T1');
      final attached = sent.report!['attached'] as List;
      expect(
        attached.map((a) => (a as Map)['text']),
        contains('What is a binary heap?'),
      );
      expect(find.text(l10n.aiReportSentBody('TICKET-123')), findsOneWidget);
    });

    testWidgets('送信に失敗したら、案内を出して、もう一度送れる', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionMore));
      await settle(tester);
      await tester.tap(find.text(l10n.aiChatActionReport));
      await settle(tester);
      repo.reportError = const ChatRequestException('NETWORK', 'x');
      await tester.enterText(find.byType(TextField).last, 'oops');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.aiReportSubmit));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(find.text(l10n.aiReportFailed), findsOneWidget);
      expect(repo.reports, isEmpty);

      repo.reportError = null;
      await tester.tap(find.widgetWithText(FilledButton, l10n.aiReportSubmit));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(repo.reports, hasLength(1));
    });

    testWidgets('「詳細」で、送った日時・クレジット・出典の数が見える', (tester) async {
      await pumpView(tester);
      final row = chatRow(
        'A1',
        'assistant',
        'answer',
        createdAt: '2026-10-18T00:00:02Z',
      );
      row['credits_charged_micro'] = 420000;
      await openThread(tester, [
        chatRow('U1', 'user', 'q', createdAt: '2026-10-18T00:00:01Z'),
        row,
      ]);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionMore));
      await settle(tester);
      await tester.tap(find.text(l10n.aiChatActionDetails));
      await settle(tester);
      expect(find.text(l10n.aiChatCreditsUsed('0.42')), findsOneWidget);
      expect(find.text(l10n.aiChatDetailSourcesCount('0')), findsOneWidget);
    });
  });

  group('資料', () {
    ChatAttachment material(
      String id,
      String title, {
      bool selected = false,
      String? messageId,
      String content = 'Heaps are complete binary trees.',
      List<ChatAttachmentSection> sections = const [],
    }) => ChatAttachment(
      id: id,
      threadId: 'T1',
      messageId: messageId,
      kind: 'text',
      status: ChatAttachmentStatus.ready,
      title: title,
      content: content,
      charCount: content.length,
      tokenCount: 100,
      selected: selected,
      sections: sections,
      summary: 'About heaps',
      createdAt: DateTime.utc(2026, 10, 18),
    );

    String inputText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('「＋」→ この会話の資料 → 全文で添付すると、一覧を開いたまま全文で読む資料になり、入力欄の上にチップが出る', (tester) async {
      repo.attachments = [material('m1', 'Heap notes')];
      await pumpView(tester);
      await openThread(tester, conversation);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester);
      await tester.tap(find.text(l10n.aiChatAttachSelect));
      await settle(tester);
      // 「＋」のメニューの項目と同じ文言なので、閉じる途中は2つ見える
      expect(find.text(l10n.aiChatAttachmentsTitle), findsWidgets);
      expect(find.text('Heap notes'), findsOneWidget);
      expect(find.text('About heaps'), findsOneWidget);

      await tester.tap(find.text('Heap notes'));
      await settle(tester);
      await tester.tap(find.text(l10n.aiChatAttachFull));
      await settle(tester);

      // 一覧は開いたまま、その場で「全文で読み中」になる(送信を待たない)
      expect(find.text(l10n.aiChatAttachmentsTitle), findsWidgets);
      expect(repo.selectCalls, [('m1', true)]);
      expect(find.text(l10n.aiChatAttachPinned), findsWidgets);
      // 一覧を閉じる(閉じ方はこのテストの対象外なので、Navigatorで確実に閉じる)
      Navigator.of(tester.element(find.text('About heaps'))).pop();
      // 閉じるアニメーションに300〜400msかかるので、既定のsettle(計400ms)より長く待つ
      await settle(tester, 400);
      // 一覧の見出しは「＋」メニューの項目と同じ文言なので、一覧にしか無い要約で閉じたことを見る
      expect(find.text('About heaps'), findsNothing);

      // 入力欄には名前を入れず(それは「メンション」)、入力欄の上にチップが出る
      expect(inputText(tester), '');
      expect(find.byType(ChatPinnedChip), findsOneWidget);
    });

    testWidgets('資料が無い会話では、「＋」の「この会話の資料」は選べない', (tester) async {
      await pumpView(tester);
      await openThread(tester, conversation);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester);
      expect(find.text(l10n.aiChatAttachSelectNone), findsOneWidget);
    });

    testWidgets('全文で読んでいる資料は入力欄の上に出て、×でやめられる', (tester) async {
      repo.attachments = [material('m1', 'Heap notes', selected: true)];
      await pumpView(tester);
      await openThread(tester, conversation);
      expect(find.text('Heap notes'), findsOneWidget);
      expect(find.text(l10n.aiChatAttachPinned), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(ChatPinnedChip),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await settle(tester);
      expect(repo.selectCalls, [('m1', false)]);
      expect(find.byType(ChatPinnedChip), findsNothing);
    });

    testWidgets('送った資料のチップを押すと中身を読めて、会話から外せる', (tester) async {
      repo.attachments = [
        material(
          'm1',
          'Heap notes',
          messageId: 'U2',
          content: 'Section one text.\nSection two text.',
          sections: const [
            ChatAttachmentSection(
              index: 1,
              title: 'One',
              description: 'first',
              start: 0,
              end: 17,
            ),
            ChatAttachmentSection(
              index: 2,
              title: 'Two',
              description: 'second',
              start: 18,
              end: 35,
            ),
          ],
        ),
      ];
      await pumpView(tester);
      await openThread(tester, [
        ...conversation,
        chatRow(
          'U2',
          'user',
          'please read this',
          createdAt: '2026-10-18T00:00:03Z',
          context: {
            'attachments': [
              {'id': 'm1', 'mode': 'full'},
            ],
          },
        ),
      ]);

      await tester.tap(find.text('Heap notes'));
      await settle(tester);
      expect(find.text(l10n.aiChatAttachmentFullText), findsOneWidget);
      expect(find.text('About heaps'), findsOneWidget);
      expect(find.text('1. One'), findsOneWidget);
      expect(find.text('Section two text.'), findsOneWidget);

      await tester.tap(find.text(l10n.aiChatAttachmentRemove));
      await settle(tester);
      expect(find.text(l10n.aiChatAttachmentRemoveConfirm), findsOneWidget);
      await tester.tap(find.text(l10n.aiChatAttachmentRemove).last);
      await settle(tester);
      expect(repo.removedAttachments, ['m1']);
      await settle(tester, 400);
      expect(find.text(l10n.aiChatAttachmentFullText), findsNothing);
    });

    testWidgets('資料を指した質問を編集すると、「@名前」と渡し方が入力欄に戻る', (tester) async {
      repo.attachments = [material('m1', 'Heap notes', messageId: 'U1')];
      await pumpView(tester);
      await openThread(tester, [
        chatRow(
          'U1',
          'user',
          'explain ⟦att:m1⟧ please',
          context: {
            'attachments': [
              {'id': 'm1', 'mode': 'full'},
            ],
          },
        ),
        chatRow(
          'A1',
          'assistant',
          'Sure.',
          createdAt: '2026-10-18T00:00:02Z',
        ),
      ]);
      await tester.tap(find.bySemanticsLabel(l10n.aiChatActionEdit));
      await settle(tester);
      expect(inputText(tester), 'explain @Heap notes please');

      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      final request = repo.lastRequest!;
      expect(request.content, 'explain ⟦att:m1⟧ please');
      expect(request.replaceFromMessageId, 'U1');
      expect(request.references.single.attachmentId, 'm1');
      expect(request.references.single.mode, ChatAttachmentMode.full);
      await repo.controller.close();
      await settle(tester);
    });
  });

  group('過去ログの読み込みとスクロール維持', () {
    testWidgets('過去ログ読み込み時に表示中メッセージの画面位置が完全に維持される(0pxズレ)', (tester) async {
      final rows = [
        for (var i = 1; i <= 30; i++)
          chatRow(
            'M$i',
            i.isOdd ? 'user' : 'assistant',
            'Message item $i',
            createdAt: '2026-10-18T00:${i.toString().padLeft(2, '0')}:00Z',
          ),
      ];
      await pumpView(tester);
      await openThread(tester, rows);

      // 初期状態: 最新20件(M11..M30)のみ取得され、古いM1は未ロード
      final state1 = container.read(chatConversationProvider);
      expect(state1.messages.length, 20);
      expect(state1.hasMore, isTrue);
      expect(find.text('Message item 1'), findsNothing);

      final messageList = find.byWidgetPredicate((w) => w is ScrollView).first;
      final list = tester.state<ScrollableState>(
        find.descendant(of: messageList, matching: find.byType(Scrollable)).first,
      );
      double fromBottom() => list.position.maxScrollExtent - list.position.pixels;

      // 少し上(過去側)へスクロールして M26 が見える状態にする(トリガー閾値には届かない位置)
      await tester.drag(messageList, const Offset(0, 200));
      await tester.pump();
      expect(fromBottom(), closeTo(200, 1.0));

      final m26Finder = find.text('Message item 26');
      expect(m26Finder, findsOneWidget);
      final m26Before = tester.getTopLeft(m26Finder);

      // 過去ログを読み込む
      await tester.runAsync(
        () => container.read(chatConversationProvider.notifier).loadOlderMessages(),
      );
      await tester.pump();

      // 全30件になり、hasMoreがfalseになる
      final state2 = container.read(chatConversationProvider);
      expect(state2.messages.length, 30);
      expect(state2.hasMore, isFalse);

      // 過去ログ読み込み後も、見ていた M26 のY座標が 0.0px (完全に不変) であることを検証！
      final m26After = tester.getTopLeft(m26Finder);
      expect(m26After.dy, equals(m26Before.dy));
      // 最下部からの距離も全く変わらない
      expect(fromBottom(), closeTo(200, 1.0));
    });

    testWidgets('最上部付近へスクロールすると自動で過去ログが読み込まれる', (tester) async {
      final rows = [
        for (var i = 1; i <= 30; i++)
          chatRow(
            'M$i',
            i.isOdd ? 'user' : 'assistant',
            'Message item $i',
            createdAt: '2026-10-18T00:${i.toString().padLeft(2, '0')}:00Z',
          ),
      ];
      await pumpView(tester);
      await openThread(tester, rows);

      final messageList = find.byWidgetPredicate((w) => w is ScrollView).first;
      final list = tester.state<ScrollableState>(
        find.descendant(of: messageList, matching: find.byType(Scrollable)).first,
      );

      // 最上部の50px手前までスクロールして150px閾値に入る
      final targetOffset =
          list.position.pixels - list.position.minScrollExtent - 50;
      await tester.drag(messageList, Offset(0, targetOffset));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester, 300);

      // 自動で全30件が読み込まれたことを確認
      final state = container.read(chatConversationProvider);
      expect(state.messages.length, 30);
      expect(state.hasMore, isFalse);
    });
  });

  /// 回答の続きを1つ受け取って、画面を進める。
  Future<void> receive(WidgetTester tester, String delta) async {
    repo.controller.add(ChatDeltaEvent(delta));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('受信中のスクロール', () {
    // 端で止まる(Android)と跳ね返る(iOS)の両方のスクロールで確かめる
    final platforms = TargetPlatformVariant(
      {TargetPlatform.android, TargetPlatform.iOS},
    );
    // 位置(pixels)ではなく画面上の見え方で確かめる。リストの組み方(逆向き/中央基準)で
    // pixelsの意味が変わっても、ユーザーに見える動きは同じであるべきなので。
    Finder messageList() => find.byWidgetPredicate((w) => w is ScrollView).first;

    String paragraph(int i) => 'Delta paragraph $i. ${'streaming words here ' * 8}\n\n';

    /// 長めの会話を開き、質問を送って回答の最初の4段落を受け取った状態にする。
    Future<void> startStreaming(WidgetTester tester) async {
      final rows = [
        for (var i = 1; i <= 16; i++)
          chatRow(
            'M$i',
            i.isOdd ? 'user' : 'assistant',
            'Message item $i ${'lorem ipsum dolor sit amet ' * 6}',
            createdAt: '2026-10-18T00:${i.toString().padLeft(2, '0')}:00Z',
          ),
      ];
      await pumpView(tester);
      await openThread(tester, rows);
      await tester.enterText(find.byType(TextField), 'Explain');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      repo.controller.add(_meta);
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await receive(tester, paragraph(i));
      }
    }

    Future<void> finishStreaming(WidgetTester tester) async {
      repo.controller.add(
        const ChatDoneEvent(status: ChatMessageStatus.complete, creditsCharged: 0.1),
      );
      await repo.controller.close();
      await settle(tester);
      // 既存の会話への送信は、完了時にキャッシュを同期する。その処理はDBの実I/Oと
      // 疑似時間のタイマーの両方を待つので、片方だけ進めても終わらず、tearDownの
      // settle()が待ち続ける。実時間と疑似時間を交互に進めて終わらせる。
      var done = false;
      unawaited(
        container.read(chatConversationProvider.notifier).settle().then((_) => done = true),
      );
      for (var i = 0; i < 50 && !done; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done, isTrue, reason: '裏の保存が終わらない');
    }

    double viewportBottom(WidgetTester tester) => tester.getRect(messageList()).bottom;

    /// 指で[dy]だけ下へ動かし、止めてから離す(慣性スクロールを残さない)。
    Future<void> scrollUpBy(WidgetTester tester, double dy) async {
      final gesture = await tester.startGesture(tester.getCenter(messageList()));
      const step = 20.0;
      for (var moved = 0.0; moved < dy; moved += step) {
        await gesture.moveBy(Offset(0, step < dy - moved ? step : dy - moved));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// 一番新しい段落の下端(画面上のY)。
    double newestBottom(WidgetTester tester, int i) => tester
        .getRect(find.textContaining('Delta paragraph $i.', findRichText: true).first)
        .bottom;

    testWidgets('最下部にいるときは、伸びる回答の末尾が画面の下端に見え続ける', (tester) async {
      await startStreaming(tester);
      for (var i = 4; i < 8; i++) {
        await receive(tester, paragraph(i));
        final bottom = newestBottom(tester, i);
        expect(bottom, lessThanOrEqualTo(viewportBottom(tester)), reason: 'delta $i');
        expect(bottom, greaterThan(viewportBottom(tester) - 60), reason: 'delta $i');
      }
      await finishStreaming(tester);
    }, variant: platforms, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('上へ読み戻している間は、回答が伸びても読んでいる文章が動かない', (tester) async {
      await startStreaming(tester);
      await scrollUpBy(tester, 400);

      final reading = find.textContaining('Delta paragraph 1.', findRichText: true).first;
      final before = tester.getTopLeft(reading).dy;
      expect(before, inInclusiveRange(0, viewportBottom(tester)), reason: '読んでいる段落が画面内にある');

      for (var i = 4; i < 8; i++) {
        await receive(tester, paragraph(i));
        expect(tester.getTopLeft(reading).dy, closeTo(before, 0.5), reason: 'delta $i');
        // 最下部へは引き戻されない
        expect(newestBottom(tester, i), greaterThan(viewportBottom(tester)), reason: 'delta $i');
      }
      await finishStreaming(tester);
      expect(tester.getTopLeft(reading).dy, closeTo(before, 0.5), reason: '完了後');
    }, variant: platforms, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('画面に収まる短い会話はスクロールせず、引っ張っても元の位置に戻る', (tester) async {
      await pumpView(tester);
      await tester.enterText(find.byType(TextField), 'Short question');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      repo.controller.add(_meta);
      await receive(tester, 'Short answer.');
      await settle(tester);

      final question = find.text('Short question');
      final before = tester.getTopLeft(question).dy;
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: messageList(), matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(position.maxScrollExtent - position.minScrollExtent, closeTo(0, 0.5));

      await scrollUpBy(tester, 200);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(question).dy, closeTo(before, 0.5));
      await finishStreaming(tester);
    }, variant: platforms, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('短い会話の回答が伸びて画面からはみ出しても、最下部に追従し、読み戻せば止まって見える', (tester) async {
      await pumpView(tester);
      await tester.enterText(find.byType(TextField), 'Short question');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(l10n.aiChatSend));
      await settle(tester);
      repo.controller.add(_meta);
      for (var i = 0; i < 8; i++) {
        await receive(tester, paragraph(i));
        await tester.pump();
        final bottom = newestBottom(tester, i);
        expect(bottom, lessThanOrEqualTo(viewportBottom(tester)), reason: 'delta $i');
        expect(bottom, greaterThan(viewportBottom(tester) - 60), reason: 'delta $i');
      }

      await scrollUpBy(tester, 400);
      final reading = find.textContaining('Delta paragraph 3.', findRichText: true).first;
      final before = tester.getTopLeft(reading).dy;
      for (var i = 8; i < 11; i++) {
        await receive(tester, paragraph(i));
        expect(tester.getTopLeft(reading).dy, closeTo(before, 0.5), reason: 'delta $i');
      }
      await finishStreaming(tester);
    }, variant: platforms, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('最下部からわずかに離れただけなら、受信で最下部へ戻って追従する', (tester) async {
      await startStreaming(tester);
      await scrollUpBy(tester, 60);

      await receive(tester, paragraph(4));
      await receive(tester, paragraph(5));
      final bottom = newestBottom(tester, 5);
      expect(bottom, lessThanOrEqualTo(viewportBottom(tester)));
      expect(bottom, greaterThan(viewportBottom(tester) - 60));
      await finishStreaming(tester);
    }, variant: platforms, timeout: const Timeout(Duration(seconds: 60)));
  });
}
