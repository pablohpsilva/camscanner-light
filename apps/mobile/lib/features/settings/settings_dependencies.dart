import '../../theme/theme_mode_store.dart';

typedef ThemeModeStoreFactory = ThemeModeStore Function();

/// Composition root for the Settings feature. Production uses shared_preferences;
/// tests inject an in-memory store.
class SettingsDependencies {
  final ThemeModeStoreFactory createThemeModeStore;
  const SettingsDependencies({
    this.createThemeModeStore = SharedPrefsThemeModeStore.new,
  });
}
