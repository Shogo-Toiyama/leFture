import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:lefture/application/errors/client_diagnostics.dart';
import 'package:lefture/application/errors/error_reporter.dart';
import 'package:lefture/domain/errors/app_error.dart';

/// Observes one lecture playback instance without changing command ordering.
class DiagnosticAudioPlayer {
  DiagnosticAudioPlayer(
    this._diagnostics, {
    required DiagnosticSurface surface,
    AudioPlayer? player,
  }) : _player = player ?? AudioPlayer(),
       _scope = _diagnostics.startScope(surface: surface) {
    _events = _player.eventStream.listen((event) {
      if (event.eventType == AudioEventType.prepared &&
          event.isPrepared == true) {
        _observe(DiagnosticAction.audioPrepared, _player.state);
      }
    }, onError: _onNativeError);
    _states = _player.onPlayerStateChanged.listen(
      (state) => _observe(DiagnosticAction.audioState, state),
    );
  }

  final AudioPlayer _player;
  final ClientDiagnostics _diagnostics;
  final DiagnosticScope _scope;
  late final StreamSubscription<AudioEvent> _events;
  late final StreamSubscription<PlayerState> _states;
  DiagnosticSource _source = DiagnosticSource.unknown;

  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;
  Stream<Duration> get onDurationChanged =>
      _player.onDurationChanged.handleError(
        // The same native event is reported once by the dedicated subscription.
        (Object _, StackTrace _) {},
        test: _isNativeAudioError,
      );

  Future<void> setReleaseMode(ReleaseMode mode) => _player.setReleaseMode(mode);
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);

  Future<void> setSource(Source source) {
    _source = switch (source) {
      UrlSource() => DiagnosticSource.remote,
      DeviceFileSource() || AssetSource() => DiagnosticSource.local,
      BytesSource() => DiagnosticSource.memory,
      _ => DiagnosticSource.unknown,
    };
    return _run(
      DiagnosticAction.audioSetSource,
      () => _player.setSource(source),
    );
  }

  Future<void> seek(Duration position, {DiagnosticTrigger? trigger}) => _run(
    DiagnosticAction.audioSeek,
    () => _player.seek(position),
    trigger: trigger,
  );

  Future<void> resume() => _run(DiagnosticAction.audioPlay, _player.resume);
  Future<void> pause() => _run(DiagnosticAction.audioPause, _player.pause);
  Future<void> stop() => _run(DiagnosticAction.audioStop, _player.stop);

  Future<void> dispose() async {
    try {
      await _run(DiagnosticAction.audioDispose, _player.dispose);
    } finally {
      await _events.cancel();
      await _states.cancel();
    }
  }

  Future<void> _run(
    DiagnosticAction action,
    Future<void> Function() command, {
    DiagnosticTrigger? trigger,
  }) async {
    final operation = _diagnostics.nextOperation();
    final startedAt = _diagnostics.elapsedMs;
    final source = _source;
    void record(DiagnosticPhase phase) {
      _diagnostics.record(
        _scope,
        action,
        phase,
        operation: operation,
        durationMs: phase == DiagnosticPhase.requested
            ? null
            : _diagnostics.elapsedMs - startedAt,
        state: _player.state,
        source: source,
        trigger: trigger,
      );
    }

    record(DiagnosticPhase.requested);
    try {
      await command();
      record(DiagnosticPhase.acknowledged);
    } catch (error) {
      record(DiagnosticPhase.failed);
      _diagnostics.rememberFailure(error, _scope);
      rethrow;
    }
  }

  void _observe(DiagnosticAction action, PlayerState state) {
    _diagnostics.record(
      _scope,
      action,
      DiagnosticPhase.observed,
      state: state,
      source: _source,
    );
  }

  void _onNativeError(Object error, StackTrace stack) {
    // The SDK continues to handle errors on its own subscriptions and futures.
    if (error is! PlatformException || !_isNativeAudioError(error)) return;
    if (!_diagnostics.isCurrentScope(_scope) ||
        _diagnostics.wasNativeErrorReported(error)) {
      return;
    }
    final what = _readCode(error.message, _what);
    final details = error.details;
    final extra = _readCode(details is String ? details : null, _extra);
    _diagnostics.record(
      _scope,
      DiagnosticAction.audioNativeError,
      DiagnosticPhase.failed,
      state: _player.state,
      source: _source,
      what: what,
      extra: extra,
    );
    _diagnostics.markNativeErrorReported(error);
    const mediaStatuses = {
      'MEDIA_ERROR_SERVER_DIED',
      'MEDIA_ERROR_SYSTEM',
      'MEDIA_ERROR_IO',
      'MEDIA_ERROR_MALFORMED',
      'MEDIA_ERROR_UNSUPPORTED',
      'MEDIA_ERROR_TIMED_OUT',
    };
    final nativeStatuses = [
      error.message,
      details,
    ].whereType<String>().where(mediaStatuses.contains);
    final nativeStack = error.stacktrace;
    reportAppError(
      AppError(
        code: AppErrorCode.unknown,
        origin: 'audio.native_event',
        raw: [
          error.code,
          if (what != null) 'what=$what',
          if (extra != null) 'extra=$extra',
          ...nativeStatuses,
        ].join(' '),
        at: DateTime.now(),
        stack: stack.toString().isNotEmpty ? stack.toString() : nativeStack,
      ),
      diagnostics: _diagnostics.snapshot(scope: _scope),
    );
  }

  static final _what = RegExp(r'^MEDIA_ERROR_UNKNOWN \{what:(-?\d{1,10})\}$');
  static final _extra = RegExp(r'^MEDIA_ERROR_UNKNOWN \{extra:(-?\d{1,10})\}$');

  static bool _isNativeAudioError(Object? error) =>
      error is PlatformException &&
      (error.code == 'AndroidAudioError' || error.code == 'DarwinAudioError');

  static int? _readCode(String? value, RegExp pattern) => value == null
      ? null
      : int.tryParse(pattern.firstMatch(value)?.group(1) ?? '');
}
