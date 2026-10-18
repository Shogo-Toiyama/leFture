// lib/presentation/pages/profile/self_portrait/cover_edit_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/sp_common.dart';

const _coverMaxChars = 500;

/// 表紙(いまのわたし)の1つの欄を書き直す。これまでどおり本人が直接書く
/// (サーバー側のトリガが書き手を「本人」にする)ので、AIはその文を勝手に変えない。
Future<void> showCoverEditSheet(
  BuildContext context, {
  required CoverField field,
  required String? initialText,
}) => showSpSheet<void>(
  context,
  (_) => _CoverEditSheet(field: field, initialText: initialText ?? ''),
);

class _CoverEditSheet extends HookConsumerWidget {
  const _CoverEditSheet({required this.field, required this.initialText});

  final CoverField field;
  final String initialText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = useTextEditingController(text: initialText);
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> save() async {
      busy.value = true;
      error.value = null;
      try {
        final text = controller.text.trim();
        await ref
            .read(userProfileRepositoryProvider)
            .updateProfile(
              bio: field == CoverField.bio ? text : null,
              interests: field == CoverField.interests ? text : null,
              futureGoals: field == CoverField.futureGoals ? text : null,
            );
        // 端末の変更をサーバーへ送ってから、自分像を読み直す
        await ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        await ref.read(selfPortraitControllerProvider.notifier).refresh();
        if (context.mounted) Navigator.of(context).pop();
      } catch (_) {
        error.value = l.selfPortraitActionFailed;
        busy.value = false;
      }
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(title: coverFieldLabel(l, field)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpTextField(
                  controller: controller,
                  maxLines: 6,
                  maxLength: _coverMaxChars,
                ),
                if (error.value != null) SpErrorText(error.value!),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => SpPrimaryButton(
                        label: busy.value
                            ? l.selfPortraitSaving
                            : l.selfPortraitSave,
                        onPressed: busy.value || value.text.trim() == initialText
                            ? null
                            : save,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SpSecondaryButton(
                      label: MaterialLocalizations.of(context).cancelButtonLabel,
                      onPressed: busy.value
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
