// lib/presentation/widgets/ai_chat/ai_chat_sheet.dart
import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/application/chat/chat_threads.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/core/utils/chat_citation_target.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/domain/plan_features.dart' as plan_features;
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_settings_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_citation_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_conversation_view.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_page_context.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_sheet_handle.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_sheet_physics.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_thread_list_view.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/sheet_style.dart';
import 'package:url_launcher/url_launcher.dart';

/// シートの枠(高さを測る・テストで見つける用)。
const aiChatSheetFrameKey = ValueKey('ai-chat-sheet-frame');

/// いま開いているチャットシート(開いていなければnull)。
ChatSheetHandle? _current;

/// AIチャットのシートを下から開く。
///
/// モーダルではなく、画面の上に重ねるシート。どの高さでも後ろは暗くならず、シートの外に見えている
/// メイン画面をそのまま触れる(チャットを開いたまま画面を操作できる)。
/// ページを移っても、チャットはずっと最上位に残る(裏の画面だけが変わる)。
///
/// 開いた直後は80%。つまみ(ヘッダー)を指で上下させると、指に合わせて動き、離した位置で止まる。
/// 素早く上へ → 100%、素早く下へ → 閉じる。15%より下で離しても閉じる。
/// つまみをタップすると、50%以下なら80%、それより高ければ30%。キーボードが出たら全画面。
/// 閉じても会話の受信は続くので、開き直せば生成途中の返答がそのまま見える。
///
/// すでに開いていれば、新しいシートは重ねず、開いているシートに[selection]や[threadId]を足す。
/// 開いた画面の世界([world])の色で出て、ページを移ると、移った先の画面の世界の色に切り替わる。
/// 返り値は、シートが閉じたときに完了する。
///
/// [threadId]を渡すとその会話を開く。渡さなければ、今開いている会話を続ける(新しい会話にするのは
/// ヘッダーの「新しい会話」)。[selection]は「Ask」で添える選択、[screen]は今見ているページ。
Future<void> showAiChatSheet(
  BuildContext context, {
  required ChatWorld world,
  String? threadId,
  String? lectureId,
  String? lectureTitle,
  String? courseId,
  String? courseTitle,
  ChatSelection? selection,
  ChatScreenRef? screen,
  VoidCallback? onOpenAiSettings,
}) {
  final open = _current;
  if (open != null && open.isOpen) {
    if (open.closing) {
      // 閉じている途中: 閉じ終わってから、新しく開く
      return open.closed.then(
        (_) => !context.mounted
            ? Future<void>.value()
            : showAiChatSheet(
                context,
                world: world,
                threadId: threadId,
                lectureId: lectureId,
                lectureTitle: lectureTitle,
                courseId: courseId,
                courseTitle: courseTitle,
                selection: selection,
                screen: screen,
                onOpenAiSettings: onOpenAiSettings,
              ),
      );
    }
    open.attach(selection: selection, threadId: threadId);
    return open.closed;
  }
  final handle = ChatSheetHandle();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => AiChatSheet(
      handle: handle,
      world: world,
      threadId: threadId,
      lectureId: lectureId,
      lectureTitle: lectureTitle,
      courseId: courseId,
      courseTitle: courseTitle,
      selection: selection,
      screen: screen,
      onOpenAiSettings: onOpenAiSettings,
    ),
  );
  _current = handle;
  Overlay.of(context, rootOverlay: true).insert(entry);
  chatSheetKeeper.register(entry);
  unawaited(
    handle.closed.then((_) {
      chatSheetKeeper.unregister(entry);
      if (identical(_current, handle)) _current = null;
      // 画面ごと片づけられたあと(アプリの終了・テスト)は、外す先がもう無い
      if (entry.mounted) {
        entry.remove();
        entry.dispose();
      }
    }),
  );
  return handle.closed;
}

/// 開いているチャットシートを閉じる(開いていなければ何もしない)。
void closeAiChatSheet({bool animate = true}) =>
    _current?.close(animate: animate);

/// チャットを開けない画面(録音・ログインまわり)。ここへ移ったらシートを閉じる。
bool _chatNotAllowedAt(String path) {
  const blocked = [
    AppRoutes.recording,
    AppRoutes.welcome,
    AppRoutes.introduction,
    AppRoutes.signIn,
    AppRoutes.signUp,
    AppRoutes.forgotPassword,
    AppRoutes.resetPassword,
    AppRoutes.onboarding,
    AppRoutes.deviceSetup,
    AppRoutes.authResult,
    AppRoutes.accountDeleted,
  ];
  return blocked.any((r) => path == r || path.startsWith('$r/'));
}

enum _SheetView { conversation, history }

/// シートを動かす間に、本体を最低この高さで組む(低いシートでは下の部分だけを見せる)。
/// 小さいシートで入力欄などがはみ出してエラーにならないようにするため。
const _bodyMinHeight = 300.0;

/// シート全体を最低この高さで組む。閉じる手前まで下げたとき(ヘッダーより低いとき)は、
/// 上のつまみとヘッダーだけを見せて、残りは枠で切る。
const _sheetMinHeight = 200.0;

/// キーボードがこの高さ以上出たら、シートは完全に全画面(キーボードの上いっぱい)になる。
const _keyboardFullAt = 120.0;

class AiChatSheet extends ConsumerStatefulWidget {
  const AiChatSheet({
    super.key,
    required this.handle,
    required this.world,
    this.threadId,
    this.lectureId,
    this.lectureTitle,
    this.courseId,
    this.courseTitle,
    this.selection,
    this.screen,
    this.onOpenAiSettings,
  });

  final ChatSheetHandle handle;
  final ChatWorld world;
  final String? threadId;
  final String? lectureId;
  final String? lectureTitle;
  final String? courseId;
  final String? courseTitle;
  final ChatSelection? selection;
  final ChatScreenRef? screen;

  /// AIの設定(覚え書き・AIのメモ・自分像への入口)を開く。nullなら、このシートが持つ設定のシート
  /// ([showAiSettingsSheet])を開く。
  final VoidCallback? onOpenAiSettings;

  @override
  ConsumerState<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<AiChatSheet>
    with SingleTickerProviderStateMixin {
  final _controller = ChatConversationController();
  late final AnimationController _anim = AnimationController(vsync: this);
  _SheetView _view = _SheetView.conversation;
  ChatSelection? _selection;

  // 見ているページ(ページを移ると、色・講義のチップなども今のページに追従する)
  late ChatWorld _world = widget.world;
  String? _lectureId;
  String? _lectureTitle;
  // コースの画面から開いたときのコース(講義を見ているときはnull)。外すのは講義のチップと同じフラグ
  String? _courseId;
  String? _courseTitle;
  ChatScreenRef? _screen;
  bool _lectureDetached = false;

  // 動き
  double _animFrom = 0;
  double _animTo = 0;
  Curve _animCurve = Curves.easeOutCubic;
  double _available = 1;
  bool _closing = false;
  GoRouter? _router;

  ChatSheetHandle get _handle => widget.handle;
  ValueNotifier<double> get _fraction => _handle.fraction;

  ChatConversation get _notifier => ref.read(chatConversationProvider.notifier);

  @override
  void initState() {
    super.initState();
    _selection = widget.selection;
    _lectureId = widget.lectureId;
    _lectureTitle = widget.lectureTitle;
    _courseId = widget.courseId;
    _courseTitle = widget.courseTitle;
    _screen = widget.screen;
    _handle.bind(
      animateTo: _animateTo,
      close: _close,
      attach: _attach,
      remove: _handle.finish,
    );
    _anim.addListener(() {
      final t = _animCurve.transform(_anim.value);
      _fraction.value = _animFrom + (_animTo - _animFrom) * t;
    });
    _fraction.value = 0;
    // 下から出てくる
    _animateTo(ChatSheetPhysics.opening, milliseconds: 280);

    final id = widget.threadId;
    if (id != null) {
      // 開く画面の構築が終わってから読み込みを始める(build中に状態を書き換えない)
      Future(() => _notifier.openThread(id));
    }
    ref.listenManual(chatPageContextProvider, (_, next) => _onPageChanged(next));
    // 会話の名前は最初の返答の途中でサーバーが付ける。返答が終わったら一覧を読み直して、
    // ヘッダーの名前に出す(webappの onTurnComplete と同じ)
    ref.listenManual(chatConversationProvider, (previous, next) {
      if (previous?.sending == true && !next.sending) _refreshThreadTitles();
    });
    // 一覧を一度も開いていない端末では、続きの会話の名前がまだ手元に無い
    if ((widget.threadId ?? ref.read(chatConversationProvider).threadId) !=
        null) {
      _refreshThreadTitles();
    }
  }

  void _refreshThreadTitles() {
    unawaited(
      ref
          .read(chatThreadActionsProvider.notifier)
          .refresh()
          .catchError((Object _) {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_onRoute);
      _router = router;
      router?.routerDelegate.addListener(_onRoute);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    _anim.dispose();
    // 外側から片づけられたときも、開いている扱いを残さない
    _handle.finish();
    super.dispose();
  }

  // ---- 動き ----

  void _animateTo(
    double target, {
    int milliseconds = 220,
    Curve curve = Curves.easeOutCubic,
  }) {
    if (_closing) return;
    _animFrom = _fraction.value;
    _animTo = target;
    _animCurve = curve;
    _anim
      ..duration = Duration(milliseconds: milliseconds)
      ..forward(from: 0);
  }

  /// 閉じる。[animate]なら下へ動かしてから消す。
  void _close({bool animate = true}) {
    if (_closing) return;
    _handle.closing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!animate) {
      _closing = true;
      _anim.stop();
      _handle.finish();
      return;
    }
    _animFrom = _fraction.value;
    _animTo = 0;
    _animCurve = Curves.easeInCubic;
    _anim
      ..duration = const Duration(milliseconds: 200)
      ..forward(from: 0).whenComplete(_handle.finish);
    _closing = true;
  }

  /// 開いているシートに、選択や会話を足す(「AIに聞く」・自分像の「会話を開く」から)。
  void _attach(ChatSelection? selection, String? threadId) {
    setState(() {
      if (selection != null) {
        _selection = selection;
        _view = _SheetView.conversation;
      }
    });
    if (threadId != null) _showConversation(threadId);
    // 低いところで開いていたら、入力欄が見える高さまで上げる
    if (_fraction.value < .5) _animateTo(ChatSheetPhysics.opening);
  }

  void _onDragStart(DragStartDetails d) {
    _anim.stop();
    // 動かすときはキーボードをしまう(高さの基準を、指に合わせるため)
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _fraction.value = ChatSheetPhysics.clampWhileDragging(
      _fraction.value - d.delta.dy / _available,
    );
  }

  void _onDragEnd(DragEndDetails d) {
    switch (releaseChatSheet(_fraction.value, d.velocity.pixelsPerSecond.dy)) {
      case ChatSheetClose():
        _close();
      case ChatSheetMoveTo(:final fraction):
        _animateTo(fraction);
      case ChatSheetStay():
        break;
    }
  }

  void _onHolderTap() =>
      _animateTo(ChatSheetPhysics.afterTap(_fraction.value));

  Future<bool> _onBack() async {
    // ダイアログや下から出るシートが開いているときは、先にそれを閉じる
    if (chatSheetKeeper.popupCount > 0) return false;
    _close();
    return true;
  }

  // ---- 見ているページ ----

  void _onRoute() {
    final router = _router;
    if (router == null) return;
    final path = router.routeInformationProvider.value.uri.path;
    if (_chatNotAllowedAt(path)) _close(animate: false);
  }

  void _onPageChanged(ChatPageContext page) {
    _screen = page.screen;
    // 宇宙の画面ならダーク、紙の画面(Deep Notesなど)ならライトに切り替わる
    _world = page.world;
    _onCourseChanged(page);
    if (page.lectureId == _lectureId) {
      if (mounted) setState(() {});
      return;
    }
    // 講義が変わった: 外していた講義のチップも、新しい講義では出し直す
    final id = page.lectureId;
    setState(() {
      _lectureId = null;
      _lectureTitle = null;
      _lectureDetached = false;
    });
    if (id == null) return;
    unawaited(() async {
      final title = await chatLectureTitle(ref, id);
      if (!mounted || title == null) return;
      // 調べている間にまたページが移っていたら、捨てる
      if (ref.read(chatPageContextProvider).lectureId != id) return;
      setState(() {
        _lectureId = id;
        _lectureTitle = title;
      });
    }());
  }

  /// コースの画面に移った・離れたとき、コースのチップを追従させる(講義を見ているときはコースを付けない)。
  void _onCourseChanged(ChatPageContext page) {
    final id = page.lectureId == null ? page.courseId : null;
    if (id == _courseId) return;
    setState(() {
      _courseId = null;
      _courseTitle = null;
      _lectureDetached = false;
    });
    if (id == null) return;
    unawaited(() async {
      final title = await chatCourseTitle(ref, id);
      if (!mounted || title == null) return;
      // 調べている間にまたページが移っていたら、捨てる
      final now = ref.read(chatPageContextProvider);
      if (now.lectureId != null || now.courseId != id) return;
      setState(() {
        _courseId = id;
        _courseTitle = title;
      });
    }());
  }

  /// AIチャット設定のシートを開く。ページへの入口を押したら、そのページへ進む。
  void _openAiSettings() {
    unawaited(
      showAiSettingsSheet(
        context,
        world: _world,
        onOpenPage: _goTo,
        threadId: ref.read(chatConversationProvider).threadId,
      ),
    );
  }

  // ---- 切り替え ----

  void _showConversation(String? threadId) {
    setState(() => _view = _SheetView.conversation);
    unawaited(_notifier.openThread(threadId));
  }

  void _newConversation() {
    setState(() {
      _view = _SheetView.conversation;
      _selection = null;
    });
    unawaited(_notifier.openThread(null));
  }

  // ---- 出典・リンク・購入 ----

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      // アプリ内ブラウザが開けない端末は、ふつうのブラウザで開く
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  void _openCitation(ChatCitation citation, List<String> specs) {
    unawaited(
      showChatCitationSheet(
        context,
        colors: ChatColors.of(_world),
        citation: citation,
        specs: specs,
        onOpenTarget: _openTarget,
      ),
    );
  }

  Future<void> _openTarget(ChatCitationTarget target) async {
    switch (target) {
      case CitationWebTarget():
        await _openLink(target.url);
      case CitationThreadTarget():
        _showConversation(target.threadId);
      case CitationCourseTarget():
        _goTo(chatCoursePath(target.courseId));
      case CitationLectureTarget():
        // 出典にコースが入っていなければ、端末の講義からコースを引く
        var courseId = target.courseId;
        if (courseId == null) {
          try {
            final lecture = await ref
                .read(lectureRepositoryProvider)
                .watchLectureById(target.lectureId)
                .first;
            courseId = lecture?.courseId;
          } catch (_) {}
        }
        final path = chatCitationPath(target, courseId);
        if (path != null && mounted) _goTo(path);
    }
  }

  /// アプリの画面へ移る。チャットは閉じずに、行き先の画面が見える高さ(30%)まで下げる。
  void _goTo(String path) {
    final router = GoRouter.of(context);
    if (_fraction.value > ChatSheetPhysics.collapsed) {
      _animateTo(ChatSheetPhysics.collapsed);
    }
    unawaited(router.push<void>(path));
  }

  void _buyCredits() => _goTo(AppRoutes.creditDetail);

  // ---- 表示 ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ChatColors.of(_world);
    final conversationState = ref.watch(chatConversationProvider);
    final isHistory = _view == _SheetView.history;
    final threadId = conversationState.threadId;
    final isNewConversation =
        !isHistory && (threadId == null && conversationState.messages.isEmpty);
    // 会話の名前は、スレッド一覧(端末のキャッシュ)から引く。名前が付く前は「新しい会話」
    final threadTitle = threadId == null
        ? null
        : ref
              .watch(chatThreadListProvider)
              .value
              ?.where((t) => t.id == threadId)
              .firstOrNull
              ?.title;
    final title = isHistory
        ? l10n.aiChatHistory
        : (threadTitle?.trim().isNotEmpty ?? false)
        ? threadTitle!.trim()
        : threadId == null
        ? l10n.aiChatNewConversation
        : l10n.aiChatThreadUntitled;
    final lectureId = _lectureDetached ? null : _lectureId;

    // 高さが変わっても作り直さない中身(指で動かす間は、枠の大きさだけが変わる)
    final sheet = Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 触れた瞬間からの動きを数える(動き出しの遅れをなくして、指にぴったり付ける)
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onTap: _onHolderTap,
            child: Column(
              children: [
                const SizedBox(height: kSheetHandleTop),
                SheetHandle(color: colors.actionForeground.withValues(alpha: .4)),
                const SizedBox(height: 6),
                _Header(
                  colors: colors,
                  title: title,
                  isHistory: isHistory,
                  isNewConversation: isNewConversation,
                  onBackOrHistory: () => setState(
                    () => _view = isHistory
                        ? _SheetView.conversation
                        : _SheetView.history,
                  ),
                  onNew: _newConversation,
                  onSettings: widget.onOpenAiSettings ?? _openAiSettings,
                  onClose: _close,
                ),
              ],
            ),
          ),
          if (!isHistory) _PlanNotice(colors: colors),
          Expanded(
            // 低いシートでも本体は最低の高さで組み、下の部分(最新の発言と入力欄)を見せる。
            // 指で動かす間に中身を作り直さないよう、組み方(大きさと位置)だけで合わせる
            child: ClipRect(
              child: CustomSingleChildLayout(
                delegate: const _BottomAlignedMinHeight(),
                child: isHistory
                    ? ChatThreadListView(
                        colors: colors,
                        activeThreadId: conversationState.threadId,
                        onSelect: _showConversation,
                        onNewConversation: _newConversation,
                        onDeleted: (id) {
                          if (id == conversationState.threadId) {
                            _newConversation();
                          }
                        },
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: ChatConversationView(
                          world: _world,
                          controller: _controller,
                          lectureId: lectureId,
                          lectureTitle: _lectureTitle,
                          courseId: _lectureDetached ? null : _courseId,
                          courseTitle: _courseTitle,
                          onDetachLecture: () =>
                              setState(() => _lectureDetached = true),
                          selection: _selection,
                          onClearSelection: () =>
                              setState(() => _selection = null),
                          // 講義のチップを外したら、その講義のページも添えない
                          screen: _lectureDetached ? null : _screen,
                          onOpenCitation: _openCitation,
                          onOpenLink: (url) => unawaited(_openLink(url)),
                          onBuyCredits: _buyCredits,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );

    final body = ValueListenableBuilder<double>(
        valueListenable: _fraction,
        child: sheet,
        builder: (context, fraction, child) {
          final media = MediaQuery.of(context);
          final keyboard = media.viewInsets.bottom;
          // 使える高さ(上の安全領域とシートの上の余白を除く)
          final available = media.size.height - media.padding.top - 8;
          _available = available <= 0 ? 1 : available;
          // キーボードが出たら、その上いっぱいまで広げる
          final blend = (keyboard / _keyboardFullAt).clamp(0.0, 1.0);
          final wanted = fraction * _available +
              (_available - fraction * _available) * blend;
          final height = wanted.clamp(0.0, _available - keyboard).toDouble();

          // シートの外には何も置かない(タッチはそのままメイン画面へ届く)
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                height: height,
                child: DecoratedBox(
                  key: aiChatSheetFrameKey,
                  decoration: BoxDecoration(
                    color: colors.sheet,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(kSheetRadius),
                    ),
                    border: Border.all(
                      color: colors.accent.withValues(
                        alpha: _world == ChatWorld.paper ? .28 : .35,
                      ),
                    ),
                    boxShadow: [
                      // 背景との境目を持ち上げるドロップシャドウ
                      const BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 32,
                        offset: Offset(0, -6),
                      ),
                      // 浮いて見えるゴールドのぼんやりした光(グロー)
                      BoxShadow(
                        color: colors.accent.withValues(
                          alpha: _world == ChatWorld.paper ? .18 : .24,
                        ),
                        blurRadius: 28,
                        spreadRadius: 1,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(kSheetRadius),
                    ),
                    // 高さによって木の形を変えない(変えると会話の画面が作り直される)
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: height < _sheetMinHeight
                          ? _sheetMinHeight
                          : height,
                      maxHeight: height < _sheetMinHeight
                          ? _sheetMinHeight
                          : height,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
    );
    // ルーターのあるアプリでは、戻る操作でページより先にシートを閉じる
    return Router.maybeOf(context) == null
        ? body
        : BackButtonListener(onBackButtonPressed: _onBack, child: body);
  }
}

/// 本体を最低[_bodyMinHeight]の高さで組み、下端に揃える(低いシートでは上が切れる)。
class _BottomAlignedMinHeight extends SingleChildLayoutDelegate {
  const _BottomAlignedMinHeight();

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: constraints.maxWidth,
        height: constraints.maxHeight < _bodyMinHeight
            ? _bodyMinHeight
            : constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(0, size.height - childSize.height);

  @override
  bool shouldRelayout(_BottomAlignedMinHeight oldDelegate) => false;
}

/// ヘッダーのボタン1つの大きさ(押せる範囲)。
const _buttonSize = 44.0;

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.title,
    required this.isHistory,
    required this.isNewConversation,
    required this.onBackOrHistory,
    required this.onNew,
    required this.onSettings,
    required this.onClose,
  });

  final ChatColors colors;
  final String title;
  final bool isHistory;
  final bool isNewConversation;
  final VoidCallback onBackOrHistory;
  final VoidCallback onNew;
  final VoidCallback? onSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback? onTap, {
      bool active = false,
    }) => IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _buttonSize,
        height: _buttonSize,
      ),
      icon: Icon(icon, size: 24, color: active ? c.accent : c.actionForeground),
    );

    final actions = <Widget>[];

    if (isHistory) {
      if (onSettings != null) {
        actions.add(button(Icons.tune_rounded, l.aiSettingsButton, onSettings));
      }
    } else if (isNewConversation) {
      if (onSettings != null) {
        actions.add(button(Icons.tune_rounded, l.aiSettingsButton, onSettings));
      }
    } else {
      if (isWide) {
        if (onSettings != null) {
          actions.add(button(Icons.tune_rounded, l.aiSettingsButton, onSettings));
        }
        actions.add(button(Icons.add_comment_rounded, l.aiChatNewConversation, onNew));
      } else {
        actions.add(
          _HeaderMoreMenu(
            colors: c,
            onNew: onNew,
            onSettings: onSettings,
            newLabel: l.aiChatNewConversation,
            settingsLabel: l.aiSettingsButton,
            tooltip: l.aiChatActionMore,
          ),
        );
      }
    }

    actions.add(button(Icons.close_rounded, l.aiChatClose, onClose));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          button(
            isHistory ? Icons.chevron_left_rounded : Icons.forum_rounded,
            isHistory
                ? MaterialLocalizations.of(context).backButtonTooltip
                : l.aiChatHistory,
            onBackOrHistory,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.strongText,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

enum _HeaderMoreChoice {
  newConversation,
  settings,
}

class _HeaderMoreMenu extends StatelessWidget {
  const _HeaderMoreMenu({
    required this.colors,
    required this.onNew,
    required this.onSettings,
    required this.newLabel,
    required this.settingsLabel,
    required this.tooltip,
  });

  final ChatColors colors;
  final VoidCallback onNew;
  final VoidCallback? onSettings;
  final String newLabel;
  final String settingsLabel;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final itemStyle = TextStyle(
      color: c.actionForegroundStrong,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

    return SizedBox(
      width: _buttonSize,
      height: _buttonSize,
      child: PopupMenuButton<_HeaderMoreChoice>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_horiz_rounded,
          size: 24,
          color: c.actionForeground,
        ),
        color: c.menuBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.menuBorder),
        ),
        constraints: const BoxConstraints(minWidth: 170),
        onSelected: (choice) {
          switch (choice) {
            case _HeaderMoreChoice.newConversation:
              onNew();
            case _HeaderMoreChoice.settings:
              onSettings?.call();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _HeaderMoreChoice.newConversation,
            child: Row(
              children: [
                Icon(
                  Icons.add_comment_rounded,
                  size: 18,
                  color: c.actionForeground,
                ),
                const SizedBox(width: 10),
                Text(newLabel, style: itemStyle),
              ],
            ),
          ),
          if (onSettings != null)
            PopupMenuItem(
              value: _HeaderMoreChoice.settings,
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: c.actionForeground,
                  ),
                  const SizedBox(width: 10),
                  Text(settingsLabel, style: itemStyle),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ヘッダーの下の細い注意書き: 今のプランでチャットが検索しない材料。
/// 回答役(LLM)にはプランを伝えず、案内はここだけで固定の文言で出す(回答のたびにプランの話が混ざって
/// 宣伝っぽくなるのを避けるため)。外れる材料が無いプラン(Core以上)と、プランを読み込む前は何も出さない。
class _PlanNotice extends ConsumerWidget {
  const _PlanNotice({required this.colors});

  final ChatColors colors;

  /// 材料の種類 → それをチャットで使うのに必要な機能(バックエンドの plan_features.py と同じ対応)。
  static const _sources = <(String, String)>[
    ('deep_note', plan_features.featureDeepNotesFull),
    ('transcript_topic', plan_features.featureSourceTranscriptView),
    ('keyword', plan_features.featureKeywordExtractionSubscriber),
    ('announcement', plan_features.featureAnnouncementGeneration),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(creditSummaryProvider).hasValue) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final excluded = [
      for (final (type, feature) in _sources)
        if (!ref.watch(hasFeatureProvider(feature)))
          chatSourceKindLabel(l, type),
    ];
    if (excluded.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(
        l.aiChatPlanExcludedSources(
          excluded.join(l.aiChatPlanExcludedSourcesSeparator),
        ),
        style: TextStyle(color: colors.stageText, fontSize: 11.5, height: 1.5),
      ),
    );
  }
}
