import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/settings/handedness_controller.dart';
import 'package:mobile/features/settings/handedness_store.dart';

void main() {
  test('defaults to the given initial (right by default)', () {
    final c = HandednessController(store: InMemoryHandednessStore());
    expect(c.value, Handedness.right);
  });

  test('honors an explicit initial', () {
    final c = HandednessController(
      store: InMemoryHandednessStore(),
      initial: Handedness.left,
    );
    expect(c.value, Handedness.left);
  });

  test('setHandedness updates value, notifies, and persists', () async {
    final store = InMemoryHandednessStore();
    final c = HandednessController(store: store, initial: Handedness.right);
    var notified = 0;
    c.addListener(() => notified++);

    await c.setHandedness(Handedness.left);

    expect(c.value, Handedness.left);
    expect(notified, 1);
    expect(await store.load(), Handedness.left);
  });

  test(
    'setHandedness to the current value is a no-op (no notify, no save)',
    () async {
      final store = InMemoryHandednessStore(Handedness.right);
      final c = HandednessController(store: store, initial: Handedness.right);
      var notified = 0;
      c.addListener(() => notified++);

      await c.setHandedness(Handedness.right);

      expect(notified, 0);
      expect(await store.load(), Handedness.right);
    },
  );
}
