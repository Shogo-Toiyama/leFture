// lib/presentation/widgets/ai_chat/chat_page_context.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_chat_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/ai_share_consent_dialog.dart';

/// 今いる画面がチャットに伝えること(webappの ChatPanelContext の pageScreen と、ルートの講義)。
/// 送られるのはページの種類とIDだけで、本文はバックエンドがDBから読む。
class ChatPageContext {
  const ChatPageContext({
    this.world = ChatWorld.universe,
    this.screen,
    this.lectureId,
    this.courseId,
  });

  /// 画面の世界。宇宙の画面はダーク、Deep Notesなど紙の画面はライトのシートが開く。
  final ChatWorld world;

  /// 見せているページ(Deep Notesのトピック・復習カード・Fun Fact)。無ければnull。
  final ChatScreenRef? screen;

  /// 話題にする講義。
  final String? lectureId;

  /// 話題にするコース(コースの画面。講義を見ているときは講義からコースが分かるので付けない)。
  final String? courseId;
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
    this.courseId,
    this.active = true,
  });

  final Widget child;
  final ChatWorld world;
  final ChatScreenRef? screen;
  final String? lectureId;
  final String? courseId;

  /// falseなら登録しない(横にスワイプする講義のページで、表示中のページだけを登録するため。
  /// 包む・外すを切り替えると中身の状態が作り直されるので、包んだまま登録だけを切り替える)。
  final bool active;

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
    courseId: widget.courseId,
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
        old.courseId != widget.courseId ||
        old.active != widget.active ||
        old.screen?.kind != widget.screen?.kind ||
        old.screen?.id != widget.screen?.id ||
        old.screen?.topicNumber != widget.screen?.topicNumber;
    if (changed) _scheduleRegister();
  }

  /// 構築中にプロバイダーを書き換えないよう、構築が終わってから登録する。
  void _scheduleRegister() {
    scheduleMicrotask(() {
      if (!mounted) return;
      if (widget.active) {
        _stack.register(_token, _value);
        _registered = true;
      } else if (_registered) {
        _stack.unregister(_token);
        _registered = false;
      }
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

/// チャットで入力した内容・資料をAIサービスへ送ることへの同意。今の版で同意済みならそのまま、
/// まだならダイアログを出して聞く。同意されなければfalse(チャットは開かない)。
Future<bool> ensureAiChatConsent(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(userProfileRepositoryProvider);
  try {
    if (await repo.hasConsentedToAiChatShare()) return true;
  } catch (_) {
    // 同意の記録が読めなくても、聞き直すだけ(読めないまま通すことはしない)
  }
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  final agreed = await showAiShareConsentDialog(
    context,
    title: l10n.aiChatConsentDialogTitle,
    message: l10n.aiChatConsentDialogMessage,
  );
  if (!agreed) return false;
  try {
    await repo.markAiChatShareConsent();
  } catch (_) {
    // 記録できなかったときは、次に開くときにまた聞く。今回は同意されたので開く
  }
  return true;
}

/// 講義の名前(チャットの講義のチップに出す)。引けなければnull(チップが出ないだけで、チャットは開ける)。
Future<String?> chatLectureTitle(WidgetRef ref, String? lectureId) async {
  if (lectureId == null) return null;
  try {
    final lecture = await ref
        .read(lectureRepositoryProvider)
        .watchLectureById(lectureId)
        .first;
    return lecture?.displayTitle;
  } catch (_) {
    return null;
  }
}

/// チャットのチップに出すコース名。手元のコース一覧から引く(無ければnull)。
Future<String?> chatCourseTitle(WidgetRef ref, String? courseId) async {
  if (courseId == null) return null;
  try {
    final courses = await ref.read(courseListProvider.future);
    for (final c in courses) {
      if (c.id == courseId) return c.displayTitle;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 今の画面の情報つきでチャットのシートを開く。[selection]は「Ask」で添える選択。
Future<void> openAiChat(
  BuildContext context,
  WidgetRef ref, {
  ChatSelection? selection,
  VoidCallback? onOpenAiSettings,
}) async {
  if (!await ensureAiChatConsent(context, ref)) return;
  if (!context.mounted) return;
  final page = ref.read(chatPageContextProvider);
  final lectureId = page.lectureId;
  final lectureTitle = await chatLectureTitle(ref, lectureId);
  // 講義を見ているときはコースを付けない(講義からコースが分かる)
  final courseId = lectureId == null ? page.courseId : null;
  final courseTitle = await chatCourseTitle(ref, courseId);
  if (!context.mounted) return;
  await showAiChatSheet(
    context,
    world: page.world,
    lectureId: lectureTitle == null ? null : lectureId,
    lectureTitle: lectureTitle,
    courseId: courseTitle == null ? null : courseId,
    courseTitle: courseTitle,
    selection: selection,
    screen: page.screen,
    onOpenAiSettings: onOpenAiSettings,
  );
}
