// lib/presentation/pages/profile/ai_memory_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/sp_common.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// AIチャット設定(ページ版。webappの AiMemoryPage):
/// 話し方の覚え書き(Style)の管理と、AIのメモ(AI Notes)のサマリー・一括消去・詳細ページへのリンク。
/// 今の状況(Right Now)は一時的な文脈のためチャット内シート限定とし、ここからは除外。
class AiMemoryPage extends HookConsumerWidget {
  const AiMemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          m.content,
          style: const TextStyle(color: spText, fontSize: 14, height: 1.55),
        ),
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

    final observationCount = memory?.observationCount ?? 0;

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

                // 1. 話し方の覚え書き
                SpSectionLabel(l.aiMemoStyleSection),
                memoSection(memory?.styles ?? const []),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.aiMemoOneTimeNote,
                    style: TextStyle(color: spMuted, fontSize: 12, height: 1.5),
                  ),
                ),

                const SizedBox(height: 12),

                // 2. AIのメモ (サマリーカード)
                SpSectionLabel(l.aiNotesLink),
                SpCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 18,
                            color: AppColors.universe.textComet,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.aiNotesCount('$observationCount'),
                            style: const TextStyle(
                              color: spText,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.aiMemoryIntro,
                        style: TextStyle(
                          color: spMuted,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () => context.push(AppRoutes.aiNotes),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.aiNotesViewAll,
                                  style: const TextStyle(
                                    color: spText,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: spMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (observationCount > 0) ...[
                        const SizedBox(height: 14),
                        Divider(
                          color: Colors.white.withValues(alpha: 0.08),
                          height: 1,
                        ),
                        const SizedBox(height: 10),
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
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          l.aiMemoryForgetAllNote,
                          style: TextStyle(
                            color: spMuted,
                            fontSize: 11.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// 右に「消す」×がつく1行。
class _DeletableRow extends StatelessWidget {
  const _DeletableRow({required this.child, required this.deleteLabel, required this.onDelete});

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
