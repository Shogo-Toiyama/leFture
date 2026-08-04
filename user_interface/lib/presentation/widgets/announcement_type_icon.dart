import 'package:flutter/material.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

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

/// アナウンスメントのtype別カラー。
Color colorForAnnouncementType(AnnouncementType type) {
  switch (type) {
    case AnnouncementType.todo:
      return Colors.green.shade400;
    case AnnouncementType.event:
      return Colors.blue.shade400;
    case AnnouncementType.info:
      return Colors.purple.shade300;
    case AnnouncementType.hint:
      return Colors.amber.shade400;
    case AnnouncementType.unknown:
      return AppColors.starGold;
  }
}

