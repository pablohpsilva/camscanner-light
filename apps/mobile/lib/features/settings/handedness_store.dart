import 'package:shared_preferences/shared_preferences.dart';

/// Which hand the primary Scan action should sit under in the home action row.
enum Handedness { left, right }

/// Persists the user's chosen [Handedness]. [load] returns null when the user
/// has never chosen — callers default to right in that case.
abstract class HandednessStore {
  Future<Handedness?> load();
  Future<void> save(Handedness handedness);
}

/// Production store backed by shared_preferences (key [_key]).
class SharedPrefsHandednessStore implements HandednessStore {
  static const _key = 'handedness';

  @override
  Future<Handedness?> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'left':
        return Handedness.left;
      case 'right':
        return Handedness.right;
      default:
        return null;
    }
  }

  @override
  Future<void> save(Handedness handedness) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, handedness.name);
  }
}

/// In-memory fake for host tests (no plugin channel).
class InMemoryHandednessStore implements HandednessStore {
  Handedness? _value;
  InMemoryHandednessStore([this._value]);

  @override
  Future<Handedness?> load() async => _value;

  @override
  Future<void> save(Handedness handedness) async => _value = handedness;
}
