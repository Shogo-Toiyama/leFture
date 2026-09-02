// lib/presentation/widgets/orphan_delete_confirm.dart
//
// 孤児録音(キル/クラッシュ等で取り残され、一度もサーバーへアップロード
// されていない講義)を削除する前に見せる確認ダイアログ。
//
// 通常の講義削除は論理削除(30日間ゴミ箱で保持、いつでも復元できる)だが、
// 孤児講義はRecordingRecoveryService.discard()経由で物理削除される
// (サーバーに実体が無いので論理削除する意味が無く、巨大なローカル音声を
// 30日間抱え続ける方が損なため)。挙動が普段の削除と違う以上、
// LectureTileの長押し→削除のような「普段は確認なしで即ゴミ箱行き」の
// フローであっても、この場合だけは明示的に確認を挟む。
// RecoveredRecordingView(復旧カード)の削除ダイアログと文言・体裁を統一する。
import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// 確認できたら`true`、キャンセルされたら`false`を返す。
Future<bool> confirmOrphanHardDelete(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.recoveryDeleteConfirmTitle),
      content: Text(l10n.recoveryDeleteConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.recoveryCancelButton),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.correctionRed),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.recoveryDeleteConfirmButton),
        ),
      ],
    ),
  );
  return confirmed == true;
}
