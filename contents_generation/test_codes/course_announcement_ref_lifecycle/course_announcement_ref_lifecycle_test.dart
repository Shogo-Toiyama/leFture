import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_announcement_provider.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';

void main() {
  const courseId = 'test-course';
  final lectureList = lectureListStreamProvider(courseId);
  final refOwner = Provider.autoDispose<Ref>((ref) => ref);
  final providers = <String, Stream<Object?> Function(Ref, String)>{
    'latest': latestAnnouncementForCourse,
    'active': activeAnnouncementsForCourse,
    'all': allAnnouncementsForCourse,
  };

  for (final entry in providers.entries) {
    testWidgets('${entry.key} stops after its Ref is disposed', (tester) async {
      final lectureUpdates = StreamController<List<Lecture>>();
      final container = ProviderContainer(
        overrides: [
          lectureList.overrideWith((ref) => lectureUpdates.stream),
          announcementRepositoryDriftProvider.overrideWith((ref) {
            throw StateError('Disposed work must not open the repository');
          }),
        ],
      );
      final lectureSubscription = container.listen(lectureList, (_, _) {});
      final ref = container.listen(refOwner, (_, _) {}).read();
      addTearDown(() async {
        container.dispose();
        await lectureUpdates.close();
      });

      final values = <Object?>[];
      final errors = <Object>[];
      var finished = false;
      final subscription = entry
          .value(ref, courseId)
          .listen(
            values.add,
            onError: errors.add,
            onDone: () => finished = true,
          );
      addTearDown(subscription.cancel);
      await tester.pump();

      container.invalidate(refOwner);
      container.read(refOwner);
      final disposedWhileWaiting = !ref.mounted && !finished;

      // Keep the dependency alive so the pending Future resolves after disposal.
      lectureUpdates.add(const []);
      await tester.pump();
      lectureSubscription.close();

      expect(disposedWhileWaiting, isTrue);
      expect(finished, isTrue);
      expect(errors, isEmpty);
      expect(values, isEmpty);
    });
  }

  testWidgets('mounted providers still publish their first values', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        lectureList.overrideWith((ref) => Stream.value(const [])),
        announcementRepositoryDriftProvider.overrideWithValue(
          _EmptyAnnouncementRepository(),
        ),
      ],
    );
    try {
      final latest = container.listen(
        latestAnnouncementForCourseProvider(courseId),
        (_, _) {},
      );
      final active = container.listen(
        activeAnnouncementsForCourseProvider(courseId),
        (_, _) {},
      );
      final all = container.listen(
        allAnnouncementsForCourseProvider(courseId),
        (_, _) {},
      );
      await tester.pump();

      expect(latest.read(), const AsyncData<Announcement?>(null));
      expect(active.read().requireValue, isEmpty);
      expect(all.read().requireValue, isEmpty);
    } finally {
      container.dispose();
    }
  });
}

class _EmptyAnnouncementRepository implements AnnouncementRepositoryDrift {
  @override
  Stream<List<Announcement>> watchActiveAnnouncementsForLectureIds(
    List<String> lectureIds, {
    DateTime? completedAfter,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
