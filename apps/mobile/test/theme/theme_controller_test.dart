import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

void main() {
  test('defaults to the given initial (dark by default)', () {
    final c = ThemeController(store: InMemoryThemeModeStore());
    expect(c.mode, ThemeMode.dark);
  });

  test('honors an explicit initial', () {
    final c = ThemeController(
      store: InMemoryThemeModeStore(),
      initial: ThemeMode.light,
    );
    expect(c.mode, ThemeMode.light);
  });

  test('setMode updates mode, notifies, and persists', () async {
    final store = InMemoryThemeModeStore();
    final c = ThemeController(store: store, initial: ThemeMode.dark);
    var notified = 0;
    c.addListener(() => notified++);

    await c.setMode(ThemeMode.light);

    expect(c.mode, ThemeMode.light);
    expect(notified, 1);
    expect(await store.load(), ThemeMode.light);
  });

  test('setMode to the current mode is a no-op (no notify, no save)', () async {
    final store = InMemoryThemeModeStore(ThemeMode.dark);
    final c = ThemeController(store: store, initial: ThemeMode.dark);
    var notified = 0;
    c.addListener(() => notified++);

    await c.setMode(ThemeMode.dark);

    expect(notified, 0);
    // store still holds the seeded value; unchanged.
    expect(await store.load(), ThemeMode.dark);
  });
}
