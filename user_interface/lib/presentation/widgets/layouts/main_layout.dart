// lib/presentation/widgets/layouts/main_layout.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  final String currentPath;
  
  const MainLayout({
    required this.child,
    required this.currentPath,
    super.key,
  });
  
  int _calculateSelectedIndex() {
    switch (currentPath) {
      case '/lecture-folder':
        return 0;
      case '/ai-chat':
        return 1;
      case '/':
        return 2;
      case '/goal-tree':
        return 3;
      case '/profile':
        return 4;
      default:
        return 2;
    }
  }
  
  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.lectureFolder);
        break;
      case 1:
        context.go(AppRoutes.aiChat);
        break;
      case 2:
        context.go(AppRoutes.dashboard);
        break;
      case 3:
        context.go(AppRoutes.goalTree);
        break;
      case 4:
        context.go(AppRoutes.profile);
        break;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _calculateSelectedIndex(),
        onTap: (index) => _onItemTapped(context, index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color.fromARGB(255, 255, 235, 191),
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.book_outlined),
            activeIcon: Icon(Icons.book),
            label: 'Notes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_outlined),
            activeIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.flag_outlined),
            activeIcon: Icon(Icons.flag),
            label: 'Goals',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outlined),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _calculateSelectedIndex() == 2
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.recording),
              icon: const Icon(Icons.mic),
              label: const Text('Record'),
            )
          : null,
    );
  }
}