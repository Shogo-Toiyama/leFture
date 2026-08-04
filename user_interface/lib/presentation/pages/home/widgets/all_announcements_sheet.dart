import 'package:flutter/material.dart';
import 'package:lefture/presentation/widgets/announcements_sheet.dart';

/// 全コース横断の未完了アナウンスメント一覧シート (HomeのAnnouncementBarから開く)。
/// 共通コンポーネント [AnnouncementsSheet] を呼び出します。
class AllAnnouncementsSheet extends StatelessWidget {
  const AllAnnouncementsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnouncementsSheet();
  }
}

