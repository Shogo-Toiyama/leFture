// application/errors/error_reporter.dart
//
// 予期せぬエラーを開発者へ届けるためのクライアント側パイプライン。
//
// 設計の要は「エラー嵐を3段の漏斗で潰す」こと。1つのバグが1秒間に何十行も
// 例外を吐くことがあり、それを素通しするとDBもメールも受信箱も溢れる。
//
//   A段(メモリ)     同一fingerprintは最初の3件だけ通す。以降は送らず
//                   カウンタを増やし、[_burstWindow]ごとに1回だけ吐き出す。
//                   → DBに到達する前に嵐を潰す。
//   B段(ローカルDB) 1行 = 1 fingerprint。嵐は occurrenceCount=250 の
//                   「1行」になる。
//   C段(サーバー)   fingerprintでグループにupsert。全文コンテキスト付きの
//                   eventは一定数までしか保存しない。
//
// 送信について:
//   * [AuthedHttpClient]は使わない。あれは401を受けると
//     セッションを破棄してサインイン画面へ飛ばす場合があるが、
//     「エラー報告の失敗」でユーザーをログアウトさせるのは本末転倒。
//     ここでは素の http に自分でトークンを載せ、失敗しても
//     セッション状態に一切触れない。
//   * 未ログインでも送れる(sign_in画面のエラーが一番知りたいため)。
//     その場合は anon key + device_id で送る。
//   * 報告処理自体が投げる例外は、絶対に呼び出し元へ伝播させない。
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lefture/application/device/device_identity_service.dart';
import 'package:lefture/application/errors/client_diagnostics.dart';
import 'package:lefture/core/config/app_config.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/errors/app_error.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';

/// A段の通過記録。fingerprintごとに保持する。
class _BurstGate {
  _BurstGate(this.firstAt);

  final DateTime firstAt;
  int passed = 0;
  int suppressed = 0;
}

class ErrorReporter {
  ErrorReporter({
    required AppDatabase db,
    required DeviceIdentityService deviceIdentity,
    required SupabaseClient supabase,
    ClientDiagnostics? diagnostics,
    http.Client? httpClient,
  })  : _db = db,
        _deviceIdentity = deviceIdentity,
        _supabase = supabase,
        _diagnostics = diagnostics ?? ClientDiagnostics(),
        _http = httpClient ?? http.Client() {
    _diagnostics.setSessionUser(supabase.auth.currentUser?.id);
    _authSubscription = supabase.auth.onAuthStateChange.listen(
      (state) => _diagnostics.setSessionUser(state.session?.user.id),
      onError: (Object _, StackTrace _) {},
    );
  }

  final AppDatabase _db;
  final DeviceIdentityService _deviceIdentity;
  final SupabaseClient _supabase;
  final ClientDiagnostics _diagnostics;
  final http.Client _http;
  late final StreamSubscription<AuthState> _authSubscription;

  // --- A段のパラメータ ---

  /// 同一fingerprintをそのまま通す件数。これを超えたら黙って数えるだけ。
  static const _burstAllowance = 3;

  /// A段のカウンタをリセットする間隔。
  static const _burstWindow = Duration(seconds: 60);

  /// 1セッションで扱う別fingerprintの上限。超過分は完全に捨てる
  /// (別々のバグが30種類も同時に出ているなら、31種類目を足しても
  ///  診断の役には立たない)。
  static const _maxDistinctPerSession = 30;

  final Map<String, _BurstGate> _gates = {};

  /// 上限に達して捨てた件数。次に送るレポートに同送して、
  /// 「見えていない分がある」ことだけは開発者に伝える。
  int _droppedDistinct = 0;

  Timer? _flushTimer;
  Future<void>? _flushFuture;
  bool _flushAgain = false;

  // ---------------------------------------------------------------
  // 受け口
  // ---------------------------------------------------------------

  /// エラーを1件受け取る。**この呼び出しは決して例外を投げない。**
  ///
  /// [traceLines]を渡すと、DevLog末尾の代わりにそれをbreadcrumbsとして送る
  /// (UploadTraceの全文用)。
  Future<bool> report(
    AppError error, {
    String? route,
    List<String>? traceLines,
    DiagnosticSnapshot? diagnostics,
  }) async {
    try {
      if (!error.shouldReport) return false;
      // Each trace carries a distinct diagnostic payload, even within one group.
      if (error.code == AppErrorCode.uploadTrace) {
        await _enqueue(
          error,
          route: route,
          breadcrumbs: traceLines ?? _breadcrumbs(40),
        );
        _scheduleFlush();
        return true;
      }

      final fp = error.fingerprint;
      final now = DateTime.now();

      // --- A段 ---
      var gate = _gates[fp];
      var carried = 0;
      if (gate == null) {
        if (_gates.length >= _maxDistinctPerSession) {
          _droppedDistinct++;
          return false;
        }
        gate = _BurstGate(now);
        _gates[fp] = gate;
      } else if (now.difference(gate.firstAt) > _burstWindow) {
        // 窓が明けた。抑制していた分を1件にまとめて通す。
        carried = gate.suppressed;
        gate = _BurstGate(now);
        _gates[fp] = gate;
      }

      if (carried == 0) {
        if (gate.passed >= _burstAllowance) {
          gate.suppressed++;
          return false;
        }
        gate.passed++;
      }

      // --- B段 ---
      final captured = _diagnostics.currentSnapshot(diagnostics);
      final snapshot = captured ?? _diagnostics.snapshot();
      final breadcrumbs = traceLines ?? [
        // Scoped reports use typed context without unrelated free-form logs.
        if (captured == null) ..._breadcrumbs(40 - snapshot.lines.length),
        ...snapshot.lines,
      ];
      await _enqueue(
        error,
        route: snapshot.route ?? route,
        extraOccurrences: carried,
        breadcrumbs: breadcrumbs,
      );
      _scheduleFlush();
      return true;
    } catch (e) {
      // 報告の失敗でアプリを壊さない。DevLogにだけ残す。
      DevLog.add('⚠️ [ErrorReporter] report() failed: $e');
      return false;
    }
  }

  Future<void> _enqueue(
    AppError error, {
    String? route,
    int extraOccurrences = 0,
    required List<String> breadcrumbs,
  }) async {
    final payload = <String, dynamic>{
      'error': error.toJson(),
      'route': route,
      'breadcrumbs': breadcrumbs,
      if (extraOccurrences > 0) 'suppressed': extraOccurrences,
    };

    await _db.enqueueErrorReport(
      coalesce: error.code != AppErrorCode.uploadTrace,
      fingerprint: error.fingerprint,
      refCode: error.refCode,
      code: error.code,
      origin: error.origin,
      payloadJson: jsonEncode(payload),
    );
  }

  /// DevLogのリングバッファ末尾。エラー直前に何が起きていたかの手掛かり。
  /// uid等が混ざり得るのでサーバー側でもマスクするが、ここでも量を絞る。
  List<String> _breadcrumbs(int take) {
    final lines = DevLog.lines.value;
    return lines.length <= take ? List.of(lines) : lines.sublist(lines.length - take);
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 20), () => unawaited(flush()));
  }

  // ---------------------------------------------------------------
  // 送信
  // ---------------------------------------------------------------

  /// キューをまとめて送る。アプリ起動時・フォアグラウンド復帰時・
  /// バックグラウンド遷移時に呼ぶ。
  Future<void> flush() {
    _flushAgain = true;
    return _flushFuture ??= _drain().whenComplete(() => _flushFuture = null);
  }

  Future<void> _drain() async {
    do {
      _flushAgain = false;
      await _flushBatch();
    } while (_flushAgain);
  }

  Future<void> _flushBatch() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.every((r) => r == ConnectivityResult.none)) return;

      await _db.pruneErrorReports();
      final rows = await _db.dequeuePendingErrorReports();
      if (rows.isEmpty) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final deviceId = await _deviceIdentity.getOrCreateDeviceId();
      final session = _supabase.auth.currentSession;

      final reports = rows.map((r) {
        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(r.payloadJson) as Map<String, dynamic>;
        } catch (_) {
          payload = {'error': {'raw': r.payloadJson}};
        }
        return {
          'report_id': r.id.toString(),
          'fingerprint': r.fingerprint,
          'ref_code': r.refCode,
          'code': r.code,
          'origin': r.origin,
          'occurrence_count': r.occurrenceCount,
          'first_seen_at': r.firstSeenAt.toUtc().toIso8601String(),
          'last_seen_at': r.lastSeenAt.toUtc().toIso8601String(),
          ...payload,
        };
      }).toList();

      final body = {
        'device_id': deviceId,
        'app_version': '${packageInfo.version} (${packageInfo.buildNumber})',
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
        'is_authenticated': session != null,
        'dropped_distinct': _droppedDistinct,
        'reports': reports,
      };

      final headers = <String, String>{
        'Content-Type': 'application/json',
        // 未ログインでも送れるようにする。サーバー側は user JWT が付いて
        // いれば user_id を紐づけ、無ければ device_id だけで受ける。
        'Authorization': 'Bearer ${session?.accessToken ?? _anonKey}',
        'X-Client-Report': '1',
      };

      final res = await _http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/client-errors/report'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      // サーバーは受理できた限り2xxを返す(レート制限で捨てた場合も202)。
      // 2xxならローカルからは消してよい。
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Traces require an explicit acknowledgement that their full event was
        // stored. Older servers, partial failures and sample caps retain them.
        final decoded = jsonDecode(res.body);
        final acknowledged = decoded is Map
            ? (decoded['accepted_report_ids'] as List? ?? const []).toSet()
            : <dynamic>{};
        final sent = rows.where((r) =>
            r.code != AppErrorCode.uploadTrace || acknowledged.contains(r.id.toString()));
        final retained = rows.where((r) =>
            r.code == AppErrorCode.uploadTrace && !acknowledged.contains(r.id.toString()));
        await _db.deleteErrorReportIds(sent.map((r) => r.id).toList());
        for (final row in retained) {
          await _db.recordErrorReportFailure(row.id);
        }
        if (rows.length == 50 && sent.isNotEmpty) _flushAgain = true;
        _droppedDistinct = 0;
        DevLog.add('📮 [ErrorReporter] Sent ${sent.length} report(s)');
      } else {
        for (final r in rows) {
          await _db.recordErrorReportFailure(r.id);
        }
        DevLog.add('⚠️ [ErrorReporter] Server returned ${res.statusCode}');
      }
    } catch (e) {
      DevLog.add('⚠️ [ErrorReporter] flush() failed: $e');
      // 個別のバックオフは次回 flush 時に dequeue 条件で効く
    }
  }

  /// 未送信のレポートが残っているか。SnagCardの
  /// 「通知済み / オンライン復帰時に通知します」の出し分けに使う。
  Future<bool> hasPendingReports() async {
    try {
      return await _db.countPendingErrorReports() > 0;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    unawaited(_authSubscription.cancel());
  }

  /// main.dart の supabaseAnonKey と同じ値。未ログイン時の送信に使う。
  /// 公開可能なキー(sb_publishable_)なので埋め込んで問題ない。
  static const _anonKey = 'sb_publishable_LUfg9T2f-zvargd7GgR7Cw_KAl86N8c';
}

/// アプリ全体で1つ。[reportAppError]から使う。
final errorReporterProvider = Provider<ErrorReporter>((ref) {
  final reporter = ErrorReporter(
    db: ref.watch(appDatabaseProvider),
    deviceIdentity: ref.watch(deviceIdentityServiceProvider),
    supabase: Supabase.instance.client,
    diagnostics: ref.watch(clientDiagnosticsProvider),
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});

// ---------------------------------------------------------------
// Riverpod の外から呼ぶための口
// ---------------------------------------------------------------

/// main.dart のグローバルエラーハンドラや、ProviderScopeを持たない
/// 場所から報告するための参照。[installErrorReporter]で差し込む。
ErrorReporter? _global;

void installErrorReporter(ErrorReporter reporter) {
  _global = reporter;
}

/// どこからでも呼べる報告関数。Reporterが未設置なら黙って何もしない。
void reportAppError(
  AppError error, {
  String? route,
  List<String>? traceLines,
  DiagnosticSnapshot? diagnostics,
}) {
  unawaited(_global?.report(
    error,
    route: route,
    traceLines: traceLines,
    diagnostics: diagnostics,
  ));
}

void reportUncaughtError(Object error, StackTrace stack) {
  final reporter = _global;
  if (reporter == null || reporter._diagnostics.wasNativeErrorReported(error)) {
    return;
  }
  unawaited(reporter.report(
    AppError.from(error, origin: 'main.uncaught', stack: stack),
    diagnostics: reporter._diagnostics.failureSnapshot(error),
  ));
}

/// Persist the report before starting delivery. True means durably queued,
/// not server acknowledgement. A failed enqueue must preserve the source file.
Future<bool> reportAppErrorAndFlush(AppError error, {List<String>? traceLines}) async {
  final reporter = _global;
  if (reporter == null) return false;
  final queued = await reporter.report(error, traceLines: traceLines);
  if (queued) unawaited(reporter.flush());
  return queued;
}

/// 例外をその場で封筒に入れて報告する短縮形。
AppError reportRawError(
  Object error, {
  required String origin,
  StackTrace? stack,
  String? route,
}) {
  final appError = AppError.from(error, origin: origin, stack: stack);
  reportAppError(
    appError,
    route: route,
    diagnostics: _global?._diagnostics.failureSnapshot(error),
  );
  return appError;
}
