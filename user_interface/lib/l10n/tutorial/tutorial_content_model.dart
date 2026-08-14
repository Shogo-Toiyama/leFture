// lib/l10n/tutorial/tutorial_content_model.dart

class TutorialContent {
  const TutorialContent({
    required this.courseTitle,
    required this.courseSummary,
    required this.lectureTitle,
    required this.lectureSummary,
    required this.funFact,
    required this.announcements,
    required this.keywords,
    required this.topics,
  });

  final String courseTitle;
  final String courseSummary;
  final String lectureTitle;
  final String lectureSummary;
  final TutorialFunFact funFact;
  final List<TutorialAnnouncement> announcements;
  final List<TutorialKeyword> keywords;
  final List<TutorialTopic> topics;
}

class TutorialTopic {
  const TutorialTopic({
    required this.topicIndex,
    required this.title,
    required this.summary,
    required this.deepNoteMarkdown,
    required this.reviewCards,
  });

  final int topicIndex;
  final String title;
  final String summary;
  final String deepNoteMarkdown;
  final List<TutorialReviewCard> reviewCards;
}

class TutorialReviewCard {
  const TutorialReviewCard({
    required this.cardType,
    required this.title,
    required this.heroEmoji,
    required this.contentBlocks,
  });

  final String cardType;
  final String title;
  final String heroEmoji;
  final List<Map<String, dynamic>> contentBlocks;
}

class TutorialFunFact {
  const TutorialFunFact({
    required this.title,
    required this.hook,
    required this.body,
    this.sources = const [],
  });

  final String title;
  final String hook;
  final String body;
  final List<String> sources;
}

class TutorialAnnouncement {
  const TutorialAnnouncement({
    required this.id,
    required this.type,
    required this.content,
  });

  final String id;
  final String type; // 'TODO' | 'INFO'
  final String content;
}

class TutorialKeyword {
  const TutorialKeyword({
    required this.keyword,
    this.definition,
    required this.topicNumber,
  });

  final String keyword;
  final String? definition;
  final int topicNumber;
}
