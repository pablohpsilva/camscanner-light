import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

void main() {
  testWidgets('MaterialApp.themeMode follows the ThemeController', (t) async {
    final controller = ThemeController(
      store: InMemoryThemeModeStore(),
      initial: ThemeMode.dark,
    );
    await t.pumpWidget(CamScannerApp(themeController: controller));
    await t.pumpAndSettle();

    MaterialApp appOf() => t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appOf().themeMode, ThemeMode.dark);

    await controller.setMode(ThemeMode.light);
    await t.pump();
    expect(appOf().themeMode, ThemeMode.light);
  });
}
