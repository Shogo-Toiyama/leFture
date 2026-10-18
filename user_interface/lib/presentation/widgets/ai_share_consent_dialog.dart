// lib/presentation/widgets/ai_share_consent_dialog.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// AIサービスへのデータ送信への同意ダイアログ(録音とチャットで同じ形)。
/// 短い説明と「詳しく見る」(送るデータと送り先の一覧)、プライバシーポリシーとお問い合わせへのリンク、
/// 「キャンセル」と「同意して続ける」。同意されたらtrueを返す。
///
/// 録音の同意とチャットの同意は送り先も目的も違うので、文言を変えて別々に出す。
/// [notice]は、前の版に同意した人にもう一度聞くときの理由(先頭に目立たせて出す)。
Future<bool> showAiShareConsentDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String detailsBody,
  String? notice,
}) async {
  final l10n = AppLocalizations.of(context);
  var expanded = false;
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: const Color(0xFF13131C),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.starGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                color: AppColors.starGold,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notice != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    notice,
                    style: const TextStyle(
                      color: AppColors.starGold,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                message,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  initiallyExpanded: expanded,
                  onExpansionChanged: (value) =>
                      setState(() => expanded = value),
                  iconColor: AppColors.starGold,
                  collapsedIconColor: AppColors.starGold,
                  title: Text(
                    l10n.aiSharingConsentDialogDetailsToggle,
                    style: const TextStyle(
                      color: AppColors.starGold,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  children: [
                    Text(
                      detailsBody,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  InkWell(
                    onTap: () => ctx.push(AppRoutes.privacyPolicy),
                    child: Text(
                      l10n.aiSharingConsentDialogPrivacyPolicyLink,
                      style: const TextStyle(
                        color: AppColors.starGold,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => ctx.push(AppRoutes.contact),
                    child: Text(
                      l10n.aiSharingConsentDialogContactLink,
                      style: const TextStyle(
                        color: AppColors.starGold,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.aiSharingConsentDialogCancelButton,
              style: TextStyle(color: AppColors.universe.textComet),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.starGold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(
              l10n.aiSharingConsentDialogAgreeButton,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
  return agreed == true;
}
