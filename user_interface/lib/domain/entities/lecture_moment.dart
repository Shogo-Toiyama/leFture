class LectureMoment {
  const LectureMoment({
    required this.id,
    required this.lectureId,
    required this.momentType,
    this.noteText,
    required this.timestampSec,
    required this.createdAt,
  });

  final String id;
  final String lectureId;
  // fun / difficult / revisit / note
  final String momentType;
  final String? noteText;
  final int timestampSec;
  final DateTime createdAt;
}
