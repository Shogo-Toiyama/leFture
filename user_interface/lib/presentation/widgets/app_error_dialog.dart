// presentation/widgets/app_error_dialog.dart
//
// アプリ共通のエラー表示。**呼び出し側のAPIは一切変えていない** —— 28箇所の
// 呼び出しをそのまま残したまま、中身だけを差し替えてある。
//
// 何を変えたか:
//   1. 「Technical Details」に生の例外文字列を常時出していたのをやめた。
//      配信ビルドでは[showTechnicalErrorDetails]がfalseに畳まれるので、
//      技術詳細を描くコードごとバイナリから消える。
//   2. 既知エラーの文言をハードコードの英語からl10nに移した。以前は
//      日本語UIでも "Incorrect email address or password." と英語が出ていた。
//      判定ロジック自体は[AppError]の分類器に移してある。
//   3. 未知のエラーは[SnagCard]/[SnagPanel]で「こちらの不具合です・開発者に
//      通知済み・参照コード」を見せ、同時に開発者へ自動報告する。
import 'package:flutter/material.dart';

import 'package:lefture/application/errors/error_reporter.dart';
import 'package:lefture/domain/errors/app_error.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/snag_panel.dart';

class AppErrorUtils {
  AppErrorUtils._();

  /// 分かりきっている典型的なエラーを、ローカライズ済みの親切な文言にする。
  /// 対象外(予期せぬエラー)の場合は null を返す。
  ///
  /// [context]が必要になったのは文言をl10nに移したため。旧シグネチャ
  /// (contextなし)は英語決め打ちしか返せず、日本語UIが壊れていた。
  static String? getFriendlyErrorMessage(BuildContext context, dynamic error) {
    if (error == null) return null;
    // 自前のバリデーションメッセージ(l10nの文字列)はStringとしてそのまま
    // 渡ってくる。例外オブジェクトと違ってすでに人に見せてよい文言なので、
    // そのまま1行表示する。
    if (error is String) return error;

    final l10n = AppLocalizations.of(context);
    return friendlyMessageForCode(
      l10n,
      AppError.from(error, origin: 'app_error_dialog').code,
    );
  }

  /// 例外を[AppError]の封筒に入れる。表示側はこれ経由でcodeを見る。
  static AppError envelope(dynamic error, {required String origin}) {
    if (error is AppError) return error;
    if (error is String) {
      // 既に人に見せてよい文言。封筒には入れるが報告はしない
      // (ユーザー向けバリデーションメッセージなので)。
      return AppError(
        code: AppErrorCode.offline == error ? AppErrorCode.offline : 'VALIDATION',
        origin: origin,
        raw: error,
        at: DateTime.now(),
      );
    }
    return AppError.from(error ?? Exception('Unknown error'), origin: origin);
  }
}

/// 全画面ページで使用する永続ダイアログ (Modal Dialog)
class AppErrorDialog extends StatelessWidget {
  const AppErrorDialog({
    super.key,
    required this.actionName,
    required this.rawError,
  });

  /// アクションの概要（例: "signing in", "creating your account" 等）
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
  /// 分かりきっているエラーの場合は [onFriendlyError] (インラインエラー状態) に
  /// セット。未知のシステムエラーの場合、または [onFriendlyError] が未指定の
  /// 場合は Modal Dialog を表示。
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
    final friendlyMsg = AppErrorUtils.getFriendlyErrorMessage(context, rawError);
    if (friendlyMsg != null && onFriendlyError != null) {
      onFriendlyError(rawError);
      return Future.value();
    }
    return show(context, actionName: actionName, rawError: rawError);
  }

  @override
  Widget build(BuildContext context) {
    final error = AppErrorUtils.envelope(rawError, origin: 'app_error_dialog.$actionName');

    // 未知のエラーはこの時点で開発者へ報告する。ErrorReporterが同一
    // fingerprintの連投を潰すので、rebuildで何度呼ばれても増えない。
    if (error.shouldReport) {
      reportAppError(error, route: 'dialog:$actionName');
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF13131C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 3バリアントのうち一番重いSnagCard。ダイアログは操作が
              // ブロックされている状態なので、安心感に一番重さが要る。
              SnagCard(
                error: error,
                actionName: actionName,
                reportStatus: error.shouldReport
                    ? SnagReportStatus.reported
                    : SnagReportStatus.hidden,
                reportedAt: error.at,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    AppLocalizations.of(context).appErrorDialogClose,
                    style: TextStyle(color: AppColors.universe.textComet),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

    final friendlyMsg = AppErrorUtils.getFriendlyErrorMessage(context, rawError);

    // 分かりきっているエラーは、すっきりした1行のインライン赤枠で表示。
    // 赤を使うのはここだけ —— 「入力を直せば解決する」類のエラーだから。
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

    // 予期せぬエラーは「こちらの不具合です」パネル。生文字列は出さない。
    final error = AppErrorUtils.envelope(rawError, origin: 'app_error_box.$actionName');
    if (error.shouldReport) {
      reportAppError(error, route: 'box:$actionName');
    }

    return SnagPanel(error: error, actionName: actionName);
  }
}
