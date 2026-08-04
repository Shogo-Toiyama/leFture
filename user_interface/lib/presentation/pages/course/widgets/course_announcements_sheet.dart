import 'package:flutter/material.dart';
import 'package:lefture/presentation/widgets/announcements_sheet.dart';

/// コース内の全レクチャーを横断した、未完了のアナウンスメント一覧ボトムシート。
/// 共通コンポーネント [AnnouncementsSheet] を呼び出します。
class CourseAnnouncementsSheet extends StatelessWidget {
  const CourseAnnouncementsSheet({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context) {
    return AnnouncementsSheet(courseId: courseId);
  }
}

