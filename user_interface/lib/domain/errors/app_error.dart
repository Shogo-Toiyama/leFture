// domain/errors/app_error.dart
//
// アプリ内で起きた失敗を、UI・ローカルDB・エラー報告の3者が同じ形で
// 扱えるようにするための封筒(エンベロープ)。
//
// 経緯: これまでは失敗を `e.toString()` の生文字列のまま持ち回っていた。
// そのため
//   1. 画面に生の例外文字列がそのまま出る(ユーザーには意味不明かつ不安)
//   2. ローカルDB(LocalUploadJobs.lastError等)を経由すると型情報が消え、
//      not_started_view が `InsufficientCreditsException(CODE): msg` という
//      toString()の書式を正規表現でパースし直す羽目になっていた
//   3. 「同じ失敗が何回起きたか」を機械的に数えられない
// という3つの問題が同時に起きていた。
//
// [AppError]は「機械が読む[code]」「人に見せる文言を引くための鍵」「開発者
// だけが見る[raw]」を分離して持つ。DBにはJSONで保存するので、経路を跨いでも
// 型情報が失われない。
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:lefture/domain/exceptions/account_suspended_exception.dart';
import 'package:lefture/domain/exceptions/insufficient_credits_exception.dart';

/// [AppError.code]に入る値。バックエンドが返す `error_code` と意図的に
/// 同じ文字列を使う(バックエンド由来のコードはそのまま透過させたいため)。
///
/// ここに無いコードが来ても壊れない — 未知のコードは[AppErrorCode.unknown]
/// として扱われ、ユーザーには汎用の「こちらの不具合です」文言が出る。
class AppErrorCode {
  AppErrorCode._();

  // --- バックエンドが構造化して返すもの(detail.error_code と一致させる) ---
  static const insufficientCredits = 'INSUFFICIENT_CREDITS';
  static const noCreditAllocation = 'NO_CREDIT_ALLOCATION';
  static const accountSuspended = 'ACCOUNT_SUSPENDED';

  // --- クライアント側で判定するもの ---
  static const offline = 'OFFLINE';
  static const timeout = 'TIMEOUT';
  static const sessionExpired = 'SESSION_EXPIRED';

  // 認証まわり(Supabase Authのメッセージから判定する)
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const emailNotConfirmed = 'EMAIL_NOT_CONFIRMED';
  static const emailAlreadyRegistered = 'EMAIL_ALREADY_REGISTERED';
  static const weakPassword = 'WEAK_PASSWORD';
  static const invalidEmail = 'INVALID_EMAIL';
  static const missingEmail = 'MISSING_EMAIL';
  static const missingPassword = 'MISSING_PASSWORD';
  static const rateLimited = 'RATE_LIMITED';
  static const samePassword = 'SAME_PASSWORD';
  static const sameEmail = 'SAME_EMAIL';

  /// バックエンドが4xx/5xxを返したが、error_codeが未知 or 構造化されていない。
  static const backendRejected = 'BACKEND_REJECTED';

  /// 失敗ではなく、Realtime Transcribe録音のアップロード全工程のログを
  /// 成功・失敗を問わず送るための診断レポート(UploadTrace)。
  static const uploadTrace = 'UPLOAD_TRACE';

  /// どれにも当てはまらない。**報告対象の本命はこれ。**
  static const unknown = 'UNKNOWN';

  /// 「待てば直る / ユーザー起因 / 既に自動回復している」ため、開発者へ
  /// 報告しても意味がないコード。これ以外を報告する。
  ///
  /// 方針: 例外を捕まえるたびに報告するのではなく、**ユーザーに失敗が
  /// 見えたときだけ**報告する。これだけで報告量の大半が落ちる。
  static const notWorthReporting = <String>{
    offline,
    timeout,
    sessionExpired,
    insufficientCredits,
    noCreditAllocation,
    accountSuspended,
    invalidCredentials,
    emailNotConfirmed,
    emailAlreadyRegistered,
    weakPassword,
    invalidEmail,
    missingEmail,
    missingPassword,
    rateLimited,
    samePassword,
    sameEmail,
  };
}

/// 失敗1件を表す不変の封筒。
class AppError implements Exception {
  const AppError({
    required this.code,
    required this.origin,
    required this.raw,
    required this.at,
    this.httpStatus,
    this.backendCode,
    this.stack,
  });

  /// 機械が読む分類。[AppErrorCode]のいずれか。
  final String code;

  /// 発生地点のタグ。`'upload_manager.uploadChunk'` のように
  /// 「ファイル.操作」で書く。fingerprintの構成要素なので、**同じ失敗が
  /// 同じoriginを名乗ること**が重要(コピペで別名を付けると別グループになる)。
  final String origin;

  /// 元の例外のtoString()。リリースビルドのユーザーには決して見せない。
  final String raw;

  /// 発生時刻(端末のローカル時計)。
  final DateTime at;

  /// バックエンド由来ならHTTPステータス。
  final int? httpStatus;

  /// バックエンドが返した生の `error_code`。[code]に昇格できなかった場合も
  /// 診断のために保持する。
  final String? backendCode;

  /// スタックトレース(あれば)。報告時のサンプルにのみ載せる。
  final String? stack;

  /// ユーザーに固定文言を出すだけで済む(=生文字列を見せる必要がない)か。
  /// [AppErrorCode.unknown]と[AppErrorCode.backendRejected]以外は、
  /// 専用の文言を持っている前提。
  bool get hasFriendlyMessage =>
      code != AppErrorCode.unknown && code != AppErrorCode.backendRejected;

  /// 開発者へ報告すべきか。
  bool get shouldReport => !AppErrorCode.notWorthReporting.contains(code);

  // ---------------------------------------------------------------
  // 指紋(fingerprint)
  // ---------------------------------------------------------------

  /// 同じ原因の失敗をまとめるための指紋。
  ///
  /// `code | origin | httpStatus | normalize(raw)` のSHA-256先頭16桁。
  /// [_normalize]がUUID・連番・パス・バイト数などの「毎回変わる部分」を
  /// 落とすので、**1文字違うだけでは別グループにならない**。
  ///
  ///   `Failed to upload chunk 17 of job 3f2a-9b1c… (4823 bytes)`
  ///     → `Failed to upload chunk <n> of job <uuid> (<n> bytes)`
  ///
  /// [httpStatus]を基礎に明示的に混ぜているのは、[_normalize]が数値を
  /// すべて潰すため。混ぜないと「HTTP 404」と「HTTP 502」が同じグループに
  /// なってしまう —— そこは分けたい。逆にチャンク番号のような添字は
  /// 潰したい(添字ごとにグループが増えると1つのバグが何百件にも散る)。
  String get fingerprint {
    final basis = '$code|$origin|${httpStatus ?? ''}|${_normalize(raw)}';
    return sha256.convert(utf8.encode(basis)).toString().substring(0, 16);
  }

  /// ユーザーに見せる参照コード(`ERR-7K2M9Q`)。
  ///
  /// 指紋＋発生時刻の分バケットから導出するので、
  ///   - オフラインでも未ログインでも端末だけで生成できる
  ///   - 同じ失敗が1分以内に連続しても同じコードになる(嵐で番号が散らない)
  /// Crockford Base32から紛らわしい I / L / O / U を除いた32文字を使う
  /// (スクリーンショットから読み上げ・打ち直しされても壊れないように)。
  String get refCode {
    final minuteBucket = at.toUtc().millisecondsSinceEpoch ~/ 60000;
    final digest = sha256.convert(utf8.encode('$fingerprint|$minuteBucket')).bytes;
    final buf = StringBuffer('ERR-');
    for (var i = 0; i < 6; i++) {
      buf.write(_refAlphabet[digest[i] % _refAlphabet.length]);
    }
    return buf.toString();
  }

  static const _refAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// fingerprint用の正規化。毎回変わる部分をプレースホルダに潰す。
  /// 置換の順序には意味がある(UUIDを先に潰さないと、後段の数値置換が
  /// UUIDを細切れにしてしまう)。
  static String _normalize(String input) {
    var s = input;

    // 1. UUID
    s = s.replaceAll(
      RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'),
      '<uuid>',
    );
    // 2. ISO8601風のタイムスタンプ
    s = s.replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[^\s,)]*'), '<ts>');
    // 3. URLのクエリ文字列(署名付きURLは毎回全く別物になる)
    s = s.replaceAll(RegExp(r'\?[^\s)"]+'), '?<query>');
    // 4. ファイルパス / ストレージキー
    s = s.replaceAll(RegExp(r'(/[\w.\-]+){2,}'), '<path>');
    // 5. 長い16進(トークン断片・ハッシュ)
    s = s.replaceAll(RegExp(r'\b[0-9a-fA-F]{8,}\b'), '<hex>');
    // 6. 残った数値をすべて潰す。1〜2桁も対象にするのが重要 ——
    //    "chunk 17" と "chunk 4" が別グループになると、チャンク添字ごとに
    //    グループが増えて1つのバグが何百件に散る。HTTPステータスの区別は
    //    [fingerprint]が httpStatus を別に混ぜることで保たれる。
    s = s.replaceAll(RegExp(r'\d+'), '<n>');
    // 7. 連続空白
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 極端に長いメッセージは指紋の安定性を下げるだけなので頭を使う
    return s.length > 300 ? s.substring(0, 300) : s;
  }

  // ---------------------------------------------------------------
  // 生成
  // ---------------------------------------------------------------

  /// 任意の例外を[AppError]に変換する。
  ///
  /// [origin]は必須 — 「どこで起きたか」が指紋の構成要素であり、
  /// ダイジェストメールで最初に見る情報でもあるため、省略させない。
  factory AppError.from(
    Object error, {
    required String origin,
    StackTrace? stack,
    int? httpStatus,
  }) {
    // 既に封筒に入っているものは、originを上書きせずそのまま通す
    // (下位レイヤーが付けた、より具体的なoriginを保つ)。
    if (error is AppError) return error;

    final raw = error.toString();

    if (error is InsufficientCreditsException) {
      return AppError(
        code: error.errorCode == AppErrorCode.noCreditAllocation
            ? AppErrorCode.noCreditAllocation
            : AppErrorCode.insufficientCredits,
        origin: origin,
        raw: raw,
        at: DateTime.now(),
        httpStatus: 402,
        backendCode: error.errorCode,
        stack: stack?.toString(),
      );
    }

    if (error is AccountSuspendedException) {
      return AppError(
        code: AppErrorCode.accountSuspended,
        origin: origin,
        raw: raw,
        at: DateTime.now(),
        httpStatus: 403,
        backendCode: AccountSuspendedException.errorCode,
        stack: stack?.toString(),
      );
    }

    return AppError(
      code: _classify(raw),
      origin: origin,
      raw: raw,
      at: DateTime.now(),
      httpStatus: httpStatus,
      stack: stack?.toString(),
    );
  }

  /// バックエンドの非200レスポンスから作る。
  /// `{"detail": {"error_code": "...", "message": "..."}}` を読み、
  /// error_codeがあればそれを[backendCode]に、既知なら[code]にも昇格する。
  factory AppError.fromResponse({
    required String origin,
    required int statusCode,
    required String body,
  }) {
    String? backendCode;
    String? message;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          backendCode = detail['error_code'] as String?;
          message = detail['message'] as String?;
        } else if (detail is String) {
          message = detail;
        }
        backendCode ??= decoded['error_code'] as String?;
        message ??= decoded['message'] as String?;
      }
    } catch (_) {
      // JSONでない(HTMLのエラーページ等)。bodyをそのまま診断に使う。
    }

    final raw = 'HTTP $statusCode $origin: ${message ?? _clip(body)}';
    final known = backendCode != null && _knownBackendCodes.contains(backendCode);

    return AppError(
      code: known ? backendCode : AppErrorCode.backendRejected,
      origin: origin,
      raw: raw,
      at: DateTime.now(),
      httpStatus: statusCode,
      backendCode: backendCode,
    );
  }

  static const _knownBackendCodes = <String>{
    AppErrorCode.insufficientCredits,
    AppErrorCode.noCreditAllocation,
    AppErrorCode.accountSuspended,
  };

  static String _clip(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  /// 型情報を持たない生文字列からコードを推定する。
  ///
  /// ここは旧 `AppErrorUtils.getFriendlyErrorMessage()` の文字列マッチを
  /// 引き継いだもの。英語の文言を直接返す代わりにコードを返すので、
  /// 表示側でl10nを引けるようになった(=日本語UIでも英語が出ない)。
  static String _classify(String raw) {
    final s = raw.toLowerCase();

    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('networkexception') ||
        s.contains('connection closed') ||
        s.contains('connection refused')) {
      return AppErrorCode.offline;
    }
    if (s.contains('timeoutexception') || s.contains('taking longer than usual')) {
      return AppErrorCode.timeout;
    }
    if (s.contains('session has expired') || s.contains('sessionexpired')) {
      return AppErrorCode.sessionExpired;
    }
    if (s.contains('invalid login credentials') ||
        s.contains('invalid_credentials') ||
        s.contains('invalid email or password')) {
      return AppErrorCode.invalidCredentials;
    }
    if (s.contains('email not confirmed') || s.contains('email_not_confirmed')) {
      return AppErrorCode.emailNotConfirmed;
    }
    if (s.contains('user already registered') ||
        s.contains('user_already_exists') ||
        s.contains('already exists')) {
      return AppErrorCode.emailAlreadyRegistered;
    }
    if (s.contains('password should be at least') || s.contains('weak_password')) {
      return AppErrorCode.weakPassword;
    }
    if (s.contains('unable to validate email address') || s.contains('invalid_email')) {
      return AppErrorCode.invalidEmail;
    }
    if (s.contains('missing email') ||
        s.contains('email or phone') ||
        s.contains('email is required') ||
        s.contains('email required')) {
      return AppErrorCode.missingEmail;
    }
    if (s.contains('missing password') ||
        s.contains('password is required') ||
        s.contains('password required') ||
        s.contains('signup requires a valid password')) {
      return AppErrorCode.missingPassword;
    }
    if (s.contains('email rate limit exceeded') || s.contains('over_email_send_rate_limit')) {
      return AppErrorCode.rateLimited;
    }
    if (s.contains('new password should be different')) {
      return AppErrorCode.samePassword;
    }
    if (s.contains('new email must be different')) {
      return AppErrorCode.sameEmail;
    }

    return AppErrorCode.unknown;
  }

  // ---------------------------------------------------------------
  // 永続化
  // ---------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'v': 1,
        'code': code,
        'origin': origin,
        'raw': raw,
        'at': at.toIso8601String(),
        if (httpStatus != null) 'http': httpStatus,
        if (backendCode != null) 'backend_code': backendCode,
        if (stack != null) 'stack': stack,
      };

  /// ローカルDBに入れる文字列表現。`LocalUploadJobs.lastError` 等はこの形で持つ。
  String encode() => jsonEncode(toJson());

  factory AppError.fromJson(Map<String, dynamic> json) => AppError(
        code: json['code'] as String? ?? AppErrorCode.unknown,
        origin: json['origin'] as String? ?? 'unknown',
        raw: json['raw'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        httpStatus: json['http'] as int?,
        backendCode: json['backend_code'] as String?,
        stack: json['stack'] as String?,
      );

  /// DBに保存された文字列を[AppError]に戻す。
  ///
  /// 旧バージョンが書いた「ただの`e.toString()`」も受け取れる必要がある
  /// (アプリを更新しても、更新前に失敗して残っているジョブ行はそのまま
  /// 残っているため)。その場合はJSONパースに失敗するので、生文字列として
  /// 包み直し、[_classify]で分類だけ付ける。
  static AppError? tryDecode(String? stored, {String origin = 'legacy'}) {
    if (stored == null || stored.trim().isEmpty) return null;

    final trimmed = stored.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> && decoded['code'] != null) {
          return AppError.fromJson(decoded);
        }
      } catch (_) {
        // 下のレガシー経路へ落とす
      }
    }

    return AppError(
      code: _classify(trimmed),
      origin: origin,
      raw: trimmed,
      at: DateTime.now(),
    );
  }

  @override
  String toString() => 'AppError($code @ $origin): $raw';
}
