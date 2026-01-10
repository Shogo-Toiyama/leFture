// lib/presentation/widgets/layouts/main_layout.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';

final navLockProvider = NotifierProvider<NavLock, bool>(NavLock.new);
class NavLock extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() => state = true;
  void unlock() => state = false;
}

class MainLayout extends ConsumerWidget {
  final Widget child;
  final String currentPath;
  
  const MainLayout({
    required this.child,
    required this.currentPath,
    super.key,
  });
  
  int _calculateSelectedIndex() {
    if (currentPath.startsWith(AppRoutes.dashboard)) return 2;
    if (currentPath.startsWith(AppRoutes.notesEntry)) return 0;
    if (currentPath.startsWith(AppRoutes.aiChat)) return 1;
    if (currentPath.startsWith(AppRoutes.goalTree)) return 3;
    if (currentPath.startsWith(AppRoutes.profile)) return 4;
    return 0;
  }
  
  void _onItemTapped(BuildContext context, WidgetRef ref, int index) {
    final locked = ref.watch(navLockProvider);
    if (locked) return;
    ref.read(navLockProvider.notifier).unlock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(navLockProvider)) {
        ref.read(navLockProvider.notifier).lock();
      }
    });
    switch (index) {
      case 0:
        context.go(AppRoutes.notesEntry);
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
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(navLockProvider);
    return Scaffold(
      body: child,
      bottomNavigationBar: AbsorbPointer(
        absorbing: locked,
        child: BottomNavigationBar(
          currentIndex: _calculateSelectedIndex(),
          onTap: (index) => _onItemTapped(context, ref, index),
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