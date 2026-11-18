import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture/lecture_state_providers.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/application/recording/recording_state.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/lecture_tile.dart';

class _IdleRecorder extends RecordingController {
  @override
  RecordingState build() => RecordingState.idle();
}

void main() {
  testWidgets('lecture tiles use the assigned course icon as image fallback', (
    tester,
  ) async {
    final date = DateTime(2026);
    final lectures = [
      for (final (id, courseId) in [
        ('with-icon', 'science'),
        ('default-icon', 'default'),
        ('unassigned', null),
        ('with-image', 'science'),
      ])
        Lecture(
          id: id,
          userId: 'user',
          courseId: courseId,
          title: id,
          sortOrder: 0,
          lectureDatetime: date,
          createdAt: date,
          updatedAt: date,
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courseListProvider.overrideWith(
            (_) => Stream.value([
              Course(
                id: 'science',
                userId: 'user',
                metadata: const {'icon': 'science'},
                createdAt: date,
                updatedAt: date,
              ),
              Course(
                id: 'default',
                userId: 'user',
                createdAt: date,
                updatedAt: date,
              ),
            ]),
          ),
          recordingControllerProvider.overrideWith(_IdleRecorder.new),
          for (final lecture in lectures) ...[
            firstTopicImagePathProvider(lecture.id).overrideWith(
              (_) => Stream.value(
                lecture.id == 'with-image' ? 'assets/images/tutorial/topic_1.jpg' : null,
              ),
            ),
            lectureStateProvider(lecture.id)
                .overrideWith((_) => Stream.value(LectureUIState.notStarted)),
          ],
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                for (final lecture in lectures)
                  LectureTile(
                    key: ValueKey(lecture.id),
                    lecture: lecture,
                    showCourseLabel: lecture.id != 'with-icon',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder tileIcon(String id, IconData icon) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byIcon(icon),
    );
    expect(tileIcon('unassigned', Icons.description_outlined), findsOneWidget);
    expect(tileIcon('with-image', Icons.description_outlined), findsNothing);
    expect(tileIcon('with-image', Icons.science_outlined), findsNothing);
    expect(tileIcon('with-icon', Icons.science_outlined), findsOneWidget);
    expect(tileIcon('default-icon', Icons.school_outlined), findsOneWidget);
  });
}
