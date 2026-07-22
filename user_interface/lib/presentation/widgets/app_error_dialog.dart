import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class AppErrorUtils {
  AppErrorUtils._();

  /// 分かりきっている典型的なエラーを人間味のある親切な英語メッセージにマッピングする。
  /// 対象外（予期せぬエラー）の場合は null を返す。
  static String? getFriendlyErrorMessage(dynamic error) {
    if (error == null) return null;
    final str = error.toString().toLowerCase();

    if (str.contains('invalid login credentials') ||
        str.contains('invalid_credentials') ||
        str.contains('invalid email or password')) {
      return 'Incorrect email address or password.';
    }
    if (str.contains('email not confirmed') || str.contains('email_not_confirmed')) {
      return 'Please verify your email address before signing in.';
    }
    if (str.contains('user already registered') ||
        str.contains('user_already_exists') ||
        str.contains('already exists')) {
      return 'An account with this email address already exists.';
    }
    if (str.contains('password should be at least') || str.contains('weak_password')) {
      return 'Password must be at least 6 characters long.';
    }
    if (str.contains('missing email') ||
        str.contains('email or phone') ||
        str.contains('email is required') ||
        str.contains('email required')) {
      return 'Please enter your email address.';
    }
    if (str.contains('missing password') ||
        str.contains('password is required') ||
        str.contains('password required') ||
        str.contains('signup requires a valid password')) {
      return 'Please enter a password.';
    }
    if (str.contains('unable to validate email address') || str.contains('invalid_email')) {
      return 'Please enter a valid email address.';
    }
    if (str.contains('email rate limit exceeded') || str.contains('over_email_send_rate_limit')) {
      return 'Too many requests. Please wait a few minutes before trying again.';
    }
    if (str.contains('new password should be different')) {
      return 'New password must be different from your old password.';
    }
    if (str.contains('new email must be different')) {
      return 'New email must be different from your current email.';
    }
    if (str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('networkexception')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (str.contains('timeoutexception') || str.contains('taking longer than usual')) {
      return 'Server is taking longer than usual to respond. Please try again in a moment.';
    }

    return null;
  }

  /// エラーオブジェクトから不要な接頭辞（Exception: 等）を取り除き、読みやすくする
  static String formatRawError(dynamic error) {
    if (error == null) return '';
    String str = error.toString().trim();
    
    // AuthException(message: ..., statusCode: ...) パターンの抽出
    final authMatch = RegExp(r'AuthException\(message:\s*([^,]+)').firstMatch(str);
    if (authMatch != null && authMatch.group(1) != null) {
      return authMatch.group(1)!.trim();
    }

    // 不要な接頭辞を削除
    str = str
        .replaceAll(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'^AuthApiException:\s*'), '')
        .replaceAll(RegExp(r'^AuthException:\s*'), '')
        .trim();

    return str.isEmpty ? 'Unknown error' : str;
  }
}

/// 全画面ページで使用する永続ダイアログ (Modal Dialog)
class AppErrorDialog extends StatelessWidget {
  const AppErrorDialog({
    super.key,
    required this.actionName,
    required this.rawError,
  });

  /// アクションの概要（例: "signing in", "creating your account", "updating your password" 等）
  final String actionName;
  final dynamic rawError;

  static Future<void> show(
    BuildContext context, {
    String actionName = 'processing your request',
    required dynamic rawError,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AppErrorDialog(
        actionName: actionName,
        rawError: rawError,
      ),
    );
  }

  /// スマートエラーハンドラ:
  /// 分かりきっているエラーの場合は [onFriendlyError] (インラインエラー状態) にセット。
  /// 未知のシステムエラーの場合、または [onFriendlyError] が未指定の場合は Modal Dialog を表示。
  static Future<void> showSmart(
    BuildContext context,
    dynamic rawError, {
    String actionName = 'processing your request',
    void Function(dynamic error)? onFriendlyError,
  }) {
    return _showSmartImpl(
      context,
      rawError: rawError,
      actionName: actionName,
      onFriendlyError: onFriendlyError,
    );
  }

  /// 名前付き引数 (actionName, rawError) での呼び出しに対応した互換用ヘルパー
  static Future<void> showSmartNamed(
    BuildContext context, {
    required dynamic rawError,
    String actionName = 'processing your request',
    void Function(dynamic error)? onFriendlyError,
  }) {
    return _showSmartImpl(
      context,
      rawError: rawError,
      actionName: actionName,
      onFriendlyError: onFriendlyError,
    );
  }

  static Future<void> _showSmartImpl(
    BuildContext context, {
    required dynamic rawError,
    String actionName = 'processing your request',
    void Function(dynamic error)? onFriendlyError,
  }) {
    final targetError = rawError;
    final friendlyMsg = AppErrorUtils.getFriendlyErrorMessage(targetError);
    if (friendlyMsg != null && onFriendlyError != null) {
      onFriendlyError(targetError);
      return Future.value();
    }
    return show(context, actionName: actionName, rawError: targetError);
  }

  @override
  Widget build(BuildContext context) {
    final formattedError = AppErrorUtils.formatRawError(rawError);

    return AlertDialog(
      backgroundColor: const Color(0xFF13131C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.universe.glassBorder),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.correctionRed, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'An error occurred while $actionName.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User guidance message
            Text(
              'Please wait a moment and try again. If the issue persists, please take a screenshot of this screen and contact us via Contact Us.',
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // Raw error technical details block
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.universe.voidBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.universe.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Technical Details:',
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    formattedError,
                    style: const TextStyle(
                      color: AppColors.correctionRed,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.push(AppRoutes.contact);
          },
          child: const Text(
            'Contact Support',
            style: TextStyle(
              color: AppColors.starGold,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.universe.glassWhiteLow,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: AppColors.universe.glassBorder),
            ),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// ボトムシートやフォーム内にインライン表示する永続エラーボックス
class AppErrorBox extends StatelessWidget {
  const AppErrorBox({
    super.key,
    required this.actionName,
    required this.rawError,
  });

  final String actionName;
  final dynamic rawError;

  @override
  Widget build(BuildContext context) {
    if (rawError == null || rawError.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final friendlyMsg = AppErrorUtils.getFriendlyErrorMessage(rawError);

    // 分かりきっているエラー（友好なメッセージ）は、すっきりした1行のインライン赤枠で表示
    if (friendlyMsg != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.correctionRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.correctionRed, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                friendlyMsg,
                style: const TextStyle(
                  color: AppColors.correctionRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 予期せぬエラーは、タイトル・案内・技術詳細付きのボックスで表示
    final formattedError = AppErrorUtils.formatRawError(rawError);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.correctionRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.correctionRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'An error occurred while $actionName.',
                  style: const TextStyle(
                    color: AppColors.correctionRed,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait a moment and try again. If the issue persists, please take a screenshot and contact support.',
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.universe.voidBackground.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.universe.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Technical Details:',
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  formattedError,
                  style: const TextStyle(
                    color: AppColors.correctionRed,
                    fontSize: 10,
                    fontFamily: 'monospace',
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
