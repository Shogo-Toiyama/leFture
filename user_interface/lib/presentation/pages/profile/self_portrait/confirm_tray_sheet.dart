// lib/presentation/pages/profile/self_portrait/confirm_tray_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/self_portrait/self_portrait_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/sp_common.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// 確認トレイ(webappの ConfirmTraySheet): センシティブな分野の項目(残す / 残さない)と、
/// 本人が書いた欄への書き直し案(反映する / 今のまま)。確認するまで、確認待ちの項目は
/// チャットやFun Factのどこにも使われない。
Future<void> showConfirmTraySheet(BuildContext context) =>
    showSpSheet<void>(context, (_) => const _ConfirmTraySheet());

String _areaLabel(AppLocalizations l, String sensitive) => switch (sensitive) {
  'religion' => l.selfPortraitAreaReligion,
  'health' => l.selfPortraitAreaHealth,
  'sexuality' => l.selfPortraitAreaSexuality,
  'politics' => l.selfPortraitAreaPolitics,
  'ethnicity' => l.selfPortraitAreaEthnicity,
  _ => l.selfPortraitAreaSensitive,
};

class _ConfirmTraySheet extends HookConsumerWidget {
  const _ConfirmTraySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(selfPortraitControllerProvider).asData?.value;
    final pending = data?.pending ?? const <ProfileItem>[];
    final proposals = data?.proposals ?? const <CoverProposal>[];
    final busyId = useState<String?>(null);
    final error = useState<String?>(null);

    Future<void> run(
      String id,
      Future<void> Function(SelfPortraitRepository repo) action,
    ) async {
      busyId.value = id;
      error.value = null;
      final wasLast = pending.length + proposals.length <= 1;
      try {
        await ref.read(selfPortraitControllerProvider.notifier).act(action);
        if (wasLast && context.mounted) Navigator.of(context).pop();
      } catch (_) {
        error.value = l.selfPortraitActionFailed;
      } finally {
        busyId.value = null;
      }
    }

    final busy = busyId.value != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(title: l.selfPortraitConfirmSheetTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error.value != null) SpErrorText(error.value!),
                for (final item in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SpCard(
                      borderColor: AppColors.starGold.withValues(alpha: .55),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.selfPortraitSensitiveAsk(
                              _areaLabel(l, item.sensitive),
                            ),
                            style: const TextStyle(
                              color: AppColors.starGold,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.content,
                            style: const TextStyle(
                              color: spText,
                              fontSize: 15,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.selfPortraitPendingNotice,
                            style: TextStyle(
                              color: spMuted,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              SpPrimaryButton(
                                label: l.selfPortraitKeep,
                                onPressed: busy
                                    ? null
                                    : () => run(item.id, (r) => r.keep(item.id)),
                              ),
                              const SizedBox(width: 10),
                              SpSecondaryButton(
                                label: l.selfPortraitDontKeep,
                                onPressed: busy
                                    ? null
                                    : () => run(
                                        item.id,
                                        (r) => r.discard(item.id),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final p in proposals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.selfPortraitProposalTitle(
                              coverFieldLabel(l, p.field),
                            ),
                            style: TextStyle(
                              color: spMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((data?.cover[p.field]?.text ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${l.selfPortraitProposalNow}${data!.cover[p.field]!.text}',
                              style: TextStyle(
                                color: spMuted,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            p.proposedText,
                            style: const TextStyle(
                              color: spText,
                              fontSize: 15,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              SpPrimaryButton(
                                label: l.selfPortraitProposalAccept,
                                onPressed: busy
                                    ? null
                                    : () => run(
                                        p.id,
                                        (r) => r.decideProposal(
                                          p.id,
                                          accept: true,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              SpSecondaryButton(
                                label: l.selfPortraitProposalReject,
                                onPressed: busy
                                    ? null
                                    : () => run(
                                        p.id,
                                        (r) => r.decideProposal(
                                          p.id,
                                          accept: false,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (pending.isEmpty && proposals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l.selfPortraitConfirmEmpty,
                      style: TextStyle(color: spMuted, fontSize: 13.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
