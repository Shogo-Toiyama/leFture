// lib/presentation/widgets/ai_chat/ai_chat_sheet.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
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
import 'package:lefture/presentation/widgets/ai_chat/chat_thread_list_view.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:url_launcher/url_launcher.dart';

/// AIチャットのシートを下から開く。
///
/// 開いた画面の世界([world]: Homeなど宇宙の画面は[ChatWorld.universe]、Deep Notesなど紙の画面は
/// [ChatWorld.paper])の色で出る。半分の高さで開き、上へ引き上げると全画面、キーボードが出ても全画面。
/// 下へ引くか×で閉じる。閉じても会話の受信は続くので、開き直せば生成途中の返答がそのまま見える。
///
/// [threadId]を渡すとその会話を開く。渡さなければ、今開いている会話を続ける(新しい会話にするのは
/// ヘッダーの「新しい会話」)。[selection]は「Ask」で添える選択、[screen]は今見ているページ。
Future<void> showAiChatSheet(
  BuildContext context, {
  required ChatWorld world,
  String? threadId,
  String? lectureId,
  String? lectureTitle,
  ChatSelection? selection,
  ChatScreenRef? screen,
  VoidCallback? onOpenAiSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .5),
    builder: (_) => AiChatSheet(
      world: world,
      threadId: threadId,
      lectureId: lectureId,
      lectureTitle: lectureTitle,
      selection: selection,
      screen: screen,
      onOpenAiSettings: onOpenAiSettings,
    ),
  );
}

enum _SheetView { conversation, history }

/// 半分の高さで開く割合(使える高さに対して)。
const _halfFraction = .62;

class AiChatSheet extends ConsumerStatefulWidget {
  const AiChatSheet({
    super.key,
    required this.world,
    this.threadId,
    this.lectureId,
    this.lectureTitle,
    this.selection,
    this.screen,
    this.onOpenAiSettings,
  });

  final ChatWorld world;
  final String? threadId;
  final String? lectureId;
  final String? lectureTitle;
  final ChatSelection? selection;
  final ChatScreenRef? screen;

  /// AIの設定(覚え書き・AIのメモ・自分像への入口)を開く。nullなら、このシートが持つ設定のシート
  /// ([showAiSettingsSheet])を開く。
  final VoidCallback? onOpenAiSettings;

  @override
  ConsumerState<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<AiChatSheet> {
  final _controller = ChatConversationController();
  _SheetView _view = _SheetView.conversation;
  bool _expanded = false;
  double _dragged = 0;
  bool _lectureDetached = false;
  ChatSelection? _selection;

  ChatConversation get _notifier => ref.read(chatConversationProvider.notifier);

  @override
  void initState() {
    super.initState();
    _selection = widget.selection;
    final id = widget.threadId;
    if (id != null) {
      // 開く画面の構築が終わってから読み込みを始める(build中に状態を書き換えない)
      Future(() => _notifier.openThread(id));
    }
  }

  /// AIチャット設定のシートを開く。ページへの入口を押したら、チャットも閉じてそのページへ進む。
  void _openAiSettings() {
    final router = GoRouter.of(context);
    unawaited(
      showAiSettingsSheet(
        context,
        world: widget.world,
        onOpenPage: (route) {
          Navigator.of(context).pop();
          unawaited(router.push(route));
        },
      ),
    );
  }

  // ---- シートの高さ ----

  void _onDragUpdate(DragUpdateDetails d) => _dragged += d.delta.dy;

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final up = _dragged < -30 || velocity < -500;
    final down = _dragged > 30 || velocity > 500;
    _dragged = 0;
    if (up) {
      setState(() => _expanded = true);
    } else if (down) {
      if (_expanded) {
        setState(() => _expanded = false);
      } else {
        Navigator.of(context).maybePop();
      }
    }
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
        colors: ChatColors.of(widget.world),
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

  /// シートを閉じてから、アプリの画面へ移る。
  void _goTo(String path) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push<void>(path));
  }

  void _buyCredits() => _goTo(AppRoutes.creditDetail);

  // ---- 表示 ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ChatColors.of(widget.world);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // 使える高さ(上の安全領域とシートの上の余白を除く)
    final available = media.size.height - media.padding.top - 8;
    final target = (_expanded || keyboard > 0)
        ? available
        : available * _halfFraction;
    final height = target.clamp(0.0, available - keyboard).toDouble();
    final conversationState = ref.watch(chatConversationProvider);
    final attachmentCount = [
      for (final a in conversationState.attachments)
        if (a.status == ChatAttachmentStatus.ready ||
            a.status == ChatAttachmentStatus.processing)
          a,
    ].length;
    final isHistory = _view == _SheetView.history;
    final title = isHistory
        ? l10n.aiChatHistory
        : conversationState.threadId == null
        ? l10n.aiChatNewConversation
        : l10n.aiChatThreadUntitled;
    final lectureId = _lectureDetached ? null : widget.lectureId;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: colors.menuBorder)),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 30),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.actionForeground.withValues(
                              alpha: .4,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      _Header(
                        colors: colors,
                        title: title,
                        isHistory: isHistory,
                        attachmentCount: isHistory ? 0 : attachmentCount,
                        onBackOrHistory: () => setState(
                          () => _view = isHistory
                              ? _SheetView.conversation
                              : _SheetView.history,
                        ),
                        onNew: _newConversation,
                        onAttachments: _controller.openAttachmentList,
                        onSettings: widget.onOpenAiSettings ?? _openAiSettings,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                if (!isHistory) _PlanNotice(colors: colors),
                Expanded(
                  child: isHistory
                      ? ChatThreadListView(
                          colors: colors,
                          activeThreadId: conversationState.threadId,
                          onSelect: _showConversation,
                          onDeleted: (id) {
                            if (id == conversationState.threadId) {
                              _newConversation();
                            }
                          },
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: ChatConversationView(
                            world: widget.world,
                            controller: _controller,
                            lectureId: lectureId,
                            lectureTitle: widget.lectureTitle,
                            onDetachLecture: () =>
                                setState(() => _lectureDetached = true),
                            selection: _selection,
                            onClearSelection: () =>
                                setState(() => _selection = null),
                            // 講義のチップを外したら、その講義のページも添えない
                            screen: _lectureDetached ? null : widget.screen,
                            onOpenCitation: _openCitation,
                            onOpenLink: (url) => unawaited(_openLink(url)),
                            onBuyCredits: _buyCredits,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.title,
    required this.isHistory,
    required this.attachmentCount,
    required this.onBackOrHistory,
    required this.onNew,
    required this.onAttachments,
    required this.onSettings,
    required this.onClose,
  });

  final ChatColors colors;
  final String title;
  final bool isHistory;
  final int attachmentCount;
  final VoidCallback onBackOrHistory;
  final VoidCallback onNew;
  final VoidCallback onAttachments;
  final VoidCallback? onSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = colors;
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback? onTap, {
      bool active = false,
    }) => IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: active ? c.accent : c.actionForeground),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
      child: Row(
        children: [
          button(
            isHistory ? Icons.chevron_left_rounded : Icons.history_rounded,
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
          if (attachmentCount > 0)
            Stack(
              clipBehavior: Clip.none,
              children: [
                button(
                  Icons.attach_file_rounded,
                  l.aiChatAttachmentsOpen('$attachmentCount'),
                  onAttachments,
                ),
                Positioned(
                  right: 2,
                  top: 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$attachmentCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          button(Icons.edit_square, l.aiChatNewConversation, onNew),
          if (onSettings != null)
            button(Icons.tune_rounded, l.aiSettingsButton, onSettings),
          button(Icons.close_rounded, l.aiChatClose, onClose),
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
