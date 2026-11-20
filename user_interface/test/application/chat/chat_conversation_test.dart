import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';

import 'fake_chat_repository.dart';

const _meta = ChatMetaEvent(
  threadId: 'T1',
  userMessageId: 'U1',
  assistantMessageId: 'A1',
);

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeChatRepository repo;
  late AppDatabase db;
  late ProviderContainer container;

  ChatConversationState read() => container.read(chatConversationProvider);
  ChatConversation notifier() =>
      container.read(chatConversationProvider.notifier);

  setUp(() {
    repo = FakeChatRepository();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatCacheDriftProvider.overrideWithValue(ChatCacheDrift(db)),
      ],
    );
    container.read(chatConversationProvider); // keepAliveなので先に作っておく
    chatReconnectPollInterval = const Duration(milliseconds: 10);
    chatReconnectPollMaxAttempts = 40;
  });

  tearDown(() async {
    await notifier().settle();
    container.dispose();
    await db.close();
  });

  group('送信', () {
    test('送信中は仮のid、metaで本物のidに変わり、deltaで本文が伸び、doneで確定する', () async {
      final sent = notifier().send('二分ヒープとは？');
      await _pump();

      var s = read();
      expect(s.sending, isTrue);
      expect(s.messages.map((m) => m.isUser), [true, false]);
      expect(s.messages.first.id, startsWith('local-user-'));
      expect(s.messages.last.stage, ChatStage.thinking);
      expect(repo.lastRequest!.content, '二分ヒープとは？');

      repo.controller.add(_meta);
      await _pump();
      s = read();
      expect(s.threadId, 'T1');
      expect(s.messages.map((m) => m.id), ['U1', 'A1']);
      expect(s.messages.map((m) => m.message.threadId), ['T1', 'T1']);

      repo.controller.add(
        const ChatStatusEvent(
          stage: ChatStage.reasoning,
          progressLabel: 'Checking the heap',
        ),
      );
      repo.controller.add(
        const ChatStatusEvent(
          stage: ChatStage.reasoning,
          progressLabel: 'Checking the parent node',
        ),
      );
      await _pump();
      s = read();
      expect(s.messages.last.progressLabel, 'Checking the parent node');
      expect(s.messages.last.stage, ChatStage.reasoning);

      repo.controller.add(
        const ChatStatusEvent(
          stage: ChatStage.searching,
          detail: ['lectures'],
          query: 'heap',
        ),
      );
      repo.controller.add(const ChatDeltaEvent('木の'));
      repo.controller.add(const ChatDeltaEvent('こと'));
      await _pump();
      s = read();
      expect(s.messages.last.message.content, '木のこと');
      expect(s.messages.last.stage, ChatStage.searching);
      expect(s.messages.last.searchQuery, 'heap');
      expect(s.messages.last.progressLabel, isNull);

      repo.controller.add(
        const ChatDoneEvent(
          status: ChatMessageStatus.complete,
          citations: [
            ChatCitation(ref: '1', sourceType: 'deep_note', label: 'x'),
          ],
          creditsCharged: 0.5,
        ),
      );
      await repo.controller.close();
      await sent;

      s = read();
      expect(s.sending, isFalse);
      final reply = s.messages.last;
      expect(reply.message.status, ChatMessageStatus.complete);
      expect(reply.message.citations, hasLength(1));
      expect(reply.message.creditsChargedMicro, 500000);
      expect(reply.stage, isNull);
      expect(reply.progressLabel, isNull);
    });

    test('空のメッセージは送らない。送信中の二重送信も無視する', () async {
      await notifier().send('   ');
      expect(read().messages, isEmpty);

      unawaited(notifier().send('一つ目'));
      await _pump();
      await notifier().send('二つ目');
      expect(read().messages, hasLength(2));
      expect(repo.lastRequest!.content, '一つ目');
      await repo.controller.close();
    });

    test('送る前に弾かれたら(残高不足)、返答の枠は消えて「送れなかった」になる', () async {
      repo.sendError = const ChatRequestException(
        'INSUFFICIENT_CREDITS',
        'no credits',
        status: 402,
      );
      await notifier().send('質問');
      final s = read();
      expect(s.sending, isFalse);
      expect(s.messages, hasLength(1));
      expect(s.messages.single.failedCode, 'INSUFFICIENT_CREDITS');
    });

    test('送れなかったメッセージは、同じ内容で再送できる', () async {
      repo.sendError = const ChatRequestException('NETWORK', 'offline');
      await notifier().send('もう一度');
      final failedId = read().messages.single.id;

      repo.sendError = null;
      final retried = notifier().retry(failedId);
      await _pump();
      expect(repo.lastRequest!.content, 'もう一度');
      expect(read().messages.where((m) => m.failedCode != null), isEmpty);
      await repo.controller.close();
      await retried;
    });

    test('送れなかったメッセージは、画面から消せる', () async {
      repo.sendError = const ChatRequestException(
        'CHAT_RATE_LIMITED',
        'slow down',
        status: 429,
      );
      await notifier().send('多すぎ');
      notifier().discard(read().messages.single.id);
      expect(read().messages, isEmpty);
    });

    test('errorイベントでは返答がerrorになる(課金なし)', () async {
      final sent = notifier().send('質問');
      await _pump();
      repo.controller.add(_meta);
      repo.controller.add(
        const ChatErrorEvent(errorCode: 'CHAT_FAILED', message: 'x'),
      );
      await repo.controller.close();
      await sent;
      expect(read().messages.last.message.status, ChatMessageStatus.error);
    });

    test('資料つきの送信は、メッセージの文脈に資料と渡し方が残る', () async {
      final sent = notifier().send(
        '見て',
        newAttachments: const [
          ChatTextAttachment(localId: 'loc1', title: 't', content: 'c'),
        ],
        references: const [
          ChatAttachmentRef(
            attachmentId: 'old1',
            mode: ChatAttachmentMode.mention,
          ),
        ],
      );
      await _pump();
      final atts = read().messages.first.message.context.attachments;
      expect(atts.map((a) => (a.attachmentId, a.mode)), [
        ('old1', ChatAttachmentMode.mention),
        ('loc1', ChatAttachmentMode.full),
      ]);
      await repo.controller.close();
      await sent;
    });
  });

  group('編集・作り直し', () {
    setUp(() async {
      repo.serverRows['T1'] = [
        chatRow('U1', 'user', '最初', createdAt: '2026-10-18T00:00:01Z'),
        chatRow('A1', 'assistant', '答え1', createdAt: '2026-10-18T00:00:02Z'),
        chatRow('U2', 'user', '二つ目', createdAt: '2026-10-18T00:00:03Z'),
        chatRow('A2', 'assistant', '答え2', createdAt: '2026-10-18T00:00:04Z'),
      ];
      await notifier().openThread('T1');
    });

    test('送る前は、編集したメッセージから後ろが画面から外れる', () async {
      final sent = notifier().send('直した', replaceFromMessageId: 'U2');
      await _pump();
      expect(read().messages.map((m) => m.id).take(2), ['U1', 'A1']);
      expect(read().messages, hasLength(4)); // U1, A1, 新しいuser, 新しいassistant
      expect(repo.lastRequest!.replaceFromMessageId, 'U2');
      await repo.controller.close();
      await sent;
    });

    test('弾かれたら、会話は元のまま戻り、onRejectedが呼ばれる', () async {
      repo.sendError = const ChatRequestException(
        'INSUFFICIENT_CREDITS',
        'x',
        status: 402,
      );
      String? rejected;
      await notifier().send(
        '直した',
        replaceFromMessageId: 'U2',
        onRejected: (code, _) => rejected = code,
      );
      expect(rejected, 'INSUFFICIENT_CREDITS');
      expect(read().messages.map((m) => m.id), ['U1', 'A1', 'U2', 'A2']);
      expect(read().messages.every((m) => m.failedCode == null), isTrue);
    });
  });

  group('停止', () {
    test('停止を押すと、サーバーが返した確定した行に差し替わり、受信も止まる', () async {
      repo.onStop = (id) async => ChatMessage.fromMap(
        chatRow(id, 'assistant', '途中まで', status: 'stopped'),
      );
      final sent = notifier().send('長い質問');
      await _pump();
      repo.controller.add(_meta);
      repo.controller.add(const ChatDeltaEvent('途中'));
      await _pump();

      notifier().stop();
      await sent;

      final s = read();
      expect(s.sending, isFalse);
      expect(s.stopping, isFalse);
      expect(s.messages.last.message.status, ChatMessageStatus.stopped);
      expect(s.messages.last.message.content, '途中まで');
      expect(s.messages.last.stopping, isFalse);
    });

    test('返答のidが届く前に停止を押しても、届いた瞬間に止める', () async {
      var stoppedId = '';
      repo.onStop = (id) async {
        stoppedId = id;
        return ChatMessage.fromMap(
          chatRow(id, 'assistant', '', status: 'stopped'),
        );
      };
      final sent = notifier().send('質問');
      await _pump();
      notifier().stop(); // まだmetaが届いていない
      expect(read().stopping, isTrue);
      expect(stoppedId, isEmpty);

      repo.controller.add(_meta);
      await sent;
      expect(stoppedId, 'A1');
      expect(read().messages.last.message.status, ChatMessageStatus.stopped);
    });

    test('停止のリクエストが届かなかったら、受信は続き、もう一度押せる', () async {
      repo.onStop = (_) async =>
          throw const ChatRequestException('NETWORK', 'x');
      final sent = notifier().send('質問');
      await _pump();
      repo.controller.add(_meta);
      repo.controller.add(const ChatDeltaEvent('続く'));
      await _pump();

      notifier().stop();
      await _pump();
      var s = read();
      expect(s.messages.last.stopFailed, isTrue);
      expect(s.stopping, isFalse);
      expect(s.sending, isTrue);

      repo.controller.add(const ChatDeltaEvent('よ'));
      await _pump();
      expect(read().messages.last.message.content, '続くよ');
      await repo.controller.close();
      await sent;
    });
  });

  group('通信が切れた・裏から戻った', () {
    test('metaのあとに切れたら、サーバーで生成が終わるのをDBで待って差し替える', () async {
      final sent = notifier().send('質問');
      await _pump();
      repo.controller.add(_meta);
      repo.controller.add(const ChatDeltaEvent('途中'));
      await _pump();
      repo.controller.addError(const ChatRequestException('NETWORK', 'lost'));
      await sent;

      // 少しのあいだはまだ生成中、そのあと完了する
      repo.messagesById['A1'] = ChatMessage.fromMap(
        chatRow('A1', 'assistant', '', status: 'streaming'),
      );
      await _pump();
      expect(read().messages.last.reconnecting, isTrue);

      repo.messagesById['A1'] = ChatMessage.fromMap(
        chatRow('A1', 'assistant', '最後まで書けた'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final reply = read().messages.last;
      expect(reply.message.content, '最後まで書けた');
      expect(reply.message.status, ChatMessageStatus.complete);
      expect(reply.reconnecting, isFalse);
    });

    test('待っても終わらなければ、errorにする', () async {
      chatReconnectPollMaxAttempts = 3;
      final sent = notifier().send('質問');
      await _pump();
      repo.controller.add(_meta);
      await _pump();
      repo.controller.addError(const ChatRequestException('NETWORK', 'lost'));
      await sent;
      repo.messagesById['A1'] = ChatMessage.fromMap(
        chatRow('A1', 'assistant', '', status: 'streaming'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(read().messages.last.message.status, ChatMessageStatus.error);
      expect(read().messages.last.reconnecting, isFalse);
    });

    test('裏から戻ったら、受信中の接続を捨てて、DBの内容で追いつく', () async {
      final sent = notifier().send('質問');
      await _pump();
      repo.controller.add(_meta);
      repo.controller.add(const ChatDeltaEvent('裏に回る前'));
      await _pump();

      // 裏に回っている間にサーバーは最後まで書き終えた(接続は黙って切れている)
      repo.messagesById['A1'] = ChatMessage.fromMap(
        chatRow(
          'A1',
          'assistant',
          '裏で最後まで書けた',
          createdAt: '2026-10-18T00:00:05Z',
        ),
      );
      await notifier().onAppResumed();
      await sent;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final s = read();
      expect(s.sending, isFalse);
      expect(s.messages.last.message.content, '裏で最後まで書けた');
      expect(s.messages.last.message.status, ChatMessageStatus.complete);
    });

    test('生成中でなければ、戻っても何もしない', () async {
      repo.serverRows['T1'] = [
        chatRow('U1', 'user', 'hi'),
        chatRow('A1', 'assistant', 'hello'),
      ];
      await notifier().openThread('T1');
      final before = repo.pollCount;
      await notifier().onAppResumed();
      await _pump();
      expect(repo.pollCount, before);
    });
  });

  group('開く・キャッシュ', () {
    test('前回のキャッシュを先に出し、サーバーの内容で丸ごと置き換える', () async {
      repo.serverRows['T1'] = [
        chatRow('U1', 'user', '古い質問'),
        chatRow('A1', 'assistant', '古い答え'),
      ];
      await notifier().openThread('T1');
      expect(read().messages.last.message.content, '古い答え');
      await notifier().settle(); // キャッシュへの保存を待つ

      // webで編集・再生成された: サーバーの中身が変わった
      repo.serverRows['T1'] = [
        chatRow('U1', 'user', '新しい質問'),
        chatRow('A9', 'assistant', '新しい答え'),
      ];
      await notifier().settle();
      container.invalidate(chatConversationProvider);
      container.read(chatConversationProvider);

      final opening = notifier().openThread('T1');
      await Future<void>.delayed(Duration.zero);
      await opening;
      final s = read();
      expect(s.loading, isFalse);
      expect(s.messages.map((m) => m.id), ['U1', 'A9']);
      expect(s.messages.last.message.content, '新しい答え');
    });

    test('読み込みに失敗しても、キャッシュがあればそのまま見せる', () async {
      repo.serverRows['T1'] = [
        chatRow('U1', 'user', '質問'),
        chatRow('A1', 'assistant', '答え'),
      ];
      await notifier().openThread('T1');
      await notifier().settle();

      repo.serverRows['T1'] = null; // オフライン
      await notifier().settle();
      container.invalidate(chatConversationProvider);
      container.read(chatConversationProvider);
      await notifier().openThread('T1');

      final s = read();
      expect(s.loadFailed, isFalse);
      expect(s.messages, hasLength(2));
    });

    test('キャッシュも無く読み込みに失敗したら、loadFailedになる', () async {
      repo.serverRows['T9'] = null;
      await notifier().openThread('T9');
      expect(read().loadFailed, isTrue);
      expect(read().messages, isEmpty);
    });

    test('生成中のまま残っている返答は、完了を待つ', () async {
      repo.serverRows['T1'] = [
        chatRow('U1', 'user', '質問'),
        chatRow('A1', 'assistant', '', status: 'streaming'),
      ];
      repo.messagesById['A1'] = ChatMessage.fromMap(
        chatRow('A1', 'assistant', '書き終わった'),
      );
      await notifier().openThread('T1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(read().messages.last.message.content, '書き終わった');
    });

    test('新しい会話(null)を開くと空になる', () async {
      repo.serverRows['T1'] = [chatRow('U1', 'user', 'hi')];
      await notifier().openThread('T1');
      await notifier().openThread(null);
      expect(read().threadId, isNull);
      expect(read().messages, isEmpty);
    });

    test('別の会話に切り替えると、前の会話の受信は止める', () async {
      repo.serverRows['T2'] = [chatRow('U9', 'user', 'other', threadId: 'T2')];
      final sent = notifier().send('質問');
      await _pump();
      repo.controller.add(_meta);
      await _pump();

      await notifier().openThread('T2');
      await sent;
      final s = read();
      expect(s.sending, isFalse);
      expect(s.threadId, 'T2');
      expect(s.messages.single.id, 'U9');
    });
  });

  test('サーバーの行はJSONのまま端末に保存され、同じ内容で読み戻せる', () async {
    final cache = ChatCacheDrift(db);
    final rows = [
      chatRow(
        'U1',
        'user',
        '日本語もそのまま',
        context: {
          'selected_text': '選択した文',
          'attachments': [
            {'id': 'att1', 'mode': 'full'},
          ],
        },
      ),
    ];
    await cache.replaceMessages(chatTestUid, 'T1', rows);
    final back = await cache.getMessages(chatTestUid, 'T1');
    expect(back.single.content, '日本語もそのまま');
    expect(back.single.context.selectedText, '選択した文');
    expect(back.single.context.attachments.single.attachmentId, 'att1');
    expect(jsonEncode(rows.single), isNotEmpty);

    // 別のユーザーの行は読まない
    expect(await cache.getMessages('someone-else', 'T1'), isEmpty);
  });

  group('ページネーション(過去ログの読み込み)', () {
    test('20件を超える会話を開いたときは、最新の20件だけを読み込んで hasMore が true になる', () async {
      final rows = [
        for (var i = 1; i <= 35; i++)
          chatRow(
            'M$i',
            i.isOdd ? 'user' : 'assistant',
            'Message $i',
            createdAt: '2026-10-18T00:${i.toString().padLeft(2, '0')}:00Z',
          ),
      ];
      repo.serverRows['T1'] = rows;

      await notifier().openThread('T1');
      final s = read();

      expect(s.messages.length, 20);
      expect(s.hasMore, isTrue);
      expect(s.loadingOlder, isFalse);
      // 最新の20件: M16 から M35
      expect(s.messages.first.id, 'M16');
      expect(s.messages.last.id, 'M35');
    });

    test('loadOlderMessages で過去のメッセージが先頭に追加され、最上部に達したら hasMore が false になる', () async {
      final rows = [
        for (var i = 1; i <= 25; i++)
          chatRow(
            'M$i',
            i.isOdd ? 'user' : 'assistant',
            'Message $i',
            createdAt: '2026-10-18T00:${i.toString().padLeft(2, '0')}:00Z',
          ),
      ];
      repo.serverRows['T1'] = rows;

      await notifier().openThread('T1');
      var s = read();
      expect(s.messages.length, 20);
      expect(s.hasMore, isTrue);
      expect(s.messages.first.id, 'M6');
      expect(s.messages.last.id, 'M25');

      // 過去メッセージを取得
      await notifier().loadOlderMessages();
      s = read();
      expect(s.messages.length, 25);
      expect(s.hasMore, isFalse);
      expect(s.messages.first.id, 'M1');
      expect(s.messages.last.id, 'M25');
    });

    test('20件以下の会話では最初から hasMore が false になる', () async {
      final rows = [
        for (var i = 1; i <= 10; i++)
          chatRow(
            'M$i',
            'user',
            'Message $i',
            createdAt: '2026-10-18T00:${i.toString().padLeft(2, '0')}:00Z',
          ),
      ];
      repo.serverRows['T1'] = rows;

      await notifier().openThread('T1');
      final s = read();
      expect(s.messages.length, 10);
      expect(s.hasMore, isFalse);
    });
  });
}
