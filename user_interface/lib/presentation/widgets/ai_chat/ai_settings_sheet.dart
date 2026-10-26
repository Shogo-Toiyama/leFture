// lib/presentation/widgets/ai_chat/ai_settings_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/core/utils/self_portrait_format.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// AIチャット設定(チャットのヘッダーのボタンから開くシート。webappの AiSettingsSheet)。
/// チャット内メモ(この会話限定)と話し方の覚え書き・今の状況(全体共通)を見て消せる。
/// 入口を押したら、このシートを閉じて[onOpenPage]を呼ぶ(呼び出し側がチャットも閉じてページを開く)。
Future<void> showAiSettingsSheet(
  BuildContext context, {
  required ChatWorld world,
  required void Function(String route) onOpenPage,
  String? threadId,
}) {
  final colors = ChatColors.of(world);
  return showChatSheet<void>(
    context,
    colors,
    (_) => _AiSettingsSheet(
      colors: colors,
      onOpenPage: onOpenPage,
      threadId: threadId,
    ),
  );
}

class _AiSettingsSheet extends HookConsumerWidget {
  const _AiSettingsSheet({
    required this.colors,
    required this.onOpenPage,
    this.threadId,
  });

  final ChatColors colors;
  final void Function(String route) onOpenPage;
  final String? threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final locale = Localizations.localeOf(context).toString();
    final async = ref.watch(aiMemoryControllerProvider);
    final memory = async.asData?.value;
    final failed = useState(false);

    final threadNotes = useState<ChatThreadNotes?>(null);
    final loadingNotes = useState(false);

    useEffect(() {
      final tid = threadId;
      if (tid == null) {
        threadNotes.value = null;
        return null;
      }
      var cancelled = false;
      loadingNotes.value = true;
      ref.read(chatRepositoryProvider).fetchThreadNotes(tid).then((notes) {
        if (!cancelled) {
          threadNotes.value = notes;
          loadingNotes.value = false;
        }
      }).catchError((_) {
        if (!cancelled) {
          threadNotes.value = null;
          loadingNotes.value = false;
        }
      });
      return () => cancelled = true;
    }, [threadId]);

    Future<void> removeMemo(String id) async {
      try {
        await ref.read(aiMemoryControllerProvider.notifier).removeMemo(id);
        failed.value = false;
      } catch (_) {
        failed.value = true;
      }
    }

    Widget memoRows(List<AiMemo> memos) {
      if (memos.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(
            memory == null ? '…' : l.aiMemoEmpty,
            style: TextStyle(color: c.stageText, fontSize: 13.5),
          ),
        );
      }
      return Column(
        children: [
          for (final m in memos)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.content,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 14,
                              height: 1.55,
                            ),
                          ),
                          if (m.expiresAt != null)
                            Text(
                              l.aiMemoUntil(shortDate(m.expiresAt, locale)),
                              style: TextStyle(color: c.stageText, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => removeMemo(m.id),
                    tooltip: l.aiMemoDelete,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: c.actionForeground,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c.stageText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      ),
    );

    final notes = threadNotes.value;
    final allChatNotes = <({String category, String label, Color badgeBg, Color badgeFg, ChatThreadNoteItem item})>[
      if (notes != null) ...[
        for (final it in notes.purpose)
          (
            category: 'purpose',
            label: l.chatNotesCategoryPurpose,
            badgeBg: const Color(0x284F8CFF),
            badgeFg: const Color(0xFF79AEFF),
            item: it,
          ),
        for (final it in notes.stylePreferences)
          (
            category: 'style',
            label: l.chatNotesCategoryStyle,
            badgeBg: const Color(0x28FFB300),
            badgeFg: const Color(0xFFFFCA4D),
            item: it,
          ),
        for (final it in notes.context)
          (
            category: 'context',
            label: l.chatNotesCategoryContext,
            badgeBg: const Color(0x2EA855F7),
            badgeFg: const Color(0xFFD8B4FE),
            item: it,
          ),
        for (final it in notes.unresolved)
          (
            category: 'unresolved',
            label: l.chatNotesCategoryUnresolved,
            badgeBg: const Color(0x28EF4444),
            badgeFg: const Color(0xFFFCA5A5),
            item: it,
          ),
      ],
    ];

    Widget chatNotesSectionWidget() {
      if (allChatNotes.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(
            loadingNotes.value ? '…' : l.chatNotesEmpty,
            style: TextStyle(color: c.stageText, fontSize: 13),
          ),
        );
      }
      return Column(
        children: [
          for (final n in allChatNotes)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 3, 20, 3),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: c.bubbleBackground,
                  border: Border.all(color: c.bubbleBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: n.badgeBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            n.label,
                            style: TextStyle(
                              color: n.badgeFg,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (n.item.sourceTurn != null)
                          Text(
                            'turn ${n.item.sourceTurn}',
                            style: TextStyle(color: c.stageText, fontSize: 11),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      n.item.text,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    Widget link(String title, String sub, String route) => InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onOpenPage(route);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.strongText,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(color: c.stageText, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.actionForeground),
          ],
        ),
      ),
    );

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.aiSettingsTitle,
                    style: TextStyle(
                      color: c.strongText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: l.aiChatClose,
                  icon: Icon(Icons.close_rounded, color: c.actionForeground),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (failed.value || (async.hasError && memory == null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      l.selfPortraitLoadError,
                      style: TextStyle(color: c.danger, fontSize: 13),
                    ),
                  ),
                if (threadId != null) ...[
                  section(l.chatNotesSection),
                  chatNotesSectionWidget(),
                ],
                section(l.aiMemoStyleSection),
                memoRows(memory?.styles ?? const []),
                section(l.aiMemoSituationSection),
                memoRows(memory?.situations ?? const []),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    l.aiMemoOneTimeNote,
                    style: TextStyle(
                      color: c.stageText,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                section(l.aiMoreSection),
                link(
                  l.aiNotesLink,
                  l.aiNotesLinkSub('${memory?.observationCount ?? 0}'),
                  AppRoutes.aiNotes,
                ),
                link(
                  l.selfPortraitPageTitle,
                  l.selfPortraitLinkSub,
                  AppRoutes.profile,
                ),
              ],
            ),
          ),
        ],
      ),
    );

  }
}
