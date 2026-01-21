import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_folder/navigator/notes_tab.dart';
import 'package:lecture_companion_ui/presentation/widgets/layouts/recording_mini_player.dart';

import 'package:lecture_companion_ui/presentation/pages/dashboard/dashboard_page.dart';
import 'package:lecture_companion_ui/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lecture_companion_ui/presentation/pages/goal_tree/goal_tree_page.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/profile_page.dart';


class MainLayout extends HookConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = useState(2); // 初期値: Dashboard (2)

    final pages = useMemoized(() => [
      const NotesTab(), // 0: Notes
      const AiChatPage(),                      // 1: Chat
      const DashboardPage(),                   // 2: Dashboard
      const GoalTreePage(),                    // 3: Goals
      const ProfilePage(),                     // 4: Profile
    ]);

    final showMiniPlayer = true;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: selectedIndex.value,
            children: pages,
          ),
          if (showMiniPlayer)
             const RecordingMiniPlayer(isVisible: true),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex.value,
        onTap: (index) => selectedIndex.value = index, // GoRouterを使わずState更新のみ
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color.fromARGB(255, 255, 235, 191),
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book_outlined), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_outlined), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.flag_outlined), label: 'Goals'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outlined), label: 'Profile'),
        ],
      ),
    );
  }
}