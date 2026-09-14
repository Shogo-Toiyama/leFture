import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/plan_lock_illustration.dart';

/// 特定の機能がまだ現在のプランで使えない時に出す、Plansページへの誘導ダイアログ。
/// クレジット残高不足時の汎用ダイアログ(low-credits用、not_started_view.dart内)とは
/// 別物 — こちらは「プランそのものが足りない」ケース専用で、解放に必要なプランの色の
/// 鍵アイコン([PlanLockIllustration])を添えて視覚的にどのプランが要るか伝える。
Future<void> showUpgradeRequiredDialog({
  required BuildContext context,
  required Color requiredTierColor,
  required String title,
  required String message,
  required String viewPlansLabel,
  required String cancelLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161829),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.universe.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlanLockIllustration(color: requiredTierColor, size: 88),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.universe.textComet,
                        side: BorderSide(color: AppColors.universe.glassBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        cancelLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        // ダイアログを閉じた後の画面遷移は、popで破棄されるdialogContext
                        // ではなく呼び出し元のcontextを使う(not_started_view.dartの
                        // 既存パターンと同じ)。
                        context.push(AppRoutes.plans);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: requiredTierColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        viewPlansLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
