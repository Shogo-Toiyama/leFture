import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';

/// アナウンスメントのtype別アイコン。Home/Course/LectureViewerで共通利用する。
IconData iconForAnnouncementType(AnnouncementType type) {
  switch (type) {
    case AnnouncementType.todo:
      return Icons.task_alt;
    case AnnouncementType.event:
      return Icons.event;
    case AnnouncementType.hint:
      return Icons.lightbulb_outline;
    case AnnouncementType.info:
      return Icons.info_outline;
    case AnnouncementType.unknown:
      return Icons.star;
  }
}
