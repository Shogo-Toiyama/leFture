import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/widgets/auth_result_view.dart';

/// メールアドレス変更・ログイン方法変更・アカウント削除など、
/// deep link 経由/同一セッション内で非同期に完了するアクションの結果を表示する。
/// [kind] によって見た目と「戻る」ボタンの遷移先を切り替える。
class AuthResultPage extends StatelessWidget {
  const AuthResultPage({super.key, required this.kind, this.detail});

  final String kind;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 'email_changed':
        return AuthResultView(
          success: true,
          icon: Icons.mark_email_read_rounded,
          title: 'Email address changed',
          message: (detail != null && detail!.isNotEmpty)
              ? 'Your email address has been updated to $detail.'
              : 'Your email address has been updated successfully.',
          buttonLabel: 'Go to Dashboard',
          onButtonPressed: () => context.go(AppRoutes.home),
        );

      case 'email_change_pending':
        return AuthResultView(
          success: true,
          icon: Icons.mark_email_unread_rounded,
          title: 'One more step',
          message: (detail != null && detail!.isNotEmpty)
              ? detail!
              : 'Please confirm the link sent to your other email address to complete the change.',
          buttonLabel: 'Got it',
          onButtonPressed: () => context.go(AppRoutes.home),
        );

      case 'email_change_error':
        return AuthResultView(
          success: false,
          icon: Icons.error_outline_rounded,
          title: 'Could not change email',
          message: (detail != null && detail!.isNotEmpty)
              ? detail!
              : 'This link is invalid or has expired. Please try again.',
          buttonLabel: 'Back to Dashboard',
          onButtonPressed: () => context.go(AppRoutes.home),
        );

      case 'provider_linked':
        return AuthResultView(
          success: true,
          icon: Icons.link_rounded,
          title: 'Login method updated',
          message: (detail != null && detail!.isNotEmpty)
              ? 'You can now sign in with $detail.'
              : 'Your login method has been updated.',
          buttonLabel: 'Go to Dashboard',
          onButtonPressed: () => context.go(AppRoutes.home),
        );

      case 'provider_link_error':
        return AuthResultView(
          success: false,
          icon: Icons.link_off_rounded,
          title: 'Could not update login method',
          message: (detail != null && detail!.isNotEmpty)
              ? detail!
              : 'Something went wrong while linking this login method. Please try again.',
          buttonLabel: 'Back to Dashboard',
          onButtonPressed: () => context.go(AppRoutes.home),
        );

      case 'account_deleted':
        return AuthResultView(
          success: true,
          icon: Icons.check_circle_outline_rounded,
          title: 'Account deleted',
          message: 'Your account and all associated data have been permanently deleted. '
              'Thank you for using leFture.',
          buttonLabel: 'Back to Sign In',
          onButtonPressed: () => context.go(AppRoutes.signIn),
        );

      default:
        // 未知のkindでもクラッシュさせず、安全にホームへ戻れるようにする。
        return AuthResultView(
          success: true,
          icon: Icons.check_circle_outline_rounded,
          title: 'Done',
          message: 'This action has completed.',
          buttonLabel: 'Go to Dashboard',
          onButtonPressed: () => context.go(AppRoutes.home),
        );
    }
  }
}
