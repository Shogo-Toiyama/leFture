import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/audio/diagnostic_audio_player.dart';
import 'package:lefture/application/device/device_identity_service.dart';
import 'package:lefture/application/errors/client_diagnostics.dart';
import 'package:lefture/application/errors/error_reporter.dart';
import 'package:lefture/domain/errors/app_error.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase db;
  late ClientDiagnostics diagnostics;
  late ErrorReporter reporter;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    diagnostics = ClientDiagnostics();
    final supabase = SupabaseClient('https://example.invalid', 'fixture');
    reporter = ErrorReporter(
      db: db,
      deviceIdentity: DeviceIdentityService(),
      supabase: supabase,
      diagnostics: diagnostics,
    );
    installErrorReporter(reporter);
    addTearDown(() async {
      reporter.dispose();
      await supabase.dispose();
      await db.close();
    });
  });

  test('the queued sample keeps the screen at the time of the error', () async {
    diagnostics.recordRoute('/home');
    diagnostics.recordRoute('/home/courses/c/:courseId');
    diagnostics.recordRoute('/home/courses/c/:courseId');
    final queued = reporter.report(
      AppError.from(StateError('fixture'), origin: 'test'),
      route: 'dialog:fixture',
    );
    diagnostics.recordRoute('/recording');

    expect(await queued, isTrue);
    final row = (await db.dequeuePendingErrorReports()).single;
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    expect(payload['route'], '/home/courses/c/:courseId');
    final events = _events(payload);
    expect(events.map((event) => event['screen']), [
      '/home',
      '/home/courses/c/:courseId',
    ]);
  });

  test(
    'a stackless native error keeps its player context and safe codes',
    () async {
      diagnostics.recordRoute('/home/courses/c/:courseId');
      final firstPlatform = _FakePlayer();
      final first = DiagnosticAudioPlayer(
        diagnostics,
        surface: DiagnosticSurface.transcriptModal,
        player: firstPlatform,
      );
      final second = DiagnosticAudioPlayer(
        diagnostics,
        surface: DiagnosticSurface.lectureRecoveredRecording,
        player: _FakePlayer(),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final durationSubscription = first.onDurationChanged.listen((_) {});
      addTearDown(durationSubscription.cancel);

      final fixtureUrl = Uri.https('example.invalid', '/', {
        'token': 'fixture-private',
      });
      await first.setSource(UrlSource(fixtureUrl.toString()));
      await first.resume();
      await first.stop();
      await first.seek(
        const Duration(seconds: 4),
        trigger: DiagnosticTrigger.transcriptTap,
      );
      await second.pause();
      final saved = db
          .select(db.localErrorReports)
          .watch()
          .firstWhere((rows) => rows.isNotEmpty);
      final error = PlatformException(
        code: 'AndroidAudioError',
        message: 'MEDIA_ERROR_UNKNOWN {what:-38}',
        details: 'MEDIA_ERROR_UNKNOWN {extra:0}',
      );
      firstPlatform.events.addError(error, StackTrace.empty);
      final row = (await saved).single;
      reportUncaughtError(error, StackTrace.empty);
      await Future<void>.delayed(Duration.zero);

      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final events = _events(payload);
      expect(payload['route'], '/home/courses/c/:courseId');
      expect(row.origin, 'audio.native_event');
      expect(payload['error']['stack'], isNull);
      expect(row.payloadJson, isNot(contains('fixture-private')));
      expect(row.payloadJson, isNot(contains('lectureRecoveredRecording')));
      expect(events, contains(containsPair('action', 'audio.stop')));
      expect(
        events,
        contains(
          allOf(
            containsPair('action', 'audio.seek'),
            containsPair('state', 'stopped'),
            containsPair('trigger', 'transcriptTap'),
          ),
        ),
      );
      expect(
        events.last,
        allOf(containsPair('what', -38), containsPair('extra', 0)),
      );
      expect((await db.dequeuePendingErrorReports()).single.occurrenceCount, 1);
    },
  );

  test(
    'history is bounded and snapshots from a previous session are invalid',
    () async {
      diagnostics.setSessionUser('first-fixture');
      final scope = diagnostics.startScope(
        surface: DiagnosticSurface.transcript,
      );
      for (var i = 0; i < 50; i++) {
        diagnostics.recordRoute('/screen$i');
        diagnostics.record(
          scope,
          DiagnosticAction.audioSeek,
          DiagnosticPhase.acknowledged,
          operation: i,
          trigger: DiagnosticTrigger.restorePosition,
        );
      }
      final captured = diagnostics.snapshot(scope: scope);
      final snapshotEvents = _events({'breadcrumbs': captured.lines});
      expect(
        snapshotEvents.where((entry) => entry.containsKey('operation')).length,
        8,
      );
      expect(
        utf8.encode(jsonEncode(captured.lines)).length,
        lessThanOrEqualTo(2048),
      );

      diagnostics.setSessionUser('second-fixture');
      expect(diagnostics.currentSnapshot(captured), isNull);
      diagnostics.record(
        scope,
        DiagnosticAction.audioSeek,
        DiagnosticPhase.failed,
      );
      final remaining = _events({
        'breadcrumbs': diagnostics.snapshot(scope: scope).lines,
      });
      expect(remaining.single, containsPair('screen', '/screen49'));
      expect(remaining.single, isNot(contains('operation')));
    },
  );

  test('repeated errors retain the existing burst limit', () async {
    diagnostics.recordRoute('/home');
    final error = AppError.from(StateError('fixture'), origin: 'burst_test');
    final outcomes = <bool>[];
    for (var occurrence = 0; occurrence < 4; occurrence++) {
      outcomes.add(await reporter.report(error));
    }
    expect(outcomes, [true, true, true, false]);
    expect((await db.dequeuePendingErrorReports()).single.occurrenceCount, 3);
  });

  test(
    'upload trace keeps its supplied lines outside the diagnostic budget',
    () async {
      diagnostics.recordRoute('/home');
      final lines = List.generate(60, (index) => 'trace fixture $index');
      await reporter.report(
        AppError(
          code: AppErrorCode.uploadTrace,
          origin: 'fixture',
          raw: 'trace fixture',
          at: _fixtureDate,
        ),
        traceLines: lines,
      );
      final row = (await db.dequeuePendingErrorReports()).single;
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['breadcrumbs'], lines);
    },
  );
}

final _fixtureDate = DateTime.utc(2026, 11, 20);

List<Map<String, dynamic>> _events(Map<String, dynamic> payload) => [
  for (final line in (payload['breadcrumbs'] as List).cast<String>())
    if (line.startsWith('diagnostic.v1 '))
      jsonDecode(line.substring('diagnostic.v1 '.length))
          as Map<String, dynamic>,
];

class _FakePlayer implements AudioPlayer {
  final events = StreamController<AudioEvent>.broadcast();
  final states = StreamController<PlayerState>.broadcast();

  @override
  PlayerState state = PlayerState.stopped;

  @override
  Stream<AudioEvent> get eventStream => events.stream;

  @override
  Stream<Duration> get onDurationChanged =>
      events.stream.map((_) => Duration.zero);

  @override
  Stream<PlayerState> get onPlayerStateChanged => states.stream;

  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> resume() async {
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> stop() async {
    state = PlayerState.stopped;
    states.add(state);
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> pause() async {
    state = PlayerState.paused;
    states.add(state);
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
