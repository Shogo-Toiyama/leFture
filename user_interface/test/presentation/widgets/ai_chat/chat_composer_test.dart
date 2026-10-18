import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_picker.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_composer_parts.dart';

import '../../../application/chat/fake_chat_files.dart';

class _Picker implements ChatFilePicker {
  List<PickedChatFile> camera = const [];
  List<PickedChatFile> photos = const [];
  List<PickedChatFile> files = const [];
  Object? error;

  @override
  Future<List<PickedChatFile>> takePhoto() async {
    if (error != null) throw error!;
    return camera;
  }

  @override
  Future<List<PickedChatFile>> pickPhotos() async {
    if (error != null) throw error!;
    return photos;
  }

  @override
  Future<List<PickedChatFile>> pickFiles() async {
    if (error != null) throw error!;
    return files;
  }
}

ChatAttachment _material(String id, String title, {bool selected = false}) =>
    ChatAttachment(
      id: id,
      threadId: 'T1',
      kind: 'pdf',
      status: ChatAttachmentStatus.ready,
      title: title,
      content: 'x',
      charCount: 1,
      tokenCount: 100,
      selected: selected,
      createdAt: DateTime.utc(2026, 10, 18),
      fileName: '$title.pdf',
    );

/// 1×1の透明なPNG(見本の画像として読めるもの)。
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

typedef _Sent = ({
  String content,
  List<ChatNewAttachment> attachments,
  List<ChatAttachmentRef> references,
});

void main() {
  late Directory work;
  late Directory temp;
  late FakeFileRepo repo;
  late FakeUploader uploader;
  late _Picker picker;
  late AppLocalizations l;
  var sent = <_Sent>[];
  var pending = <List<ChatAttachmentRef>>[];

  setUp(() {
    work = Directory.systemTemp.createTempSync('composer_work');
    temp = Directory.systemTemp.createTempSync('composer_temp');
    repo = FakeFileRepo();
    uploader = FakeUploader();
    picker = _Picker();
    sent = [];
    pending = [];
  });

  tearDown(() {
    work.deleteSync(recursive: true);
    temp.deleteSync(recursive: true);
  });

  PickedChatFile file(String name, String content) {
    final f = File('${work.path}/$name')..writeAsStringSync(content);
    return PickedChatFile(path: f.path, name: name);
  }

  Future<void> pumpComposer(
    WidgetTester tester, {
    List<ChatAttachment> mentionables = const [],
    List<ChatAttachment> selected = const [],
    ChatPrefill? prefill,
    ChatInsertRequest? insert,
    bool disabled = false,
  }) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatFilePickerProvider.overrideWithValue(picker),
          chatFilePipelineProvider.overrideWithValue(
            ChatFilePipeline(
              repository: repo,
              shrinker: FakeShrinker(_tinyPng),
              uploader: uploader,
              tempDirectory: () async => temp,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ChatComposer(
                  colors: ChatColors.universe,
                  placeholder: 'Ask',
                  disabled: disabled,
                  mentionables: mentionables,
                  selectedAttachments: selected,
                  prefill: prefill,
                  insertRequest: insert,
                  onOpenAttachmentList: () {},
                  onPendingChange: pending.add,
                  onSend: (content, attachments, references) => sent.add((
                    content: content,
                    attachments: attachments,
                    references: references,
                  )),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    l = AppLocalizations.of(tester.element(find.byType(ChatComposer)));
  }

  /// 実際のファイルの読み書きが終わるのを待つ。
  Future<void> io(WidgetTester tester) async {
    // 読み書きは何度かに分かれて、そのたびに実際の時間と、続きを動かすpumpが要る
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    // 準備中のチップは回り続けるので、pumpAndSettleは使えない
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  TextField input(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
  }

  group('＋メニュー', () {
    testWidgets('カメラ・写真・ファイル・長い文章・この会話の資料が並ぶ', (tester) async {
      await pumpComposer(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text(l.aiChatAttachCamera), findsOneWidget);
      expect(find.text(l.aiChatAttachPhoto), findsOneWidget);
      expect(find.text(l.aiChatAttachFile), findsOneWidget);
      expect(find.text(l.aiChatAttachLongText), findsOneWidget);
      expect(find.text(l.aiChatAttachSelect), findsOneWidget);
    });

    testWidgets('写真を選ぶと、チップと「@名前」が入る', (tester) async {
      picker.photos = [file('page1.png', 'x')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachPhoto);
      await io(tester);
      expect(find.text('page1.png'), findsWidgets);
      expect(input(tester).controller!.text, '@page1.png ');
    });

    testWidgets('カメラで撮ると、チップが出る', (tester) async {
      picker.camera = [file('photo.jpg', 'x')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachCamera);
      await io(tester);
      expect(find.text('photo.jpg'), findsWidgets);
    });

    testWidgets('許可がなくて開けなかったら、案内を出す', (tester) async {
      picker.error = StateError('denied');
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachCamera);
      await io(tester);
      expect(find.text(l.aiChatAttachPickFailed), findsOneWidget);
    });

    testWidgets('対応していないファイルは、理由を出す', (tester) async {
      picker.files = [file('movie.mp4', 'x')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachFile);
      await io(tester);
      expect(find.text(l.aiChatFileErrorUnsupported), findsOneWidget);
      expect(input(tester).controller!.text, isEmpty);
    });

    testWidgets('上限まで添付すると、メニューが選べなくなる', (tester) async {
      picker.files = [
        for (var i = 0; i < chatMaxAttachmentsPerMessage; i++)
          file('f$i.txt', 'text $i'),
      ];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachFile);
      await io(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text(
          l.aiChatAttachmentLimitPerMessage('$chatMaxAttachmentsPerMessage'),
        ),
        findsWidgets,
      );
    });
  });

  group('資料を添えて送る', () {
    testWidgets('テキストのファイルは、テキストの資料になって送られる', (tester) async {
      picker.files = [file('main.py', 'print(1)\n')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachFile);
      await io(tester);
      await tester.enterText(find.byType(TextField).first, '@main.py  explain');
      await tester.pump();
      await tapSend(tester);

      final s = sent.single;
      final a = s.attachments.single as ChatTextAttachment;
      expect(a.title, 'main.py');
      expect(a.content, 'print(1)\n');
      // 本文の「@名前」は、その資料の印になる
      expect(s.content, '⟦att:${a.localId}⟧  explain');
      expect(input(tester).controller!.text, isEmpty);
    });

    testWidgets('長い文章を書いて資料にできる', (tester) async {
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachLongText);
      await tester.enterText(
        find.byType(TextField).last,
        'First line\nsecond line',
      );
      await tester.pump();
      await tester.tap(find.text(l.aiChatAttachmentAdd));
      await tester.pumpAndSettle();
      expect(input(tester).controller!.text, '@First line ');
      await tapSend(tester);
      final a = sent.single.attachments.single as ChatTextAttachment;
      expect(a.content, 'First line\nsecond line');
    });

    testWidgets('準備が終わるまで送れない(アップロード中)', (tester) async {
      uploader.gate = Completer<void>();
      picker.photos = [file('scan.pdf', 'x')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachPhoto);
      await io(tester);
      await tester.enterText(find.byType(TextField).first, '@scan.pdf hi');
      await tester.pump();
      await tapSend(tester);
      expect(sent, isEmpty);

      uploader.gate!.complete();
      await io(tester);
      await tapSend(tester);
      final a = sent.single.attachments.single as ChatFileAttachment;
      expect(a.attachmentId, 'att-1');
      expect(sent.single.content, '⟦att:att-1⟧ hi');
    });

    testWidgets('資料だけを送ることもできる', (tester) async {
      picker.files = [file('a.txt', 'hello')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachFile);
      await io(tester);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tapSend(tester);
      expect(sent.single.attachments, hasLength(1));
      expect(sent.single.content, isEmpty);
    });

    testWidgets('チップの×で資料を外すと、「@名前」も消える', (tester) async {
      picker.files = [file('a.txt', 'hello')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachFile);
      await io(tester);
      expect(input(tester).controller!.text, '@a.txt ');
      await tester.tap(
        find.descendant(
          of: find.byType(ChatDraftChip),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pump();
      expect(find.text('a.txt'), findsNothing);
      expect(input(tester).controller!.text, isEmpty);
    });
  });

  group('「@名前」', () {
    testWidgets('「@」を打つと候補が出て、選ぶと名前が入る', (tester) async {
      await pumpComposer(
        tester,
        mentionables: [_material('m1', 'Lecture notes')],
      );
      await tester.enterText(find.byType(TextField).first, 'see @');
      await tester.pump();
      expect(find.text(l.aiChatMentionPickerTitle), findsOneWidget);
      await tester.tap(find.text('Lecture notes'));
      await tester.pump();
      expect(input(tester).controller!.text, 'see @Lecture notes ');
      expect(find.text(l.aiChatMentionPickerTitle), findsNothing);

      await tapSend(tester);
      expect(sent.single.content, 'see ⟦att:m1⟧');
      final ref = sent.single.references.single;
      expect(ref.attachmentId, 'm1');
      expect(ref.mode, ChatAttachmentMode.mention);
    });

    testWidgets('「全文で添付」を選ぶと、全文で指す', (tester) async {
      await pumpComposer(tester, mentionables: [_material('m1', 'Notes')]);
      await tester.enterText(find.byType(TextField).first, '@no');
      await tester.pump();
      await tester.tap(find.text(l.aiChatAttachFull));
      await tester.pump();
      await tapSend(tester);
      expect(sent.single.references.single.mode, ChatAttachmentMode.full);
    });

    testWidgets('合う資料が無いときは、その案内が出る', (tester) async {
      await pumpComposer(tester, mentionables: [_material('m1', 'Notes')]);
      await tester.enterText(find.byType(TextField).first, '@zzz');
      await tester.pump();
      expect(find.text(l.aiChatMentionPickerEmpty), findsOneWidget);
    });

    testWidgets('資料が無い会話では、候補を出さない', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField).first, 'see @');
      await tester.pump();
      expect(find.text(l.aiChatMentionPickerTitle), findsNothing);
    });

    testWidgets('名前の途中を消すと、名前ごと消える', (tester) async {
      picker.files = [file('notes.txt', 'hello')];
      await pumpComposer(tester);
      await choose(tester, l.aiChatAttachFile);
      await io(tester);
      expect(input(tester).controller!.text, '@notes.txt ');
      // バックスペースで「t」を1文字消した状態
      await tester.enterText(find.byType(TextField).first, '@notes.tx ');
      await tester.pump();
      expect(input(tester).controller!.text, ' ');
      // 資料のチップは残る(外すのはチップの×)
      expect(find.text('notes.txt'), findsOneWidget);
    });

    testWidgets('名前にカーソルがあると操作が出て、メンション⇄全文を切り替えられる', (tester) async {
      await pumpComposer(
        tester,
        mentionables: [_material('m1', 'Notes')],
        prefill: const ChatPrefill(
          text: 'about ⟦att:m1⟧ now',
          nonce: 1,
          attachments: [],
          references: [
            ChatAttachmentRef(
              attachmentId: 'm1',
              mode: ChatAttachmentMode.mention,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(input(tester).controller!.text, 'about @Notes now');

      // カーソルを名前の中に置く
      final controller = input(tester).controller!;
      controller.selection = const TextSelection.collapsed(offset: 9);
      await tester.pump();
      expect(find.text(l.aiChatAttachView), findsOneWidget);
      expect(find.text(l.aiChatMentionToFull), findsOneWidget);
      await tester.tap(find.text(l.aiChatMentionToFull));
      await tester.pump();
      expect(find.text(l.aiChatMentionToMention), findsOneWidget);

      await tapSend(tester);
      expect(sent.single.references.single.mode, ChatAttachmentMode.full);
      expect(sent.single.content, 'about ⟦att:m1⟧ now');
    });

    testWidgets('指している既存の資料の変化を知らせる', (tester) async {
      await pumpComposer(tester, mentionables: [_material('m1', 'Notes')]);
      await tester.enterText(find.byType(TextField).first, '@');
      await tester.pump();
      await tester.tap(find.text('Notes'));
      await tester.pump();
      await tester.pump();
      expect(pending.last.single.attachmentId, 'm1');
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.pump();
      expect(pending.last, isEmpty);
    });

    testWidgets('資料の一覧からの依頼で、名前が入る', (tester) async {
      final notes = _material('m1', 'Notes');
      await pumpComposer(
        tester,
        mentionables: [notes],
        insert: ChatInsertRequest(
          attachment: notes,
          mode: ChatInsertMode.full,
          nonce: 1,
        ),
      );
      // 依頼は更新で届く
      await pumpComposer(
        tester,
        mentionables: [notes],
        insert: ChatInsertRequest(
          attachment: notes,
          mode: ChatInsertMode.full,
          nonce: 2,
        ),
      );
      await tester.pump();
      expect(input(tester).controller!.text.contains('@Notes'), isTrue);
    });
  });

  group('長さ', () {
    testWidgets('上限を超える貼り付けは、入力欄に入れず資料の編集へ回る', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'a' * (chatMaxMessageChars + 1),
      );
      await tester.pumpAndSettle();
      expect(input(tester).controller!.text, isEmpty);
      expect(
        find.text(l.aiChatAttachmentPasteNotice('4,000')),
        findsOneWidget,
      );
    });

    testWidgets('上限を超えて打つと、送れずに「資料にする」が出る', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'a' * chatMaxMessageChars,
      );
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).first,
        'a' * (chatMaxMessageChars + 1),
      );
      await tester.pump();
      expect(find.text(l.aiChatErrorTooLong('4,000')), findsOneWidget);
      await tapSend(tester);
      expect(sent, isEmpty);
      await tester.tap(find.text(l.aiChatAttachmentConvert));
      await tester.pumpAndSettle();
      expect(
        find.text(l.aiChatAttachmentPasteNotice('4,000')),
        findsOneWidget,
      );
    });
  });

  group('入れ直し・全文で読んでいる資料', () {
    testWidgets('送れなかった送信を戻すと、本文・資料・指した資料が戻る', (tester) async {
      await pumpComposer(
        tester,
        mentionables: [_material('m1', 'Notes')],
        prefill: const ChatPrefill(
          text: 'see ⟦att:t1⟧ and ⟦att:f1⟧ and ⟦att:m1⟧',
          nonce: 1,
          attachments: [
            ChatTextAttachment(localId: 't1', title: 'Essay', content: 'c'),
            ChatFileAttachment(
              attachmentId: 'f1',
              fileName: 'slides.pdf',
              fileKind: ChatFileKind.pdf,
            ),
          ],
          references: [
            ChatAttachmentRef(
              attachmentId: 'm1',
              mode: ChatAttachmentMode.full,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(
        input(tester).controller!.text,
        'see @Essay and @slides.pdf and @Notes',
      );
      expect(find.text('Essay'), findsOneWidget);
      expect(find.text('slides.pdf'), findsOneWidget);
      await tapSend(tester);
      final s = sent.single;
      expect(s.content, 'see ⟦att:t1⟧ and ⟦att:f1⟧ and ⟦att:m1⟧');
      expect(s.attachments, hasLength(2));
      expect(s.references.single.mode, ChatAttachmentMode.full);
    });

    testWidgets('全文で読んでいる資料はチップで見え、×でやめられる', (tester) async {
      String? unselected;
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            chatFilePickerProvider.overrideWithValue(picker),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: ChatComposer(
                colors: ChatColors.universe,
                placeholder: 'Ask',
                selectedAttachments: [_material('m1', 'Notes', selected: true)],
                onUnselectAttachment: (id) => unselected = id,
                onSend: (_, _, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      l = AppLocalizations.of(tester.element(find.byType(ChatComposer)));
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text(l.aiChatAttachPinned), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(ChatPinnedChip),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      expect(unselected, 'm1');
    });
  });
}
