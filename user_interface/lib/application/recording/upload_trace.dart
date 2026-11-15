// application/recording/upload_trace.dart
//
// Realtime Transcribeで録音した講義の「録音停止〜アップロード完了」の全ログを、
// 成功・失敗を問わず開発者へ送るための記録係。
//
// なぜ別物にしたか:
//   DevLogのリングバッファ(300行)はメモリ上にしかなく、録音中は毎秒の
//   Timerログで数分で押し流される。アップロードが「例外を出さずに止まる」
//   (OSにアプリを止められる等)場合は、報告のきっかけ自体が無い。そこで
//   講義単位のファイルへ追記しておき、完了時、または一定時間進まないときに
//   まとめて送る。ファイルなのでアプリが止められても残る。
//
// 流れ:
//   begin(lectureId)  ... 保存ボタン直後(Realtime録音のときだけ)
//   DevLog.tap        ... 以降のDevLogを、開いている全traceへ追記
//   finish(lectureId) ... all required jobs completed, cancelled, or deleted
//   sweep()           ... 進まないtraceを'stuck'として送る(ファイルは残す。
//                         その後に完了すれば、もう一度'completed'で送る)
//
// 送信は既存のErrorReporter(UPLOAD_TRACEコード)に乗せる。ログ本文は
// breadcrumbsとして届き、サーバー側でマスクされてclient_error_eventsに入る。
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:lefture/application/errors/error_reporter.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/errors/app_error.dart';

class UploadTrace {
  UploadTrace._();

  /// 1講義で保持する最大行数。超えたら追記を止める(無限増殖の防波堤)。
  static const int maxLines = 3000;

  /// 1行の最大文字数。
  static const int maxLineLength = 600;

  /// 最後のジョブ成功からこれだけ経っても完了しないtraceを'stuck'として送る。
  static const Duration stuckAfter = Duration(minutes: 15);

  /// 起動時に見つけた未完了traceを'interrupted'として送るしきい値。
  /// (アプリが終了されていた間に進まなくなった分。短い中断は無視する)
  static const Duration interruptedAfter = Duration(minutes: 2);

  /// 完了しないまま放置されたtraceを破棄するまでの期間。
  static const Duration abandonAfter = Duration(days: 7);

  static Directory? _dir;
  static Future<void>? _initializing;
  static Timer? _sweepTimer;
  static final Map<String, Future<void>> _operations = {};

  // The upload manager supplies local DB state; unrelated logs are not progress.
  static Future<({String? outcome, DateTime? progressedAt})> Function(String)? inspect;
  static Iterable<String> get activeLectureIds => _active.keys.toList();
  static bool _inTap = false;

  /// lectureId -> 開始時刻
  static final Map<String, DateTime> _active = {};
  static final Map<String, int> _lineCounts = {};


  static File _logFile(String lectureId) => File('${_dir!.path}/$lectureId.log');
  static File _stuckMarker(String lectureId) => File('${_dir!.path}/$lectureId.stuck');
  static File _outcomeFile(String lectureId) => File('${_dir!.path}/$lectureId.outcome');

  static Future<void> _serialized(String id, Future<void> Function() action) {
    final previous = _operations[id] ?? Future<void>.value();
    late final Future<void> next;
    next = previous.then((_) => action()).whenComplete(() {
      if (identical(_operations[id], next)) _operations.remove(id);
    });
    _operations[id] = next;
    return next;
  }

  /// Release hooks and timers without deleting durable diagnostic files.
  static void dispose() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    DevLog.tap = null;
    _active.clear();
    _lineCounts.clear();
    _dir = null;
    _initializing = null;
    inspect = null;
  }

  /// アプリ起動時に1回。ディレクトリを用意し、前回から残っているtraceを
  /// 拾い直し、DevLogへフックを掛ける。例外は呼び出し元へ伝播させない。
  static Future<void> init() => _initializing ??= _initialize();

  static Future<void> _initialize() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/upload_traces');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dir = dir;

      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.log')) continue;
        final lectureId = entity.uri.pathSegments.last.replaceAll('.log', '');
        final lines = await entity.readAsLines();
        _active[lectureId] = _parseStart(lines) ?? (await entity.lastModified());
        _lineCounts[lectureId] = lines.length;
      }

      DevLog.tap = _onLine;
      await sweep(threshold: interruptedAfter, outcome: 'interrupted');
      _sweepTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(sweep());
      });
    } catch (e) {
      DevLog.tap = null;
      DevLog.add('⚠️ [UploadTrace] init failed: $e');
    }
  }

  static DateTime? _parseStart(List<String> lines) {
    if (lines.isEmpty) return null;
    final m = RegExp(r'^# started=(\S+)').firstMatch(lines.first);
    return m == null ? null : DateTime.tryParse(m.group(1)!);
  }

  /// Realtime録音の保存直後に呼ぶ。直前のDevLog(録音中のチャンク送信など)も
  /// 前置きとして書き出す。
  static Future<void> begin(String lectureId, {List<String> preamble = const []}) async {
    await init();
    if (_dir == null) return;
    await _serialized(lectureId, () async {
    if (_active.containsKey(lectureId)) return;
    try {
      final now = DateTime.now();
      final buf = StringBuffer('# started=${now.toIso8601String()} lecture=$lectureId\n');
      for (final l in preamble) {
        if (_isNoise(l)) continue;
        buf.writeln(_clip(l));
      }
      buf.writeln('--- stop pressed, upload phase begins ---');
      await _logFile(lectureId).writeAsString(buf.toString());
      if (await _stuckMarker(lectureId).exists()) await _stuckMarker(lectureId).delete();
      _active[lectureId] = now;
      _lineCounts[lectureId] = buf.toString().split('\n').length;

    } catch (e) {
      DevLog.add('⚠️ [UploadTrace] begin failed: $e');
    }
    });
  }

  static bool _isNoise(String line) => line.contains('[Timer] Tick');

  static String _clip(String line) =>
      line.length <= maxLineLength ? line : '${line.substring(0, maxLineLength)}…';

  static void _onLine(String line) {
    if (_inTap || _active.isEmpty || _isNoise(line)) return;
    _inTap = true;
    try {
      final clipped = _clip(line);
      for (final id in _active.keys.toList()) {
        final n = _lineCounts[id] ?? 0;
        if (n > maxLines) continue;
        final text = n == maxLines ? '$clipped\n--- truncated: line limit reached ---\n' : '$clipped\n';
        _logFile(id).writeAsStringSync(text, mode: FileMode.append);
        _lineCounts[id] = n + 1;
      }
    } catch (_) {
      // 診断のために本処理を壊さない
    } finally {
      _inTap = false;
    }
  }

  /// Close only after a durable queue insertion. Failed insertions retain both
  /// the source and terminal outcome for the periodic retry or next launch.
  static Future<void> finish(String lectureId, {String outcome = 'completed'}) =>
      _serialized(lectureId, () => _finish(lectureId, outcome));

  static Future<void> _finish(String lectureId, String outcome) async {
    if (!_active.containsKey(lectureId)) return;
    try {
      await _outcomeFile(lectureId).writeAsString(outcome, flush: true);
      if (await _send(lectureId, outcome)) await _remove(lectureId);
    } catch (e) {
      DevLog.add('⚠️ [UploadTrace] finish failed: $e');
    }
  }

  /// Poll repeatedly. Only completed upload jobs move the inactivity deadline;
  /// unrelated DevLog lines and failing retries cannot hide a stalled upload.
  static Future<void> sweep({
    Duration threshold = stuckAfter,
    String outcome = 'stuck',
    DateTime? now,
  }) async {
    if (_dir == null) return;
    for (final id in _active.keys.toList()) {
      await _serialized(id, () async {
        try {
          if (!_active.containsKey(id)) return;
          final file = _logFile(id);
          if (!await file.exists()) return;
          final terminal = _outcomeFile(id);
          if (await terminal.exists()) {
            await _finish(id, await terminal.readAsString());
            return;
          }
          final status = await inspect?.call(id);
          if (status?.outcome != null) {
            await _finish(id, status!.outcome!);
            return;
          }
          final at = now ?? DateTime.now();
          final started = _active[id]!;
          if (at.difference(started) > abandonAfter) {
            await _finish(id, 'abandoned');
            return;
          }
          final progressed = status?.progressedAt;
          final lastProgress = progressed != null && progressed.isAfter(started)
              ? progressed : started;
          if (at.difference(lastProgress) < threshold ||
              await _stuckMarker(id).exists()) return;
          if (await _send(id, outcome)) {
            await _stuckMarker(id).writeAsString('queued', flush: true);
          }
        } catch (e) {
          DevLog.add('⚠️ [UploadTrace] sweep failed for $id: $e');
        }
      });
    }
  }

  static Future<void> _remove(String lectureId) async {
    _active.remove(lectureId);
    _lineCounts.remove(lectureId);
    for (final f in [_logFile(lectureId), _stuckMarker(lectureId), _outcomeFile(lectureId)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  static Future<bool> _send(String lectureId, String outcome) async {
    try {
      final lines = await _logFile(lectureId).readAsLines();
      final started = _active[lectureId] ?? DateTime.now();
      final elapsed = DateTime.now().difference(started);
      final short = lectureId.length >= 8 ? lectureId.substring(0, 8) : lectureId;
      // rawの数値・UUIDはfingerprintで潰れるので、outcomeごとに1グループになる。
      final error = AppError(
        code: AppErrorCode.uploadTrace,
        origin: 'upload_trace.realtime',
        raw: 'Realtime upload trace: $outcome (lecture $short, ${lines.length} lines, '
            '${elapsed.inMinutes}m${elapsed.inSeconds % 60}s since stop)',
        at: DateTime.now(),
      );
      // 同じ指紋の未送信行は最新で上書きされるため、溜めずにすぐ流す。
      return await reportAppErrorAndFlush(error, traceLines: lines);
    } catch (e) {
      DevLog.add('⚠️ [UploadTrace] send failed: $e');
      return false;
    }
  }
}
