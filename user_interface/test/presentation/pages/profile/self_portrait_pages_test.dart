import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/self_portrait/self_portrait_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/ai_memory_page.dart';
import 'package:lefture/presentation/pages/profile/user_profile_detail_page.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_settings_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/app/routes.dart';

import 'fake_self_portrait_repository.dart';

SelfPortrait portrait() => SelfPortrait.fromMap({
  'cover': {
    'bio': {'text': '情報系の学生です', 'written_by': 'ai'},
    'interests': {'text': null, 'written_by': null},
    'future_goals': {'text': '研究者になりたい', 'written_by': 'user'},
  },
  'proposals': [
    {
      'id': 'p1',
      'field': 'interests',
      'proposed_text': 'アルゴリズム、音楽',
      'created_at': '2026-10-01T00:00:00Z',
    },
  ],
  'categories': [
    {'id': 'c1', 'name': '学び方', 'description': '', 'kind': 'trait'},
  ],
  'items': [
    {
      'id': 'i1',
      'category_id': 'c1',
      'kind': 'trait',
      'content': '図にして考えるのが得意',
      'origin': 'ai',
      'status': 'active',
      'sensitive': 'none',
      'is_new': true,
      'changed_at': '2026-10-02T00:00:00Z',
      'evidence_threads': 2,
    },
    {
      'id': 'i2',
      'kind': 'trait',
      'content': 'ある信仰を持っている',
      'status': 'pending_confirm',
      'sensitive': 'religion',
      'changed_at': '2026-10-03T00:00:00Z',
    },
  ],
  'recent': [
    {
      'item_id': 'i1',
      'topics': ['ヒープ', '二分木'],
    },
  ],
});

AiMemory memory() => AiMemory.fromMap({
  'memos': [
    {'id': 'm1', 'kind': 'answer_style', 'content': '結論から短く'},
    {
      'id': 'm2',
      'kind': 'situation',
      'content': '来週が試験',
      'expires_at': '2026-10-25',
    },
  ],
  'observation_groups': [
    {
      'thread_id': 't1',
      'thread_title': 'ヒープの質問',
      'last_observed_at': '2026-10-01T00:00:00Z',
      'observations': [
        {'id': 'o1', 'note': '図で説明すると理解が早い', 'observed_at': '2026-10-01T00:00:00Z'},
      ],
    },
  ],
  'observation_count': 1,
});

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  FakeSelfPortraitRepository repo,
  Widget page,
) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [selfPortraitRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ja'),
        home: page,
      ),
    ),
  );
  await settle(tester);
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  group('自分像のページ', () {
    late FakeSelfPortraitRepository repo;

    setUp(() => repo = FakeSelfPortraitRepository(portrait: portrait(), memory: memory()));

    testWidgets('表紙の3つの欄と、最近わかったこと・確認バナーが出る', (tester) async {
      await pumpPage(tester, repo, const UserProfileDetailPage());

      expect(find.text('情報系の学生です'), findsOneWidget);
      expect(find.text('研究者になりたい'), findsOneWidget);
      // 空の欄は案内文
      expect(find.text('まだ興味・関心が設定されていません。'), findsOneWidget);
      // 会話から書かれた欄にだけ印
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      // 最近わかったこと(別々の会話から来た話題がつながっている)
      expect(find.text('つながった話'), findsOneWidget);
      expect(find.text('二分木'), findsOneWidget);
      // 確認待ち1件+書き直し案1件
      expect(find.text('確認してほしいことがあります'), findsOneWidget);
      expect(find.textContaining('残すか決めてほしいこと 1件'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('表紙の鉛筆で、その欄の今の文が入った編集シートが開く', (tester) async {
      await pumpPage(tester, repo, const UserProfileDetailPage());
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '情報系の学生です');
      // 変えるまで保存は押せない
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed,
        isNull,
      );
      await unmount(tester);
    });

    testWidgets('開くと、新しい印を消すようサーバーに伝える', (tester) async {
      await pumpPage(tester, repo, const UserProfileDetailPage());
      expect(repo.calls, contains('seen:i1'));
      await unmount(tester);
    });

    testWidgets('確認トレイで「残す」を選ぶと、残して取り直す', (tester) async {
      await pumpPage(tester, repo, const UserProfileDetailPage());
      await tester.tap(find.text('確認してほしいことがあります'));
      await settle(tester);

      expect(find.text('宗教に関わる話なので、残すかどうか決めてください'), findsOneWidget);
      await tester.tap(find.text('残す'));
      await settle(tester);

      expect(repo.calls, contains('keep:i2'));
      // 残した項目はもう確認待ちではない(書き直し案だけが残る)
      expect(find.text('宗教に関わる話なので、残すかどうか決めてください'), findsNothing);
      expect(find.text('反映する'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('書き直し案を「反映する」と、案を決めてトレイが空になれば閉じる', (tester) async {
      repo.portrait = SelfPortrait(
        cover: repo.portrait.cover,
        proposals: repo.portrait.proposals,
        categories: repo.portrait.categories,
        items: [
          for (final i in repo.portrait.items)
            if (i.isActive) i,
        ],
        recent: repo.portrait.recent,
      );
      await pumpPage(tester, repo, const UserProfileDetailPage());
      await tester.tap(find.text('確認してほしいことがあります'));
      await settle(tester);
      expect(find.text('興味・関心の書き直し案'), findsWidgets);

      await tester.tap(find.text('反映する'));
      await settle(tester);

      expect(repo.calls, contains('proposal:p1:accept'));
      expect(find.text('反映する'), findsNothing);
      await unmount(tester);
    });

    testWidgets('項目を開いて「直す」と、新しい文で保存される', (tester) async {
      await pumpPage(tester, repo, const UserProfileDetailPage());
      // 閉じたタイルの項目(最近わかったことのカードにも同じ文がある)
      await tester.tap(find.text('図にして考えるのが得意').last);
      await settle(tester);

      await tester.tap(find.text('直す'));
      await settle(tester);
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, '図や表にして考えるのが得意');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await settle(tester);

      expect(repo.calls, contains('edit:i1:図や表にして考えるのが得意'));
      await unmount(tester);
    });

    testWidgets('「違う」では理由を添えて送れる', (tester) async {
      await pumpPage(tester, repo, const UserProfileDetailPage());
      await tester.tap(find.text('図にして考えるのが得意').last);
      await settle(tester);

      await tester.tap(find.text('違う'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'そこまででもない');
      await tester.pump();
      // 主ボタン(「違う」)を押す
      await tester.tap(find.widgetWithText(FilledButton, '違う'));
      await settle(tester);

      expect(repo.calls, contains('reject:i1:そこまででもない'));
      await unmount(tester);
    });

    testWidgets('操作に失敗したら、シートは開いたまま案内を出す', (tester) async {
      repo.failWrites = true;
      await pumpPage(tester, repo, const UserProfileDetailPage());
      await tester.tap(find.text('図にして考えるのが得意').last);
      await settle(tester);
      await tester.tap(find.text('直す'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'ちがう文');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await settle(tester);

      expect(find.text('うまくいきませんでした。もう一度お試しください。'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('AIチャット設定のページ', () {
    late FakeSelfPortraitRepository repo;

    setUp(() => repo = FakeSelfPortraitRepository(portrait: portrait(), memory: memory()));

    testWidgets('話し方・今の状況・AIのメモが出る', (tester) async {
      await pumpPage(tester, repo, const AiMemoryPage());
      expect(find.text('結論から短く'), findsOneWidget);
      expect(find.text('来週が試験'), findsOneWidget);
      expect(find.textContaining('まで'), findsOneWidget);
      expect(find.text('図で説明すると理解が早い'), findsOneWidget);
      expect(find.textContaining('ヒープの質問'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('覚え書きを消すと、すぐ画面から消えて送られる', (tester) async {
      await pumpPage(tester, repo, const AiMemoryPage());
      await tester.tap(find.byTooltip('この覚え書きを消す').first);
      await settle(tester);
      expect(repo.calls, contains('deleteMemo:m1'));
      expect(find.text('結論から短く'), findsNothing);
      expect(find.text('来週が試験'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('消せなかったときは、画面を本当の状態に戻して案内を出す', (tester) async {
      repo.failWrites = true;
      await pumpPage(tester, repo, const AiMemoryPage());
      await tester.tap(find.byTooltip('この覚え書きを消す').first);
      await settle(tester);
      expect(find.text('結論から短く'), findsOneWidget);
      expect(find.text('読み込めませんでした。時間をおいてもう一度お試しください。'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('メモを1件消すと、会話ごと空になれば会話も消える', (tester) async {
      await pumpPage(tester, repo, const AiMemoryPage());
      await tester.tap(find.byTooltip('このメモを消す'));
      await settle(tester);
      expect(repo.calls, contains('deleteObservation:o1'));
      expect(find.textContaining('ヒープの質問'), findsNothing);
      expect(find.text('まだメモはありません。'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('「全部消す」は確認してから、メモだけを消す', (tester) async {
      await pumpPage(tester, repo, const AiMemoryPage());
      await tester.tap(find.text('AIのメモを全部消す'));
      await settle(tester);
      expect(find.text('1件のメモを消します。元に戻せません。'), findsOneWidget);
      expect(repo.calls, isNot(contains('forget')));

      await tester.tap(find.text('削除'));
      await settle(tester);
      expect(repo.calls, contains('forget'));
      // 覚え書きは残る
      expect(find.text('結論から短く'), findsOneWidget);
      await unmount(tester);
    });
  });
  group('チャットのAI設定シート', () {
    late FakeSelfPortraitRepository repo;

    setUp(() => repo = FakeSelfPortraitRepository(portrait: portrait(), memory: memory()));

    Future<List<String>> openSheet(WidgetTester tester) async {
      final opened = <String>[];
      await pumpPage(
        tester,
        repo,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAiSettingsSheet(
                context,
                world: ChatWorld.paper,
                onOpenPage: opened.add,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      return opened;
    }

    testWidgets('覚え書きが出て、消せる', (tester) async {
      await openSheet(tester);
      expect(find.text('結論から短く'), findsOneWidget);
      expect(find.text('来週が試験'), findsOneWidget);

      await tester.tap(find.byTooltip('この覚え書きを消す').first);
      await settle(tester);
      expect(repo.calls, contains('deleteMemo:m1'));
      expect(find.text('結論から短く'), findsNothing);
      await unmount(tester);
    });

    testWidgets('AIのメモ・自分像への入口は、シートを閉じて行き先を渡す', (tester) async {
      final opened = await openSheet(tester);
      await tester.tap(find.text('AIのメモ'));
      await settle(tester);
      expect(opened, [AppRoutes.aiMemory]);
      // シートは閉じている
      expect(find.text('結論から短く'), findsNothing);
      await unmount(tester);
    });
  });
}
