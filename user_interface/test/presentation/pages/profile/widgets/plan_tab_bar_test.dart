import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/presentation/pages/profile/widgets/plan_tab_bar.dart';

void main() {
  testWidgets('PlanTabBar renders tabs with bottom labels and handles selection', (tester) async {
    final plans = [
      PlanOption.fromJson({'id': 'p1', 'name': 'Free', 'claim_mode': 'self_serve'}),
      PlanOption.fromJson({'id': 'p2', 'name': 'Lite', 'store_product_id': 'com.lefture.app.sub.starter'}),
      PlanOption.fromJson({'id': 'p3', 'name': 'Core', 'store_product_id': 'com.lefture.app.sub.standard'}),
      PlanOption.fromJson({'id': 'p4', 'name': 'Max', 'store_product_id': 'com.lefture.app.sub.premium'}),
    ];

    var selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return PlanTabBar(
                plans: plans,
                selectedIndex: selectedIndex,
                onSelected: (i) => setState(() => selectedIndex = i),
              );
            },
          ),
        ),
      ),
    );

    // プラン名が描画されていることを確認
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Lite'), findsWidgets);
    expect(find.text('Core'), findsWidgets);
    expect(find.text('Max'), findsWidgets);

    // Lite タブをタップ
    await tester.tap(find.text('Lite').first);
    await tester.pumpAndSettle();
    expect(selectedIndex, 1);
  });
}
