import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_chat_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_page_context.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

import '../../../application/chat/fake_chat_repository.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  /// 画面を片づけて、外れる登録が流れ切るまで進める(テストの終わりに残さない)。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  ChatPageContext current() => container.read(chatPageContextProvider);

  Future<void> pumpScopes(
    WidgetTester tester, {
    bool home = true,
    bool notes = false,
    ChatScreenRef? screen,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Column(
            children: [
              if (home)
                ChatScreenScope(
                  lectureId: 'L1',
                  child: Column(
                    children: [
                      if (notes)
                        ChatScreenScope(
                          world: ChatWorld.paper,
                          screen: screen,
                          lectureId: 'L1',
                          child: const SizedBox(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the default is a universe screen with nothing registered', (
    tester,
  ) async {
    expect(current().world, ChatWorld.universe);
    expect(current().screen, isNull);
    expect(current().lectureId, isNull);
    await unmount(tester);
  });

  testWidgets('a screen registers its world, page and lecture', (tester) async {
    await pumpScopes(
      tester,
      notes: true,
      screen: const ChatScreenRef(kind: 'deep_note', id: 'N1'),
    );
    expect(current().world, ChatWorld.paper);
    expect(current().screen!.id, 'N1');
    expect(current().lectureId, 'L1');
    await unmount(tester);
  });

  testWidgets('closing the top screen brings back the one below', (
    tester,
  ) async {
    await pumpScopes(
      tester,
      notes: true,
      screen: const ChatScreenRef(kind: 'deep_note', id: 'N1'),
    );
    await pumpScopes(tester, notes: false);
    await tester.pump();
    expect(current().world, ChatWorld.universe);
    expect(current().screen, isNull);
    expect(current().lectureId, 'L1');
    await unmount(tester);
  });

  testWidgets('changing the page re-registers it', (tester) async {
    await pumpScopes(
      tester,
      notes: true,
      screen: const ChatScreenRef(kind: 'review_card', id: 'C1'),
    );
    expect(current().screen!.id, 'C1');
    await pumpScopes(
      tester,
      notes: true,
      screen: const ChatScreenRef(kind: 'review_card', id: 'C2'),
    );
    expect(current().screen!.id, 'C2');
    // 登録は1つだけ(積み上がらない)
    expect(container.read(chatPageContextStackProvider), hasLength(2));
    await unmount(tester);
  });

  testWidgets('leaving every screen clears the registration', (tester) async {
    await pumpScopes(tester, notes: true);
    await pumpScopes(tester, home: false);
    await tester.pump();
    expect(container.read(chatPageContextStackProvider), isEmpty);
  });

  group('openAiChat', () {
    late AppDatabase db;
    late ProviderContainer chatContainer;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      chatContainer = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          chatCacheDriftProvider.overrideWithValue(ChatCacheDrift(db)),
          creditSummaryProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
        ],
      );
    });

    tearDown(() async {
      await chatContainer.read(chatConversationProvider.notifier).settle();
      chatContainer.dispose();
      await db.close();
    });

    testWidgets('開いた画面の世界の色で開き、選んだ文章が添わる', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: chatContainer,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: ChatScreenScope(
              world: ChatWorld.paper,
              screen: const ChatScreenRef(kind: 'deep_note', id: 'N1'),
              child: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => openAiChat(
                      context,
                      ref,
                      selection: const ChatSelection(text: 'a binary heap'),
                    ),
                    child: const Text('ask'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('ask'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AiChatSheet), findsOneWidget);
      // 選んだ文章が入力欄の上に添わる
      expect(find.text('a binary heap'), findsOneWidget);
      // 紙の世界の色で開く
      final sheet = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first,
      );
      expect((sheet.decoration as BoxDecoration).color, ChatColors.paper.sheet);
      await unmount(tester);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
