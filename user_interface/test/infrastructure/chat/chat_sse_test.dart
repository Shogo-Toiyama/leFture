import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_sse.dart';

String _event(String name, Map<String, dynamic> data) =>
    'event: $name\ndata: ${jsonEncode(data)}\n\n';

Future<List<ChatStreamEvent>> _parse(Stream<List<int>> bytes) =>
    parseChatSse(bytes).toList();

void main() {
  group('parseChatSseBlock', () {
    test('metaを読む', () {
      final e = parseChatSseBlock(
        'event: meta\ndata: {"thread_id":"t","user_message_id":"u","assistant_message_id":"a"}',
      );
      expect(e, isA<ChatMetaEvent>());
      final meta = e! as ChatMetaEvent;
      expect(
        [meta.threadId, meta.userMessageId, meta.assistantMessageId],
        ['t', 'u', 'a'],
      );
    });

    test('statusの段階と探索の情報を読む', () {
      final e =
          parseChatSseBlock(
                'event: status\ndata: {"stage":"searching","detail":["lectures","web"],"query":"heap","handle":"C2/L5"}',
              )!
              as ChatStatusEvent;
      expect(e.stage, ChatStage.searching);
      expect(e.detail, ['lectures', 'web']);
      expect(e.query, 'heap');
      expect(e.handle, 'C2/L5');
      expect(e.target, isNull);
    });

    test('知らない段階はthinkingにする', () {
      final e =
          parseChatSseBlock('event: status\ndata: {"stage":"something_new"}')!
              as ChatStatusEvent;
      expect(e.stage, ChatStage.thinking);
    });

    test('doneの状態・出典・クレジットを読む', () {
      final e =
          parseChatSseBlock(
                'event: done\ndata: ${jsonEncode({
                  'status': 'complete',
                  'credits_charged': 0.42,
                  'citations': [
                    {
                      'n': 3,
                      'source_type': 'deep_note',
                      'label': 'CS 161 / Heaps',
                      'lecture_id': 'L',
                      'passages': {
                        '5': {'text': 'hello', 'before': 'a', 'after': 'b'},
                      },
                    },
                    {'n': 'W1', 'source_type': 'web', 'label': 'example.com', 'url': 'https://example.com'},
                  ],
                })}',
              )!
              as ChatDoneEvent;
      expect(e.status, ChatMessageStatus.complete);
      expect(e.creditsCharged, 0.42);
      expect(e.citations, hasLength(2));
      expect(e.citations![0].ref, '3');
      expect(e.citations![0].passages['5']!.text, 'hello');
      expect(e.citations![1].ref, 'W1');
      expect(e.citations![1].url, 'https://example.com');
    });

    test('doneにcitationsが無ければnull(途中停止など)', () {
      final e =
          parseChatSseBlock(
                'event: done\ndata: {"status":"blocked","credits_charged":0}',
              )!
              as ChatDoneEvent;
      expect(e.citations, isNull);
      expect(e.status, ChatMessageStatus.blocked);
    });

    test('attachmentsは外した資料と長すぎた資料を読む', () {
      final e =
          parseChatSseBlock(
                'event: attachments\ndata: {"unpinned":["a"],"too_long":["b","c"]}',
              )!
              as ChatAttachmentsEvent;
      expect(e.notice.unpinned, ['a']);
      expect(e.notice.tooLong, ['b', 'c']);
    });

    test('知らないイベント・壊れたJSON・名前だけは読み飛ばす', () {
      expect(parseChatSseBlock('event: future\ndata: {"x":1}'), isNull);
      expect(parseChatSseBlock('event: delta\ndata: {broken'), isNull);
      expect(parseChatSseBlock('event: delta'), isNull);
      expect(parseChatSseBlock(': keep-alive'), isNull);
    });

    test('CRLFでも読める', () {
      final e =
          parseChatSseBlock('event: delta\r\ndata: {"text":"hi"}\r\n')!
              as ChatDeltaEvent;
      expect(e.text, 'hi');
    });

    test('thoughtイベントを読める', () {
      final e =
          parseChatSseBlock('event: thought\ndata: {"text":"思考プロセス..."}')!
              as ChatThoughtEvent;
      expect(e.text, '思考プロセス...');
    });
  });

  group('parseChatSse', () {
    test('複数のイベントを順に取り出す', () async {
      final raw =
          _event('meta', {
            'thread_id': 't',
            'user_message_id': 'u',
            'assistant_message_id': 'a',
          }) +
          _event('delta', {'text': 'こん'}) +
          _event('delta', {'text': 'にちは'}) +
          _event('done', {'status': 'complete', 'credits_charged': 1});
      final events = await _parse(Stream.value(utf8.encode(raw)));
      expect(events.map((e) => e.runtimeType), [
        ChatMetaEvent,
        ChatDeltaEvent,
        ChatDeltaEvent,
        ChatDoneEvent,
      ]);
      expect(
        events.whereType<ChatDeltaEvent>().map((e) => e.text).join(),
        'こんにちは',
      );
    });

    test('通信の区切りが日本語の1文字の途中に来ても読める', () async {
      final bytes = utf8.encode(_event('delta', {'text': '星雲のかたち'}));
      // 1バイトずつ届く最悪のケース
      final events = await _parse(
        Stream.fromIterable([
          for (final b in bytes) [b],
        ]),
      );
      expect(events, hasLength(1));
      expect((events.single as ChatDeltaEvent).text, '星雲のかたち');
    });

    test('区切りの空行が通信の境目をまたいでも読める', () async {
      final raw =
          _event('delta', {'text': 'a'}) + _event('delta', {'text': 'b'});
      final bytes = utf8.encode(raw);
      final cut = raw.indexOf('\n\n') + 1; // 空行のちょうど真ん中で割る
      final events = await _parse(
        Stream.fromIterable([bytes.sublist(0, cut), bytes.sublist(cut)]),
      );
      expect(events.map((e) => (e as ChatDeltaEvent).text), ['a', 'b']);
    });

    test('最後の空行が無くても、残りを読む', () async {
      final events = await _parse(
        Stream.value(utf8.encode('event: delta\ndata: {"text":"end"}')),
      );
      expect((events.single as ChatDeltaEvent).text, 'end');
    });

    test('途中で壊れたイベントがあっても、ほかは読む', () async {
      final raw =
          'event: delta\ndata: {oops\n\n${_event('delta', {'text': 'ok'})}';
      final events = await _parse(Stream.value(utf8.encode(raw)));
      expect(events, hasLength(1));
      expect((events.single as ChatDeltaEvent).text, 'ok');
    });

    test('接続が切れたら、そこまでのイベントを渡してからエラーを伝える', () async {
      final controller = StreamController<List<int>>();
      final received = <ChatStreamEvent>[];
      final done = Completer<Object?>();
      parseChatSse(controller.stream).listen(
        received.add,
        onError: (Object e) {
          if (!done.isCompleted) done.complete(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete(null);
        },
      );
      controller.add(utf8.encode(_event('delta', {'text': 'a'})));
      await Future<void>.delayed(Duration.zero);
      controller.addError(const FormatException('connection lost'));
      expect(await done.future, isA<FormatException>());
      expect(received, hasLength(1));
    });
  });
}
