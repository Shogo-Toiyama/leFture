import 'dart:collection';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

final clientDiagnosticsProvider = Provider<ClientDiagnostics>(
  (_) => ClientDiagnostics(),
);

enum DiagnosticSurface {
  transcript,
  transcriptModal,
  lectureNotStarted,
  lectureRecoveredRecording,
}

enum DiagnosticTrigger {
  autoHighlight,
  restorePosition,
  transcriptTap,
  slider,
  skip,
}

enum DiagnosticSource { local, remote, memory, unknown }

enum DiagnosticPhase { requested, acknowledged, failed, observed }

enum DiagnosticAction {
  audioSetSource('audio.set_source'),
  audioPlay('audio.play'),
  audioPause('audio.pause'),
  audioSeek('audio.seek'),
  audioStop('audio.stop'),
  audioDispose('audio.dispose'),
  audioPrepared('audio.prepared'),
  audioState('audio.state'),
  audioNativeError('audio.native_error');

  const DiagnosticAction(this.label);

  final String label;
}

class DiagnosticScope {
  DiagnosticScope._(this._generation, this.id, this.surface, this.startedRoute);

  final int _generation;
  final int id;
  final DiagnosticSurface? surface;
  final String? startedRoute;
}

class DiagnosticSnapshot {
  DiagnosticSnapshot._(this.route, List<String> lines, this._generation)
    : lines = List.unmodifiable(lines);

  final String? route;
  final List<String> lines;
  final int _generation;
}

/// Bounded, process-local history. Only snapshots are persisted with reports.
class ClientDiagnostics {
  final _clock = Stopwatch()..start();
  final _routes = Queue<({int at, String name})>();
  final _events =
      Queue<({int at, DiagnosticScope scope, Map<String, Object> data})>();
  final _failures = Expando<DiagnosticSnapshot>();
  final _reportedNativeErrors = Expando<int>();
  int _generation = 0;
  int _nextId = 0;
  String? _sessionUser;

  String? get route => _routes.lastOrNull?.name;
  int get elapsedMs => _clock.elapsedMilliseconds;
  int nextOperation() => ++_nextId;

  void recordRoute(String? template) {
    if (template == null || template == route) return;
    if (_routes.length == 8) _routes.removeFirst();
    _routes.add((at: elapsedMs, name: template));
  }

  void setSessionUser(String? userId) {
    if (_sessionUser == userId) return;
    final currentRoute = route;
    _sessionUser = userId;
    _generation++;
    _routes.clear();
    _events.clear();
    recordRoute(currentRoute);
  }

  DiagnosticScope startScope({DiagnosticSurface? surface}) =>
      DiagnosticScope._(_generation, nextOperation(), surface, route);

  bool isCurrentScope(DiagnosticScope scope) =>
      scope._generation == _generation;

  void record(
    DiagnosticScope scope,
    DiagnosticAction action,
    DiagnosticPhase phase, {
    int? operation,
    int? durationMs,
    Enum? state,
    DiagnosticSource? source,
    DiagnosticTrigger? trigger,
    int? what,
    int? extra,
  }) {
    if (!isCurrentScope(scope)) return;
    if (_events.length == 24) _events.removeFirst();
    _events.add((
      at: elapsedMs,
      scope: scope,
      data: {
        'action': action.label,
        'phase': phase.name,
        'scope': scope.id,
        if (scope.surface case final surface?) 'surface': surface.name,
        if (operation != null) 'operation': operation,
        if (durationMs != null) 'duration_ms': durationMs,
        if (state != null) 'state': state.name,
        if (source != null) 'source': source.name,
        if (trigger != null) 'trigger': trigger.name,
        if (what != null) 'what': what,
        if (extra != null) 'extra': extra,
      },
    ));
  }

  DiagnosticSnapshot snapshot({DiagnosticScope? scope}) {
    final now = elapsedMs;
    final events = scope == null
        ? const <({int at, DiagnosticScope scope, Map<String, Object> data})>[]
        : _events.where((event) => identical(event.scope, scope)).toList();
    final recentRoutes = _routes.toList().reversed.take(3).toList().reversed;
    final lines = [
      for (final event in recentRoutes)
        _line({'screen': event.name, 'offset_ms': event.at - now}),
      if (scope?._generation == _generation && scope?.startedRoute != null)
        _line({'started_screen': scope!.startedRoute!}),
      for (final event in events.reversed.take(8).toList().reversed)
        _line({...event.data, 'offset_ms': event.at - now}),
    ];
    // Keep the most recent entries under the serialized payload budget.
    while (utf8.encode(jsonEncode(lines)).length > 2048) {
      lines.removeAt(0);
    }
    return DiagnosticSnapshot._(route, lines, _generation);
  }

  DiagnosticSnapshot? currentSnapshot(DiagnosticSnapshot? captured) =>
      captured?._generation == _generation ? captured : null;

  void rememberFailure(Object error, DiagnosticScope scope) {
    if ((error is Exception || error is Error) && isCurrentScope(scope)) {
      _failures[error] ??= snapshot(scope: scope);
    }
  }

  DiagnosticSnapshot? failureSnapshot(Object error) {
    if (error is Exception || error is Error) {
      return currentSnapshot(_failures[error]);
    }
    return null;
  }

  void markNativeErrorReported(Exception error) {
    _reportedNativeErrors[error] = _generation;
  }

  bool wasNativeErrorReported(Object error) =>
      error is Exception && _reportedNativeErrors[error] == _generation;

  String _line(Map<String, Object> data) => 'diagnostic.v1 ${jsonEncode(data)}';
}
