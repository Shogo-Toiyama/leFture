import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// クレジット消費早見表（録音時間ごとの消費量）を表示するポップアップモーダル。
Future<void> showCreditRateTableDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const CreditRateTableDialog(),
  );
}

class CreditRateTableDialog extends StatelessWidget {
  const CreditRateTableDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final rates = [
      (duration: l10n.creditRateRow1Duration, credits: 60),
      (duration: l10n.creditRateRow2Duration, credits: 80),
      (duration: l10n.creditRateRow3Duration, credits: 100),
      (duration: l10n.creditRateRow4Duration, credits: 120),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF161829),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.universe.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー: アイコン・タイトル・閉じるボタン
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.starGold.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stars_rounded,
                        color: AppColors.starGold,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.creditRateModalTitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 17.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.universe.textComet,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 説明文
                Text(
                  l10n.creditRateModalDescription,
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),

                // 早見表テーブル
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1020),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.universe.glassBorder.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    children: [
                      // テーブルヘッダー
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.creditRateTableDurationHeader,
                                style: TextStyle(
                                  color: AppColors.universe.textComet,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              l10n.creditRateTableCreditsHeader,
                              style: TextStyle(
                                color: AppColors.universe.textComet,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.universe.glassBorder.withValues(alpha: 0.4),
                      ),

                      // 各行
                      ...rates.asMap().entries.map((entry) {
                        final i = entry.key;
                        final row = entry.value;
                        final isLast = i == rates.length - 1;

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(
                                children: [
                                  // 左側: 録音時間（Expandedでオーバーフロー防止）
                                  Expanded(
                                    child: Text(
                                      row.duration,
                                      style: TextStyle(
                                        color: AppColors.universe.textStarlight,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 右側: クレジットアイコン + 数値
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.stars_rounded,
                                        color: AppColors.starGold,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${row.credits}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.universe.glassBorder.withValues(alpha: 0.25),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 注意事項（3.5時間制限）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.starGold.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.starGold,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.creditRateMaxDurationNotice,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight.withValues(alpha: 0.9),
                            fontSize: 11.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
