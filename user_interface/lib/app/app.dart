import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/router.dart';
import 'package:lecture_companion_ui/presentation/themes/app_theme.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'leFture',
      theme: AppTheme.light,
      // darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}