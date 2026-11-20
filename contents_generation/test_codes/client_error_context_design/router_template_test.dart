import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

String? visibleRouteTemplate(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  final top = configuration.lastOrNull;
  final visible = top is ImperativeRouteMatch ? top.matches : configuration;
  if (visible.isError) return 'routing_error';
  return visible.isEmpty ? null : visible.fullPath;
}

void main() {
  testWidgets('reads the visible route template across go, push and pop', (
    tester,
  ) async {
    final screens = <String?>[];
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
    void onNavigation() {
      final template = visibleRouteTemplate(router);
      if (screens.isEmpty || screens.last != template) screens.add(template);
    }

    router.routerDelegate.addListener(onNavigation);
    addTearDown(() {
      router.routerDelegate.removeListener(onNavigation);
      router.dispose();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go(
      '/home/courses/course-fixture/lectures/lecture-fixture/transcript',
    );
    await tester.pumpAndSettle();
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
    expect(visibleRouteTemplate(router), '/recording');

    router.pop();
    await tester.pumpAndSettle();
    router.go('/redirect?code=fixture');
    await tester.pumpAndSettle();
    router.go('/unknown/private-fixture');
    await tester.pumpAndSettle();

    expect(screens, [
      '/home',
      '/home/courses/:courseId/lectures/:lectureId/transcript',
      '/recording',
      '/home/courses/:courseId/lectures/:lectureId/transcript',
      '/home',
      'routing_error',
    ]);
    await tester.pumpWidget(const SizedBox());
  });
}
