// lib/presentation/pages/profile/self_portrait/item_detail_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/core/utils/self_portrait_format.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/self_portrait/self_portrait_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/sp_common.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

const _itemMaxChars = 500;

enum _Mode { view, edit, reject }

/// 自分像の項目を開いたとき(webappの ItemDetailSheet): 根拠になった会話(本人の言葉)・書き直しの変化・
/// 「直す / 違う / 残したくない」(確認待ちの項目なら「残す / 残さない」)。
/// 会話を開くときは[onOpenChat]が呼ばれる(シートは閉じてから)。
Future<void> showItemDetailSheet(
  BuildContext context, {
  required ProfileItem item,
  required String categoryLabel,
  required void Function(String threadId) onOpenChat,
}) {
  return showSpSheet<void>(
    context,
    (_) => _ItemDetailSheet(
      item: item,
      categoryLabel: categoryLabel,
      onOpenChat: onOpenChat,
    ),
  );
}

class _ItemDetailSheet extends HookConsumerWidget {
  const _ItemDetailSheet({
    required this.item,
    required this.categoryLabel,
    required this.onOpenChat,
  });

  final ProfileItem item;
  final String categoryLabel;
  final void Function(String threadId) onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final detailAsync = ref.watch(selfPortraitItemDetailProvider(item.id));
    final detail = detailAsync.asData?.value;
    final mode = useState(_Mode.view);
    final draft = useTextEditingController();
    final reason = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);
    final content = detail?.content ?? item.content;

    Future<void> run(
      Future<void> Function(SelfPortraitRepository repo) action,
    ) async {
      busy.value = true;
      error.value = null;
      try {
        await ref
            .read(selfPortraitControllerProvider.notifier)
            .act(action);
        if (context.mounted) Navigator.of(context).pop();
      } catch (_) {
        error.value = l.selfPortraitActionFailed;
      } finally {
        busy.value = false;
      }
    }

    Future<void> confirmDiscard() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: spSheetBackground,
          title: Text(
            l.selfPortraitDiscardConfirmTitle,
            style: const TextStyle(color: spText, fontSize: 17),
          ),
          content: Text(
            l.selfPortraitDiscardConfirmMessage,
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
                l.selfPortraitDiscardConfirmButton,
                style: const TextStyle(color: AppColors.correctionRed),
              ),
            ),
          ],
        ),
      );
      if (ok == true) await run((repo) => repo.discard(item.id));
    }

    Widget actionRow({
      required IconData icon,
      required String title,
      required String hint,
      required VoidCallback onTap,
      Color? color,
    }) {
      return InkWell(
        onTap: busy.value ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color ?? spMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color ?? spText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(color: spMuted, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cancelLabel = MaterialLocalizations.of(context).cancelButtonLabel;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(title: categoryLabel),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  style: const TextStyle(color: spText, fontSize: 15.5, height: 1.6),
                ),
                if (detail?.editedByUser == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l.selfPortraitEditedByYou,
                      style: const TextStyle(
                        color: AppColors.starGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (error.value != null) SpErrorText(error.value!),
                if (detailAsync.hasError && detail == null)
                  SpErrorText(l.selfPortraitLoadError),
                const SizedBox(height: 14),
                if (mode.value == _Mode.edit) ...[
                  Text(
                    l.selfPortraitActionEdit,
                    style: const TextStyle(color: spText, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SpTextField(
                    controller: draft,
                    maxLength: _itemMaxChars,
                  ),
                  Text(
                    l.selfPortraitActionEditHint,
                    style: TextStyle(color: spMuted, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: draft,
                    builder: (context, value, _) {
                      final next = value.text.trim();
                      return Row(
                        children: [
                          SpPrimaryButton(
                            label: busy.value
                                ? l.selfPortraitSaving
                                : l.selfPortraitSave,
                            onPressed: busy.value || next.isEmpty || next == content
                                ? null
                                : () => run((repo) => repo.edit(item.id, next)),
                          ),
                          const SizedBox(width: 10),
                          SpSecondaryButton(
                            label: cancelLabel,
                            onPressed: () => mode.value = _Mode.view,
                          ),
                        ],
                      );
                    },
                  ),
                ] else if (mode.value == _Mode.reject) ...[
                  Text(
                    l.selfPortraitRejectReasonLabel,
                    style: const TextStyle(color: spText, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SpTextField(
                    controller: reason,
                    maxLines: 3,
                    maxLength: _itemMaxChars,
                    hint: l.selfPortraitRejectReasonPlaceholder,
                  ),
                  Text(
                    l.selfPortraitActionRejectHint,
                    style: TextStyle(color: spMuted, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SpPrimaryButton(
                        label: l.selfPortraitActionReject,
                        onPressed: busy.value
                            ? null
                            : () => run(
                                (repo) =>
                                    repo.reject(item.id, reason: reason.text),
                              ),
                      ),
                      const SizedBox(width: 10),
                      SpSecondaryButton(
                        label: cancelLabel,
                        onPressed: () => mode.value = _Mode.view,
                      ),
                    ],
                  ),
                ] else if (item.isPending) ...[
                  Text(
                    l.selfPortraitPendingNotice,
                    style: TextStyle(color: spMuted, fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SpPrimaryButton(
                        label: l.selfPortraitKeep,
                        onPressed: busy.value
                            ? null
                            : () => run((repo) => repo.keep(item.id)),
                      ),
                      const SizedBox(width: 10),
                      SpSecondaryButton(
                        label: l.selfPortraitDontKeep,
                        onPressed: busy.value
                            ? null
                            : () => run((repo) => repo.discard(item.id)),
                      ),
                    ],
                  ),
                ] else ...[
                  actionRow(
                    icon: Icons.edit_outlined,
                    title: l.selfPortraitActionEdit,
                    hint: l.selfPortraitActionEditHint,
                    color: AppColors.starGold,
                    onTap: () {
                      draft.text = content;
                      mode.value = _Mode.edit;
                    },
                  ),
                  actionRow(
                    icon: Icons.cancel_outlined,
                    title: l.selfPortraitActionReject,
                    hint: l.selfPortraitActionRejectHint,
                    onTap: () => mode.value = _Mode.reject,
                  ),
                  actionRow(
                    icon: Icons.delete_outline_rounded,
                    title: l.selfPortraitActionDiscard,
                    hint: l.selfPortraitActionDiscardHint,
                    color: AppColors.correctionRed,
                    onTap: confirmDiscard,
                  ),
                ],
                if (detail != null && detail.evidence.isNotEmpty) ...[
                  SpSectionLabel(l.selfPortraitEvidenceSection),
                  for (final ev in detail.evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SpCard(
                        padding: const EdgeInsets.all(12),
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenChat(ev.threadId);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${ev.threadTitle.isEmpty ? l.aiChatThreadUntitled : ev.threadTitle} · ${shortDate(ev.observedAt, locale)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: spMuted, fontSize: 12),
                                  ),
                                ),
                                Text(
                                  l.selfPortraitOpenChat,
                                  style: const TextStyle(
                                    color: AppColors.starGold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ev.quote != null
                                  ? l.selfPortraitQuote(ev.quote!)
                                  : ev.note,
                              style: const TextStyle(
                                color: spText,
                                fontSize: 13.5,
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (detail != null && detail.versions.isNotEmpty) ...[
                  SpSectionLabel(l.selfPortraitHistorySection),
                  for (final v in detail.versions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${l.selfPortraitUntil(shortDate(v.replacedAt, locale))}${v.content}',
                        style: TextStyle(color: spMuted, fontSize: 13, height: 1.5),
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
