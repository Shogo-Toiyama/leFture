import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/review_cards/review_cards_viewer_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _UnusedDatabase implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _withViewer(
  WidgetTester tester,
  Future<void> Function() exercise,
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

  final date = DateTime(2026);
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(_UnusedDatabase()),
      lectureProvider('lecture').overrideWith((_) => Stream.value(null)),
      courseListProvider.overrideWith((_) => Stream.value([])),
      lectureTopicsProvider('lecture').overrideWith(
        (_) => Stream.value([
          LectureTopic(
            id: 'topic',
            index: 1,
            topicTitle: 'Topic',
            createdAt: date,
            updatedAt: date,
          ),
        ]),
      ),
      reviewCardsProvider('lecture').overrideWith(
        (_) => Stream.value([
          for (final (id, type) in [('first', 'hook'), ('second', 'core_why')])
            ReviewCard(
              id: id,
              topicNumber: 1,
              cardType: type,
              title: id,
              createdAt: date,
              cardContent: [
                for (var i = 0; i < 30; i++)
                  ReviewCardBlock(type: 'paragraph', text: 'Paragraph $i'),
              ],
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
        home: ReviewCardsViewerPage(lectureId: 'lecture', initialIndex: 1),
      ),
    ),
  );
  try {
    await tester.pumpAndSettle();
    await exercise();
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }
}

Finder _cardScroll(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Scrollable));

ScrollPosition _cardPosition(WidgetTester tester, String title) =>
    tester.state<ScrollableState>(_cardScroll(title)).position;

Future<TestGesture> _startSwipe(
  WidgetTester tester,
  String title,
  double dx,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_cardScroll(title)),
  );
  final recognitionDelta = dx.sign * 24;
  await gesture.moveBy(Offset(recognitionDelta, 0));
  await gesture.moveBy(Offset(dx - recognitionDelta, 0));
  await tester.pump();
  return gesture;
}

void main() {
  final mobilePlatforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  testWidgets('Each card keeps its offset through swipe and cancellation', (
    tester,
  ) async {
    await _withViewer(tester, () async {
      final center = tester.getCenter(_cardScroll('first'));
      await tester.dragFrom(center, const Offset(0, -220));
      await tester.pumpAndSettle();
      final firstOffset = _cardPosition(tester, 'first').pixels;
      expect(firstOffset, greaterThan(0));

      // Hold the pointer down to inspect the very first rendered drag frame.
      var gesture = await _startSwipe(tester, 'first', -45);
      expect(find.text('2 / 3'), findsOneWidget);
      final duringSwipe = _cardPosition(tester, 'first').pixels;
      final incoming = _cardPosition(tester, 'second').pixels;
      await gesture.cancel();
      await tester.pumpAndSettle();
      final cancelled = _cardPosition(tester, 'first').pixels;
      print(
        'Swipe: $firstOffset -> $duringSwipe -> $cancelled, incoming $incoming',
      );
      expect(duringSwipe, firstOffset);
      expect(cancelled, firstOffset);
      expect(incoming, 0);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(_cardScroll('second'), findsNothing);

      gesture = await _startSwipe(tester, 'first', -45);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(_cardPosition(tester, 'first').pixels, firstOffset);

      gesture = await _startSwipe(tester, 'first', -320);
      expect(_cardPosition(tester, 'first').pixels, firstOffset);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(_cardPosition(tester, 'second').pixels, 0);

      await tester.dragFrom(
        tester.getCenter(_cardScroll('second')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      final secondOffset = _cardPosition(tester, 'second').pixels;
      expect(secondOffset, greaterThan(0));
      expect(secondOffset, isNot(firstOffset));

      gesture = await _startSwipe(tester, 'second', 320);
      expect(_cardPosition(tester, 'second').pixels, secondOffset);
      expect(_cardPosition(tester, 'first').pixels, firstOffset);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(_cardPosition(tester, 'first').pixels, firstOffset);

      gesture = await _startSwipe(tester, 'first', -320);
      expect(_cardPosition(tester, 'second').pixels, secondOffset);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(_cardPosition(tester, 'second').pixels, secondOffset);
      print(
        'Independent settled offsets: first $firstOffset, second $secondOffset',
      );
    });
  }, variant: mobilePlatforms);

  testWidgets(
    'Progress bar navigation preserves an in-flight vertical offset',
    (tester) async {
      await _withViewer(tester, () async {
        final bar = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is GestureDetector &&
                widget.onTapUp != null &&
                widget.onHorizontalDragStart != null,
          ),
        );

        await tester.flingFrom(
          tester.getCenter(_cardScroll('first')),
          const Offset(0, -100),
          1200,
        );
        await tester.pump();
        final position = _cardPosition(tester, 'first');
        final atRelease = position.pixels;
        await tester.pump(const Duration(milliseconds: 32));
        expect(position.pixels, greaterThan(atRelease));
        expect(position.isScrollingNotifier.value, isTrue);
        expect(position.outOfRange, isFalse);
        final before = position.pixels;
        expect(before, greaterThan(0));

        // Tap outside the scroll view while its momentum is still active.
        await tester.tapAt(Offset(bar.left + bar.width * .83, bar.center.dy));
        await tester.pump();
        final during = _cardPosition(tester, 'first').pixels;
        print('Progress bar during vertical momentum: $before -> $during');
        expect(during, before);
        await tester.pumpAndSettle();
        expect(find.text('3 / 3'), findsOneWidget);
        expect(_cardPosition(tester, 'second').pixels, 0);
      });
    },
    variant: mobilePlatforms,
  );
}
