// lib/presentation/widgets/ai_chat/ai_settings_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/core/utils/self_portrait_format.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_draft_sheets.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// AIチャット設定(チャットのヘッダーのボタンから開くシート。webappの AiSettingsSheet)。
/// 話し方の覚え書きと今の状況を見て消せる。AIのメモと自分像のページへの入口を置く。
/// 入口を押したら、このシートを閉じて[onOpenPage]を呼ぶ(呼び出し側がチャットも閉じてページを開く)。
Future<void> showAiSettingsSheet(
  BuildContext context, {
  required ChatWorld world,
  required void Function(String route) onOpenPage,
}) {
  final colors = ChatColors.of(world);
  return showChatSheet<void>(
    context,
    colors,
    (_) => _AiSettingsSheet(colors: colors, onOpenPage: onOpenPage),
  );
}

class _AiSettingsSheet extends HookConsumerWidget {
  const _AiSettingsSheet({required this.colors, required this.onOpenPage});

  final ChatColors colors;
  final void Function(String route) onOpenPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = colors;
    final locale = Localizations.localeOf(context).toString();
    final async = ref.watch(aiMemoryControllerProvider);
    final memory = async.asData?.value;
    final failed = useState(false);

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
