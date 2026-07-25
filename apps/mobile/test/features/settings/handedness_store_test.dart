import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/settings/handedness_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsHandednessStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load returns null when nothing stored', () async {
      final store = SharedPrefsHandednessStore();
      expect(await store.load(), isNull);
    });

    for (final h in Handedness.values) {
      test('round-trips $h', () async {
        final store = SharedPrefsHandednessStore();
        await store.save(h);
        expect(await store.load(), h);
      });
    }

    test('load returns null for an unrecognized stored value', () async {
      SharedPreferences.setMockInitialValues({'handedness': 'bogus'});
      expect(await SharedPrefsHandednessStore().load(), isNull);
    });
  });

  group('InMemoryHandednessStore', () {
    test('defaults to the given initial then round-trips', () async {
      final store = InMemoryHandednessStore(Handedness.left);
      expect(await store.load(), Handedness.left);
      await store.save(Handedness.right);
      expect(await store.load(), Handedness.right);
    });

    test('null initial loads null', () async {
      expect(await InMemoryHandednessStore().load(), isNull);
    });
  });
}
