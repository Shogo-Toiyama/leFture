// presentation/widgets/snag_panel.dart
//
// 「予期せぬエラー」をユーザーに伝えるための表示。生の例外文字列は
// 配信ビルドでは一切出さず、代わりに
//   ・こちら側の問題であること(ユーザーのせいではないこと)
//   ・開発者に自動通知済みであること
//   ・急ぎならお問い合わせできること + 参照コード
// を伝える。
//
// 3つのバリアントは見た目違いではなく、アプリに実在する3つのスロットに
// 対応している:
//   [SnagPanel] … AppErrorBox が入っていたインライン枠(シート・フォーム)
//   [SnagCard]  … AppErrorDialog のモーダル / NotStartedView のバナー
//   [SnagLine]  … SnackBar と、余白のない狭いインライン枠
//
// 色について: 既存のエラー表示は correctionRed だったが、赤は「あなたが
// 何か間違えた」と読めてしまう。ここでは starGold を使う — 「システムが
// 対応中」と読め、アプリのアクセント色とも揃う。ユーザー起因のバリデー
// ションエラー(赤)と、こちら側の不具合(金)を色で区別する意図もある。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/errors/error_reporter.dart';
import 'package:lefture/core/config/error_visibility.dart';
import 'package:lefture/domain/errors/app_error.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// エラー報告が実際に開発者へ届いたか。[SnagCard]だけがこれを表示する。
///
/// オフライン中は報告がローカルキューに積まれるだけなので、そこで
/// 「通知済み」と言い切ると嘘になる。[queued]はそのための状態。
enum SnagReportStatus {
  /// 報告済み(サーバーが受理した)。
  reported,

  /// ローカルキューに入っている(オフライン等)。
  queued,

  /// 表示しない。
  hidden,
}

/// [AppError.code]に対応する、ローカライズ済みの固定文言を返す。
/// 対応する文言を持たないコード(=予期せぬエラー)では null を返す。
///
/// 旧 `AppErrorUtils.getFriendlyErrorMessage()` の置き換え。あちらは英語の
/// 文字列を直接返していたため、日本語UIでも英語が出ていた。
String? friendlyMessageForCode(AppLocalizations l10n, String code) {
  switch (code) {
    case AppErrorCode.offline:
      return l10n.errOffline;
    case AppErrorCode.timeout:
      return l10n.errTimeout;
    case AppErrorCode.sessionExpired:
      return l10n.errSessionExpired;
    case AppErrorCode.invalidCredentials:
      return l10n.errInvalidCredentials;
    case AppErrorCode.emailNotConfirmed:
      return l10n.errEmailNotConfirmed;
    case AppErrorCode.emailAlreadyRegistered:
      return l10n.errEmailAlreadyRegistered;
    case AppErrorCode.weakPassword:
      return l10n.errWeakPassword;
    case AppErrorCode.invalidEmail:
      return l10n.errInvalidEmail;
    case AppErrorCode.missingEmail:
      return l10n.errMissingEmail;
    case AppErrorCode.missingPassword:
      return l10n.errMissingPassword;
    case AppErrorCode.rateLimited:
      return l10n.errRateLimited;
    case AppErrorCode.samePassword:
      return l10n.errSamePassword;
    case AppErrorCode.sameEmail:
      return l10n.errSameEmail;
    case AppErrorCode.accountSuspended:
      return l10n.errAccountSuspended;
    default:
      // INSUFFICIENT_CREDITS / NO_CREDIT_ALLOCATION は専用ダイアログで
      // クレジットページへ誘導する経路があるので、ここでは扱わない。
      return null;
  }
}

// =====================================================================
// 共有パーツ
// =====================================================================

/// 参照コードのチップ。タップでクリップボードにコピーできる
/// (ユーザーがお問い合わせフォームに貼りやすいように)。
class _RefCodeChip extends StatelessWidget {
  const _RefCodeChip(this.refCode);

  final String refCode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: refCode));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(refCode),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Text(
          refCode,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontSize: 11,
            fontFamily: 'monospace',
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// お問い合わせフォームへ飛ぶリンク。
class _ContactLink extends StatelessWidget {
  const _ContactLink({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.contact),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.starGold,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 開発者だけが見る技術詳細。[showTechnicalErrorDetails]がfalseのビルドでは
/// この関数ごとtree-shakingで消えるため、配信版には文字列も残らない。
class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails(this.error);

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final payload = 'code:   ${error.code}\n'
        'origin: ${error.origin}\n'
        'fp:     ${error.fingerprint}\n'
        'ref:    ${error.refCode}\n'
        '${error.httpStatus != null ? 'http:   ${error.httpStatus}\n' : ''}'
        'raw:    ${error.raw}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.snagTechnicalDetails(error.code),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: payload)),
                child: Text(
                  l10n.snagCopyReport,
                  style: const TextStyle(
                    color: AppColors.starGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            payload,
            style: const TextStyle(
              color: AppColors.correctionRed,
              fontSize: 10,
              height: 1.45,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// 本文。[actionName]があれば「〜の途中で」と具体的に言う。
String _bodyText(AppLocalizations l10n, String? actionName) =>
    actionName == null || actionName.isEmpty
        ? l10n.snagBodyNoAction
        : l10n.snagBody(actionName);

// =====================================================================
// バリアントA — インラインの安心パネル
// =====================================================================

/// シートやフォーム内に置く、予期せぬエラーのインライン表示。
/// `AppErrorBox` の予期せぬエラー経路を置き換える。
class SnagPanel extends StatelessWidget {
  const SnagPanel({
    super.key,
    required this.error,
    this.actionName,
    this.onRetry,
  });

  final AppError error;

  /// 「解析の開始」のような、失敗した操作の説明。`AppErrorDialog`が
  /// 既に受け取っている `actionName` をそのまま流用する。
  final String? actionName;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.starGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.starGold.withValues(alpha: 0.32)),
        // 左端の金のラインが「これはこちら側の不具合」の目印
        gradient: LinearGradient(
          colors: [
            AppColors.starGold.withValues(alpha: 0.16),
            AppColors.starGold.withValues(alpha: 0.06),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.starGold, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.snagTitle,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _bodyText(l10n, actionName),
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
          if (showTechnicalErrorDetails) ...[
            _TechnicalDetails(error),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _ContactLink(label: l10n.snagContactButton),
              const Spacer(),
              if (onRetry != null) ...[
                GestureDetector(
                  onTap: onRetry,
                  child: Text(
                    l10n.snagRetryButton,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              _RefCodeChip(error.refCode),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// バリアントB — ステータスカード
// =====================================================================

/// 操作がブロックされたときに使う、もっとも重いバリアント。
/// 「開発者に通知しました」を文章ではなく**観測可能な状態**として見せる
/// (緑のチェック + 時刻)のがこのバリアントの主眼。
class SnagCard extends StatelessWidget {
  const SnagCard({
    super.key,
    required this.error,
    this.actionName,
    this.reportStatus = SnagReportStatus.hidden,
    this.reportedAt,
    this.nothingLost = false,
    this.onRetry,
  });

  final AppError error;
  final String? actionName;
  final SnagReportStatus reportStatus;
  final DateTime? reportedAt;

  /// 失敗しても手元のデータが消えていない場合だけ true にする
  /// (録音がまだ端末にある等)。嘘になる場面では出さない。
  final bool nothingLost;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- ヘッダ ---
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.starGold, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.snagTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- 本文 ---
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bodyText(l10n, actionName),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
                if (nothingLost) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.snagNothingLost,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (showTechnicalErrorDetails) ...[
                  const SizedBox(height: 10),
                  _TechnicalDetails(error),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.starGold,
                        foregroundColor: const Color(0xFF2A1C00),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: Text(
                        l10n.snagRetryButton,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // --- フッタ帯: 報告状態 + 参照コード ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.13)),
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(13),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: _reportStatusLine(l10n)),
                const SizedBox(width: 8),
                _RefCodeChip(error.refCode),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportStatusLine(AppLocalizations l10n) {
    switch (reportStatus) {
      case SnagReportStatus.reported:
        final t = TimeOfDay.fromDateTime(reportedAt ?? DateTime.now());
        final label = '${t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod}:'
            '${t.minute.toString().padLeft(2, '0')} '
            '${t.period == DayPeriod.am ? 'AM' : 'PM'}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded,
                color: AppColors.growthGreen, size: 13),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                l10n.snagReported(label),
                style: const TextStyle(
                  color: AppColors.growthGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case SnagReportStatus.queued:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded,
                color: AppColors.universe.textComet, size: 13),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                l10n.snagReportQueued,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case SnagReportStatus.hidden:
        return _ContactLink(label: l10n.snagContactButton);
    }
  }
}

// =====================================================================
// バリアントC — 静かな一行
// =====================================================================

/// 非ブロッキングな失敗のための最小表示。狭いインライン枠に置く。
class SnagLine extends StatelessWidget {
  const SnagLine({super.key, required this.error, this.actionName});

  final AppError error;
  final String? actionName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        l10n.snagShort(actionName ?? ''),
        style: TextStyle(
          color: AppColors.universe.textComet,
          fontSize: 11.5,
          height: 1.45,
        ),
      ),
    );
  }
}

/// SnackBarとして出す形。生エラーを`SnackBar(content: Text(e.toString()))`
/// で出していた箇所は、すべてこれに置き換える。
void showSnagSnackBar(
  BuildContext context,
  AppError error, {
  String? actionName,
}) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF1D2130),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.snagShort(actionName ?? ''),
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          if (showTechnicalErrorDetails) ...[
            const SizedBox(height: 4),
            Text(
              '${error.code} @ ${error.origin}',
              style: const TextStyle(
                color: AppColors.correctionRed,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
      action: SnackBarAction(
        label: error.refCode,
        textColor: AppColors.starGold,
        onPressed: () => Clipboard.setData(ClipboardData(text: error.refCode)),
      ),
    ),
  );
}

// =====================================================================
// 掃き出し用のヘルパー
// =====================================================================

/// `AsyncValue.when(error: ...)` の穴に置く表示。
///
/// 層2の `l10n.xxxError(err.toString())` 系(26箇所)を置き換えるためのもの。
/// 既知のエラーなら中央寄せの1行、未知なら[SnagPanel]を出し、同時に報告する。
class SnagAsyncError extends StatelessWidget {
  const SnagAsyncError({
    super.key,
    required this.error,
    required this.origin,
    this.actionName,
    this.onRetry,
    this.compact = false,
  });

  final Object? error;

  /// 発生地点タグ。fingerprintの構成要素なので、画面ごとに固有の値にする。
  final String origin;

  final String? actionName;
  final VoidCallback? onRetry;

  /// 狭い場所(モーダル内のリスト等)では[SnagLine]相当の軽い表示にする。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appError = AppError.from(error ?? Exception('Unknown error'), origin: origin);
    final friendly = friendlyMessageForCode(l10n, appError.code);

    if (friendly != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          friendly,
          style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    reportAppError(appError, route: origin);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: compact
          ? SnagLine(error: appError, actionName: actionName)
          : SnagPanel(error: appError, actionName: actionName, onRetry: onRetry),
    );
  }
}

/// 例外から「ユーザーに見せてよい1行」を作る。未知のエラーなら同時に報告する。
///
/// 層3の `errorMsg.value = e.toString()` 系を置き換えるためのもの。
/// あれらは`String?`のstateにそのまま入れて`Text`に流していたので、
/// 受け皿の型を変えずに中身だけ安全にできるこの形が一番影響が小さい。
///
/// 返り値に参照コードを含めるのは、ユーザーがそのまま問い合わせに
/// 貼れるようにするため。
///
/// [BuildContext]ではなく[AppLocalizations]を受け取るのは、呼び出し元が
/// await後のcatchブロックだから —— その時点でcontextが外れている可能性が
/// あり、`use_build_context_synchronously`に触れる。呼び出し側はbuildの
/// 先頭で取った`l10n`を渡す。
String snagMessageFor(
  AppLocalizations l10n,
  Object error, {
  required String origin,
  String? actionName,
}) {
  final appError = AppError.from(error, origin: origin);
  final friendly = friendlyMessageForCode(l10n, appError.code);
  if (friendly != null) return friendly;

  reportAppError(appError, route: origin);

  final body = actionName == null || actionName.isEmpty
      ? l10n.snagBodyNoAction
      : l10n.snagBody(actionName);
  return '${l10n.snagTitle}\n$body\n${appError.refCode}';
}

/// 既存の `l10n.xxxError({error})` の穴に差す、ユーザーに見せてよい短い文字列。
///
/// 既知のエラーならその文言、未知なら「こちらの不具合です + 参照コード」を
/// 返し、同時に開発者へ報告する。文言の枠(「エラー: 〜」等)は既存のl10nキーを
/// そのまま使いたいので、穴に入る値だけを安全にするためのもの。
///
/// [snagMessageFor]と同じ理由で[AppLocalizations]を受け取る —— 呼び出し元に
/// 非同期コールバック内のものがあり、そこでcontextを触ると
/// `use_build_context_synchronously`に触れる。
String safeErrorText(AppLocalizations l10n, Object error, String origin) {
  final appError = AppError.from(error, origin: origin);
  final friendly = friendlyMessageForCode(l10n, appError.code);
  if (friendly != null) return friendly;

  reportAppError(appError, route: origin);
  return '${l10n.snagTitle} ${appError.refCode}';
}
