// lib/presentation/widgets/ai_chat/chat_page_context.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_chat_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// 今いる画面がチャットに伝えること(webappの ChatPanelContext の pageScreen と、ルートの講義)。
/// 送られるのはページの種類とIDだけで、本文はバックエンドがDBから読む。
class ChatPageContext {
  const ChatPageContext({
    this.world = ChatWorld.universe,
    this.screen,
    this.lectureId,
  });

  /// 画面の世界。宇宙の画面はダーク、Deep Notesなど紙の画面はライトのシートが開く。
  final ChatWorld world;

  /// 見せているページ(Deep Notesのトピック・復習カード・Fun Fact)。無ければnull。
  final ChatScreenRef? screen;

  /// 話題にする講義。
  final String? lectureId;
}

/// 重なった画面の登録の一覧。いちばん上(最後に登録した画面)が今の画面。上の画面が閉じると、
/// 下の画面の登録がまた効く(コース → 講義 → Deep Notes と開いて、Deep Notesを閉じたら講義に戻る)。
class ChatPageContextStack extends Notifier<List<(Object, ChatPageContext)>> {
  @override
  List<(Object, ChatPageContext)> build() => const [];

  /// [token]の画面を登録する(登録済みなら内容を差し替える)。
  void register(Object token, ChatPageContext context) {
    state = [
      for (final e in state)
        if (!identical(e.$1, token)) e,
      (token, context),
    ];
  }

  void unregister(Object token) {
    state = [
      for (final e in state)
        if (!identical(e.$1, token)) e,
    ];
  }
}

final chatPageContextStackProvider =
    NotifierProvider<ChatPageContextStack, List<(Object, ChatPageContext)>>(
      ChatPageContextStack.new,
    );

/// いま効いている画面の情報。
final chatPageContextProvider = Provider<ChatPageContext>((ref) {
  final stack = ref.watch(chatPageContextStackProvider);
  return stack.isEmpty ? const ChatPageContext() : stack.last.$2;
});

/// 画面を包んで、見ているページ・講義・世界をチャットに伝える(画面を離れたら外れる)。
/// webappの `useChatScreen` にあたる。
class ChatScreenScope extends ConsumerStatefulWidget {
  const ChatScreenScope({
    super.key,
    required this.child,
    this.world = ChatWorld.universe,
    this.screen,
    this.lectureId,
  });

  final Widget child;
  final ChatWorld world;
  final ChatScreenRef? screen;
  final String? lectureId;

  @override
  ConsumerState<ChatScreenScope> createState() => _ChatScreenScopeState();
}

class _ChatScreenScopeState extends ConsumerState<ChatScreenScope> {
  final _token = Object();
  late ChatPageContextStack _stack;
  bool _registered = false;

  ChatPageContext get _value => ChatPageContext(
    world: widget.world,
    screen: widget.screen,
    lectureId: widget.lectureId,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stack = ref.read(chatPageContextStackProvider.notifier);
  }

  @override
  void initState() {
    super.initState();
    _scheduleRegister();
  }

  @override
  void didUpdateWidget(ChatScreenScope old) {
    super.didUpdateWidget(old);
    final changed =
        old.world != widget.world ||
        old.lectureId != widget.lectureId ||
        old.screen?.kind != widget.screen?.kind ||
        old.screen?.id != widget.screen?.id ||
        old.screen?.topicNumber != widget.screen?.topicNumber;
    if (changed) _scheduleRegister();
  }

  /// 構築中にプロバイダーを書き換えないよう、構築が終わってから登録する。
  void _scheduleRegister() {
    scheduleMicrotask(() {
      if (!mounted) return;
      _stack.register(_token, _value);
      _registered = true;
    });
  }

  @override
  void dispose() {
    final stack = _stack;
    final registered = _registered;
    final token = _token;
    // 画面が外れる途中でプロバイダーを書き換えないよう、あとで外す
    if (registered) scheduleMicrotask(() => stack.unregister(token));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 今の画面の情報つきでチャットのシートを開く。[selection]は「Ask」で添える選択。
Future<void> openAiChat(
  BuildContext context,
  WidgetRef ref, {
  ChatSelection? selection,
  VoidCallback? onOpenAiSettings,
}) async {
  final page = ref.read(chatPageContextProvider);
  String? lectureTitle;
  final lectureId = page.lectureId;
  if (lectureId != null) {
    try {
      final lecture = await ref
          .read(lectureRepositoryProvider)
          .watchLectureById(lectureId)
          .first;
      lectureTitle = lecture?.displayTitle;
    } catch (_) {
      // 講義の名前が引けなくても、チャットは開ける(講義のチップが出ないだけ)
    }
  }
  if (!context.mounted) return;
  await showAiChatSheet(
    context,
    world: page.world,
    lectureId: lectureTitle == null ? null : lectureId,
    lectureTitle: lectureTitle,
    selection: selection,
    screen: page.screen,
    onOpenAiSettings: onOpenAiSettings,
  );
}
