// lib/presentation/pages/profile/ai_notes_page.dart
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

/// AIメモ一覧(ページ版。webappの AiNotesPage):
/// 会話の中でAIが気づいた観察メモ(observations)を会話ごとに一覧表示し、
/// 個別削除や全消去、該当チャットを開く操作ができる。
class AiNotesPage extends HookConsumerWidget {
  const AiNotesPage({super.key});

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
          l.aiNotesLink,
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
                  l.aiMemoryIntro,
                  style: TextStyle(color: spMuted, fontSize: 13, height: 1.55),
                ),
                if (failed.value || (async.hasError && memory == null))
                  SpErrorText(l.selfPortraitLoadError),
                const SizedBox(height: 16),
                if (memory != null && memory.observationGroups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l.aiMemoryEmpty,
                        style: TextStyle(color: spMuted, fontSize: 14),
                      ),
                    ),
                  ),
                for (final g in memory?.observationGroups ?? const <ObservationGroup>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
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
                            _DeletableNoteRow(
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
class _DeletableNoteRow extends StatelessWidget {
  const _DeletableNoteRow({
    required this.child,
    required this.deleteLabel,
    required this.onDelete,
  });

  final Widget child;
  final String deleteLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          IconButton(
            onPressed: onDelete,
            tooltip: deleteLabel,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.close_rounded, size: 16, color: spMuted),
          ),
        ],
      ),
    );
  }
}
