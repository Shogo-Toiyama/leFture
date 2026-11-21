import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lefture/app/diagnostic_route.dart';
import 'package:lefture/application/errors/client_diagnostics.dart';

void main() {
  testWidgets('reads the visible route template across go, push and pop', (
    tester,
  ) async {
    final diagnostics = ClientDiagnostics();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const SizedBox(),
          routes: [
            GoRoute(
              path: 'courses/:courseId/lectures/:lectureId/transcript',
              builder: (_, _) => const SizedBox(),
            ),
          ],
        ),
        GoRoute(path: '/recording', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/redirect', redirect: (_, _) => '/home'),
      ],
      errorBuilder: (_, _) => const SizedBox(),
    );
    final stopObserving = observeDiagnosticRoutes(router, diagnostics);
    addTearDown(router.dispose);
    addTearDown(stopObserving);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(diagnostics.route, '/home');
    router.go(
      '/home/courses/course-fixture/lectures/lecture-fixture/transcript',
    );
    await tester.pumpAndSettle();
    expect(
      diagnostics.route,
      '/home/courses/:courseId/lectures/:lectureId/transcript',
    );
    router.go(
      '/home/courses/course-fixture/lectures/lecture-fixture/transcript'
      '?highlight_sids=fixture',
    );
    await tester.pumpAndSettle();

    unawaited(router.push<void>('/recording?courseId=course-fixture'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.fullPath,
      isNot('/recording'),
    );
    expect(diagnostics.route, '/recording');

    router.pop();
    await tester.pumpAndSettle();
    expect(
      diagnostics.route,
      '/home/courses/:courseId/lectures/:lectureId/transcript',
    );
    router.go('/redirect?code=fixture');
    await tester.pumpAndSettle();
    router.go('/unknown/private-fixture');
    await tester.pumpAndSettle();

    expect(diagnostics.route, 'routing_error');
    final history = diagnostics.snapshot().lines;
    expect(history, hasLength(3));
    expect(
      history[0],
      contains('/home/courses/:courseId/lectures/:lectureId/transcript'),
    );
    expect(history[1], contains('"/home"'));
    expect(history[2], contains('routing_error'));
    expect(history.join(), isNot(contains('fixture')));
    await tester.pumpWidget(const SizedBox());
  });
}
