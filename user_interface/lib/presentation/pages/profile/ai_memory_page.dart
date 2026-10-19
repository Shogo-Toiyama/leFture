// lib/presentation/pages/profile/ai_memory_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/core/utils/self_portrait_format.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/sp_common.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_chat_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// AIチャット設定(ページ版。webappの AiMemoryPage): 話し方の覚え書き・今の状況と、
/// AIのメモ(観察)を会話ごとに。アカウントページとチャットのシートから来る。
/// 仮説(AIが次に聞いてみたいこと)は見せない。
class AiMemoryPage extends HookConsumerWidget {
  const AiMemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final async = ref.watch(aiMemoryControllerProvider);
    final memory = async.asData?.value;
    final failed = useState(false);

    Future<void> act(Future<void> Function() action) async {
      try {
        await action();
        failed.value = false;
      } catch (_) {
        failed.value = true;
      }
    }

    final controller = ref.read(aiMemoryControllerProvider.notifier);

    Future<void> confirmForgetAll() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: spSheetBackground,
          title: Text(
            l.aiMemoryForgetAll,
            style: const TextStyle(color: spText, fontSize: 17),
          ),
          content: Text(
            l.aiMemoryForgetConfirmMessage('${memory?.observationCount ?? 0}'),
            style: TextStyle(color: spMuted, fontSize: 14, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                MaterialLocalizations.of(ctx).cancelButtonLabel,
                style: TextStyle(color: spMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                MaterialLocalizations.of(ctx).deleteButtonTooltip,
                style: const TextStyle(color: AppColors.correctionRed),
              ),
            ),
          ],
        ),
      );
      if (ok == true) await act(controller.forgetAll);
    }

    Widget memoRow(AiMemo m) => _DeletableRow(
      deleteLabel: l.aiMemoDelete,
      onDelete: () => act(() => controller.removeMemo(m.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.content,
            style: const TextStyle(color: spText, fontSize: 14, height: 1.55),
          ),
          if (m.expiresAt != null)
            Text(
              l.aiMemoUntil(shortDate(m.expiresAt, locale)),
              style: TextStyle(color: spMuted, fontSize: 12),
            ),
        ],
      ),
    );

    Widget memoSection(List<AiMemo> memos) => SpCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: memos.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l.aiMemoEmpty,
                style: TextStyle(color: spMuted, fontSize: 13.5),
              ),
            )
          : Column(children: [for (final m in memos) memoRow(m)]),
    );

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        backgroundColor: AppColors.universe.voidBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: spText,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l.aiSettingsPageTitle,
          style: const TextStyle(
            color: spText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: memory == null && !async.hasError
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.starGold),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                Text(
                  l.aiSettingsPageIntro,
                  style: TextStyle(color: spMuted, fontSize: 13.5, height: 1.5),
                ),
                if (failed.value || (async.hasError && memory == null))
                  SpErrorText(l.selfPortraitLoadError),

                SpSectionLabel(l.aiMemoStyleSection),
                memoSection(memory?.styles ?? const []),
                SpSectionLabel(l.aiMemoSituationSection),
                memoSection(memory?.situations ?? const []),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.aiMemoOneTimeNote,
                    style: TextStyle(color: spMuted, fontSize: 12, height: 1.5),
                  ),
                ),

                SpSectionLabel(l.aiNotesLink),
                Text(
                  l.aiMemoryIntro,
                  style: TextStyle(color: spMuted, fontSize: 12.5, height: 1.55),
                ),
                const SizedBox(height: 10),
                if (memory != null && memory.observationGroups.isEmpty)
                  Text(
                    l.aiMemoryEmpty,
                    style: TextStyle(color: spMuted, fontSize: 13.5),
                  ),
                for (final g in memory?.observationGroups ?? const <ObservationGroup>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SpCard(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${g.threadTitle.isEmpty ? l.aiChatThreadUntitled : g.threadTitle} · ${shortDate(g.lastObservedAt, locale)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: spMuted, fontSize: 12),
                                ),
                              ),
                              InkWell(
                                onTap: () => unawaited(
                                  showAiChatSheet(
                                    context,
                                    world: ChatWorld.universe,
                                    threadId: g.threadId,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    l.selfPortraitOpenChat,
                                    style: const TextStyle(
                                      color: AppColors.starGold,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          for (final o in g.observations)
                            _DeletableRow(
                              deleteLabel: l.aiMemoryDeleteNote,
                              onDelete: () =>
                                  act(() => controller.removeObservation(o.id)),
                              child: Text(
                                o.note,
                                style: const TextStyle(
                                  color: spText,
                                  fontSize: 14,
                                  height: 1.55,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                if (memory != null && memory.observationCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                            onPressed: confirmForgetAll,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.correctionRed,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                            ),
                            child: Text(
                              l.aiMemoryForgetAll,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          Text(
                            l.aiMemoryForgetAllNote,
                            style: TextStyle(
                              color: spMuted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// 右に「消す」×がつく1行。
class _DeletableRow extends StatelessWidget {
  const _DeletableRow({
    required this.child,
    required this.onDelete,
    required this.deleteLabel,
  });

  final Widget child;
  final VoidCallback onDelete;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: child,
            ),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: deleteLabel,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: spMuted, size: 18),
          ),
        ],
      ),
    );
  }
}
