import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/domain/plan_features.dart' as plan_features;
import 'package:lefture/presentation/pages/profile/widgets/plan_theme.dart';
import 'package:lefture/presentation/widgets/upgrade_required_dialog.dart';

void main() {
  testWidgets('showUpgradeRequiredDialog passes targetTierLevel to AppRoutes.plans', (tester) async {
    Object? pushedExtra;
    String? pushedLocation;

    final router = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(
          path: '/test',
          builder: (context, state) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showUpgradeRequiredDialog(
                context: context,
                requiredTierColor: planThemeColor(plan_features.tierCore),
                targetTierLevel: plan_features.tierCore,
                title: 'Core Required',
                message: 'This feature requires Core plan.',
                viewPlansLabel: 'View Plans',
                cancelLabel: 'Cancel',
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.plans,
          builder: (context, state) {
            pushedExtra = state.extra;
            pushedLocation = state.uri.toString();
            return const Scaffold(body: Text('Plans Page'));
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // ボタンを押してダイアログを表示
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Core Required'), findsOneWidget);
    expect(find.text('View Plans'), findsOneWidget);

    // View Plans をタップして画面遷移
    await tester.tap(find.text('View Plans'));
    await tester.pumpAndSettle();

    expect(pushedLocation, AppRoutes.plans);
    expect(pushedExtra, plan_features.tierCore);
  });

  testWidgets('showUpgradeRequiredDialog infers targetTierLevel from color when null', (tester) async {
    Object? pushedExtra;

    final router = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(
          path: '/test',
          builder: (context, state) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showUpgradeRequiredDialog(
                context: context,
                requiredTierColor: planThemeColor(plan_features.tierLite),
                // targetTierLevel は未指定(フォールバックの動作検証)
                title: 'Lite Required',
                message: 'This feature requires Lite plan.',
                viewPlansLabel: 'View Plans',
                cancelLabel: 'Cancel',
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.plans,
          builder: (context, state) {
            pushedExtra = state.extra;
            return const Scaffold(body: Text('Plans Page'));
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Plans'));
    await tester.pumpAndSettle();

    expect(pushedExtra, plan_features.tierLite);
  });
}
