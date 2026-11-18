import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/core/utils/topic_image_paths.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/lecture_hero_collage.dart';
import 'package:lefture/presentation/pages/review_cards/review_cards_viewer_page.dart';
import 'package:lefture/presentation/widgets/topic_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _UnusedDatabase implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Review Cards supports relative drag and absolute taps', (
    tester,
  ) async {
    await Supabase.initialize(
      url: 'https://review-cards.invalid',
      anonKey: 'local-widget-test',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
    addTearDown(() => Supabase.instance.dispose());

    const currentPath = 'u/l/images/topic_5.jpg';
    final thumbnail = Completer<File>();
    final original = Completer<File>();
    final requests = <String>[];
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        artifactFileProvider.overrideWith((_, path) {
          requests.add(path);
          return path == currentPath ? original.future : thumbnail.future;
        }),
        appDatabaseProvider.overrideWithValue(_UnusedDatabase()),
        lectureProvider('l').overrideWith((_) => Stream.value(null)),
        courseListProvider.overrideWith((_) => Stream.value([])),
        reviewCardsProvider('l').overrideWith((_) => Stream.value([])),
        lectureTopicsProvider('l').overrideWith(
          (_) => Stream.value([
            for (var i = 0; i < 10; i++)
              LectureTopic(
                id: 'topic-$i',
                index: i + 1,
                topicTitle: 'Topic ${i + 1}',
                imagePath: i == 4 ? currentPath : null,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReviewCardsViewerPage(lectureId: 'l', initialIndex: 4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 / 10'), findsOneWidget);
    expect(requests, [thumbnailPathFor(currentPath)]);
    thumbnail.complete(File('assets/icon.png'));
    await tester.pumpAndSettle();
    expect(requests, [thumbnailPathFor(currentPath), currentPath]);
    expect(find.byKey(const ValueKey('thumb')), findsOneWidget);

    original.completeError(StateError('Original image unavailable'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thumb')), findsOneWidget);
    expect(find.byTooltip('Retry image download'), findsOneWidget);

    final bar = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onTapUp != null &&
            widget.onHorizontalDragStart != null,
      ),
    );
    for (final start in [0.15, 0.70]) {
      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * start, bar.center.dy),
      );
      await gesture.moveBy(Offset(bar.width * 0.12, 0));
      await tester.pump();
      expect(find.text('6 / 10'), findsOneWidget);
      await gesture.moveBy(Offset(-bar.width * 0.24, 0));
      await tester.pump();
      expect(find.text('4 / 10'), findsOneWidget);
      await gesture.moveBy(Offset(bar.width * 0.12, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('5 / 10'), findsOneWidget);
    }
    await tester.tapAt(Offset(bar.left + bar.width * 0.85, bar.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('9 / 10'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('topic thumbnail uses the production key convention', () {
    expect(
      thumbnailPathFor('user/lecture/images/topic_10.jpg'),
      'user/lecture/images/topic_10_thumb192.webp',
    );
    expect(thumbnailPathFor('assets/tutorial.jpg'), isNull);
  });

  testWidgets('all ten collage thumbnails are attempted before originals', (
    tester,
  ) async {
    final paths = List.generate(10, (i) => 'u/l/images/topic_${i + 1}.jpg');
    final thumbnails = paths.map((path) => thumbnailPathFor(path)!).toList();
    final requests = <String, Completer<File>>{};
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          lectureTopicsProvider('l').overrideWith(
            (_) => Stream.value([
              for (var i = 0; i < paths.length; i++)
                LectureTopic(
                  id: 'topic-$i',
                  index: i + 1,
                  imagePath: paths[i],
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
            ]),
          ),
          artifactFileProvider.overrideWith(
            (_, path) => requests.putIfAbsent(path, Completer<File>.new).future,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LectureHeroCollage(lectureId: 'l')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TopicImage), findsNWidgets(10));
    expect(requests.keys, thumbnails.take(3));

    for (final (index, path) in thumbnails.indexed) {
      expect(requests, contains(path));
      if (index == 9) {
        requests[path]!.completeError(StateError('Missing thumbnail'));
      } else {
        requests[path]!.complete(File('assets/icon.png'));
      }
      await tester.pumpAndSettle();
      if (index < 9) {
        expect(requests.keys, everyElement(endsWith('_thumb192.webp')));
      }
    }
    expect(requests.keys.skip(10), paths.take(3));
  });

  testWidgets('current topic is promoted while collage requests are pending', (
    tester,
  ) async {
    final paths = List.generate(10, (i) => 'u/l/images/topic_${i + 1}.jpg');
    final requests = <String>[];
    final priority = ValueNotifier(false);
    addTearDown(priority.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artifactFileProvider.overrideWith((_, path) {
            requests.add(path);
            return Completer<File>().future;
          }),
        ],
        child: ValueListenableBuilder(
          valueListenable: priority,
          builder: (context, cardsOpen, _) => Consumer(
            builder: (context, ref, _) {
              watchTopicImages(
                ref,
                cardsOpen ? paths.reversed : paths,
                startRequests: true,
                prioritizeFirst: cardsOpen,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, paths.take(3).map(thumbnailPathFor));
    priority.value = true;
    await tester.pumpAndSettle();
    expect(requests, [
      ...paths.take(3).map(thumbnailPathFor),
      thumbnailPathFor(paths.last),
    ]);
  });
}
