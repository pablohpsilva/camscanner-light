# Ream Final Phase — Settings, dark-by-default, dark verification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a persisted, user-selectable Light/Dark/System theme via a real Settings screen, make dark the default, verify every in-scope screen in dark on both platforms, and finish carried polish.

**Architecture:** A `ThemeModeStore` (shared_preferences impl + in-memory fake) persists the choice; a `ThemeController extends ChangeNotifier` holds the mode and is created in an async `main()` and passed into `CamScannerApp`, which wraps `MaterialApp` in an `AnimatedBuilder` so `themeMode` is reactive. A new `SettingsScreen` (reached by the home gear) drives the controller. Existing screens read `context.ream`, so dark flips automatically; a small status-bar-overlay fix plus per-screen dark tests close the visual gap.

**Tech Stack:** Flutter, Material 3, `shared_preferences` (new), `ReamColors` ThemeExtension, `bdd_widget_test`.

## Global Constraints

- **Pure feature + consolidation only.** No change to OCR, PDF generation, share/print, FeedbackService, DonationConfig, or the drift schema. Only the theme feature and the settings-nav consolidation add/alter behavior.
- **"Ream" is an internal codename — never user-facing.** Display name is **CamScanner-light**. The only user-facing "Ream" string (`donation_screen` header) is fixed to **"Support the app"**.
- **Default theme = Dark** when the store has no value.
- **Only new dependency = `shared_preferences`.** Do NOT add `package_info_plus` (already present but unused here) or any other package. About footer shows no version number.
- **Scoped `git add`** — named paths only, never `-A`/`.` (repo carries a long-lived WIP pile).
- **TDD first**, `flutter analyze` zero-warnings, `dart format lib test` clean, run the **full** `flutter test` suite (not just brief-named files) before reporting DONE. The 2 `opencv_edge_detector_test` host failures are known-environmental — not regressions.
- **Out of scope:** scan feature (`scan_screen`, `id_scan_screen`, `capture_review_screen`, `widgets/crop_overlay.dart`, `widgets/filter_picker_strip.dart`); the two already-dark screens (`page_viewer_screen`, `edit_crop_screen`) and their `Colors.black` scrims; `ocr_pdf_text_layer.dart` `PdfColors.black`.
- All commands run from `apps/mobile/`.

---

### Task 1: `ThemeModeStore` + shared_preferences impl + in-memory fake

**Files:**
- Modify: `pubspec.yaml` (add `shared_preferences`)
- Create: `lib/theme/theme_mode_store.dart`
- Test: `test/theme/theme_mode_store_test.dart`

**Interfaces:**
- Produces: `abstract class ThemeModeStore { Future<ThemeMode?> load(); Future<void> save(ThemeMode mode); }`; `SharedPrefsThemeModeStore` (production, key `theme_mode`); `InMemoryThemeModeStore([ThemeMode? initial])` (tests).

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (alongside the others), add:

```yaml
  shared_preferences: ^2.3.2
```

Run: `flutter pub get`
Expected: resolves, no errors.

- [ ] **Step 2: Write the failing test**

Create `test/theme/theme_mode_store_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/theme_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsThemeModeStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load returns null when nothing stored', () async {
      final store = SharedPrefsThemeModeStore();
      expect(await store.load(), isNull);
    });

    for (final mode in ThemeMode.values) {
      test('round-trips $mode', () async {
        final store = SharedPrefsThemeModeStore();
        await store.save(mode);
        expect(await store.load(), mode);
      });
    }

    test('load returns null for an unrecognized stored value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'bogus'});
      expect(await SharedPrefsThemeModeStore().load(), isNull);
    });
  });

  group('InMemoryThemeModeStore', () {
    test('defaults to the given initial then round-trips', () async {
      final store = InMemoryThemeModeStore(ThemeMode.light);
      expect(await store.load(), ThemeMode.light);
      await store.save(ThemeMode.system);
      expect(await store.load(), ThemeMode.system);
    });

    test('null initial loads null', () async {
      expect(await InMemoryThemeModeStore().load(), isNull);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/theme/theme_mode_store_test.dart`
Expected: FAIL — `theme_mode_store.dart` does not exist.

- [ ] **Step 4: Write the implementation**

Create `lib/theme/theme_mode_store.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen [ThemeMode]. [load] returns null when the user
/// has never chosen — callers default to dark in that case.
abstract class ThemeModeStore {
  Future<ThemeMode?> load();
  Future<void> save(ThemeMode mode);
}

/// Production store backed by shared_preferences (key [_key]).
class SharedPrefsThemeModeStore implements ThemeModeStore {
  static const _key = 'theme_mode';

  @override
  Future<ThemeMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  @override
  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// In-memory fake for host tests (no plugin channel).
class InMemoryThemeModeStore implements ThemeModeStore {
  ThemeMode? _mode;
  InMemoryThemeModeStore([this._mode]);

  @override
  Future<ThemeMode?> load() async => _mode;

  @override
  Future<void> save(ThemeMode mode) async => _mode = mode;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/theme/theme_mode_store_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Analyze, format, commit**

```bash
flutter analyze lib/theme/theme_mode_store.dart test/theme/theme_mode_store_test.dart
dart format lib/theme/theme_mode_store.dart test/theme/theme_mode_store_test.dart
git add pubspec.yaml pubspec.lock lib/theme/theme_mode_store.dart test/theme/theme_mode_store_test.dart
git commit -m "feat(theme): ThemeModeStore + shared_preferences persistence"
```

---

### Task 2: `ThemeController`

**Files:**
- Create: `lib/theme/theme_controller.dart`
- Test: `test/theme/theme_controller_test.dart`

**Interfaces:**
- Consumes: `ThemeModeStore`, `InMemoryThemeModeStore` (Task 1).
- Produces: `class ThemeController extends ChangeNotifier { ThemeController({required ThemeModeStore store, ThemeMode initial = ThemeMode.dark}); ThemeMode get mode; Future<void> setMode(ThemeMode mode); }`.

- [ ] **Step 1: Write the failing test**

Create `test/theme/theme_controller_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/theme_controller_test.dart`
Expected: FAIL — `theme_controller.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/theme/theme_controller.dart`:

```dart
import 'package:flutter/material.dart';

import 'theme_mode_store.dart';

/// Holds the active [ThemeMode] and persists changes through a [ThemeModeStore].
/// Defaults to dark when constructed without a stored value.
class ThemeController extends ChangeNotifier {
  final ThemeModeStore _store;
  ThemeMode _mode;

  ThemeController({required ThemeModeStore store, ThemeMode initial = ThemeMode.dark})
      : _store = store,
        _mode = initial;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _store.save(mode);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/theme_controller_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/theme/theme_controller.dart test/theme/theme_controller_test.dart
dart format lib/theme/theme_controller.dart test/theme/theme_controller_test.dart
git add lib/theme/theme_controller.dart test/theme/theme_controller_test.dart
git commit -m "feat(theme): ThemeController (ChangeNotifier, dark default, persists)"
```

---

### Task 3: Reactive app wiring (`main.dart`, `runCamScannerApp`, `CamScannerApp`, thread controller to `HomeScreen`)

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/features/library/home_screen.dart` (accept + hold a `ThemeController`)
- Test: `test/app/theme_reacts_test.dart` (create)

**Interfaces:**
- Consumes: `ThemeController`, `SharedPrefsThemeModeStore`, `InMemoryThemeModeStore`.
- Produces: `runCamScannerApp({ScanDependencies, LibraryDependencies, FeedbackDependencies, ThemeController? themeController})`; `CamScannerApp({..., required ThemeController themeController})`; `HomeScreen(..., ThemeController? themeController)` — when null, HomeScreen builds an ephemeral `ThemeController(store: InMemoryThemeModeStore())` so existing tests need no change.

- [ ] **Step 1: Write the failing test**

Create `test/app/theme_reacts_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

void main() {
  testWidgets('MaterialApp.themeMode follows the ThemeController', (t) async {
    final controller =
        ThemeController(store: InMemoryThemeModeStore(), initial: ThemeMode.dark);
    await t.pumpWidget(CamScannerApp(themeController: controller));
    await t.pumpAndSettle();

    MaterialApp appOf() => t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appOf().themeMode, ThemeMode.dark);

    await controller.setMode(ThemeMode.light);
    await t.pump();
    expect(appOf().themeMode, ThemeMode.light);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app/theme_reacts_test.dart`
Expected: FAIL — `CamScannerApp` has no `themeController` parameter.

- [ ] **Step 3: Rewrite `lib/main.dart`**

Replace the file with:

```dart
import 'package:flutter/material.dart';

import 'features/feedback/feedback_dependencies.dart';
import 'features/library/home_screen.dart';
import 'features/library/library_dependencies.dart';
import 'features/scan/scan_dependencies.dart';
import 'theme/ream_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_mode_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SharedPrefsThemeModeStore();
  final controller =
      ThemeController(store: store, initial: await store.load() ?? ThemeMode.dark);
  runCamScannerApp(themeController: controller);
}

/// App entrypoint with injectable dependencies, so integration tests can drive
/// deterministic states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
  LibraryDependencies libraryDependencies = const LibraryDependencies(),
  FeedbackDependencies feedbackDependencies = const FeedbackDependencies(),
  ThemeController? themeController,
}) {
  runApp(
    CamScannerApp(
      scanDependencies: scanDependencies,
      libraryDependencies: libraryDependencies,
      feedbackDependencies: feedbackDependencies,
      themeController: themeController ??
          ThemeController(store: SharedPrefsThemeModeStore()),
    ),
  );
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;
  final ThemeController themeController;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'CamScanner-light',
        debugShowCheckedModeBanner: false,
        theme: ReamTheme.light(),
        darkTheme: ReamTheme.dark(),
        themeMode: themeController.mode,
        home: HomeScreen(
          dependencies: scanDependencies,
          libraryDependencies: libraryDependencies,
          feedbackDependencies: feedbackDependencies,
          themeController: themeController,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Thread the controller into `HomeScreen`**

In `lib/features/library/home_screen.dart`, add the import near the others:

```dart
import '../../theme/theme_controller.dart';
import '../../theme/theme_mode_store.dart';
```

Add the field + constructor param to the `HomeScreen` widget class (after `feedbackDependencies`):

```dart
  final ThemeController? themeController;
```

and in the `const HomeScreen({...})` parameter list add:

```dart
    this.themeController,
```

In `_HomeScreenState`, add a resolved controller so the screen always has one:

```dart
  late final ThemeController _themeController =
      widget.themeController ?? ThemeController(store: InMemoryThemeModeStore());
```

(Place this beside the other `_HomeScreenState` fields. It is used by the Settings push in Task 4.)

- [ ] **Step 5: Run the reaction test + the full suite**

Run: `flutter test test/app/theme_reacts_test.dart`
Expected: PASS.
Run: `flutter test`
Expected: green except the 2 known opencv-env failures. (HomeScreen's new optional param must not break existing home tests.)

- [ ] **Step 6: Analyze, format, commit**

```bash
flutter analyze lib/main.dart lib/features/library/home_screen.dart test/app/theme_reacts_test.dart
dart format lib/main.dart lib/features/library/home_screen.dart test/app/theme_reacts_test.dart
git add lib/main.dart lib/features/library/home_screen.dart test/app/theme_reacts_test.dart
git commit -m "feat(theme): reactive MaterialApp driven by ThemeController; thread into HomeScreen"
```

---

### Task 4: `SettingsScreen` + `SettingsDependencies`, replace the home gear popup with a push

**Files:**
- Create: `lib/features/settings/settings_screen.dart`
- Create: `lib/features/settings/settings_dependencies.dart`
- Modify: `lib/features/library/home_screen.dart` (`_buildSettingsMenu` → push)
- Test: `test/features/settings/settings_screen_test.dart` (create)
- Modify: `test/features/library/home_feedback_menu_test.dart` (new nav path)

**Interfaces:**
- Consumes: `ThemeController` (Task 2/3), `FeedbackDependencies`, `FeedbackScreen`, `DonationScreen`, `ReamBackHeader`, `ReamSectionLabel`, `ReamSegmented`, `ReamSegment`.
- Produces: `SettingsScreen({required ThemeController themeController, required FeedbackDependencies feedbackDependencies, bool feedbackAvailable})`; keys `settings-theme-mode`, `settings-feedback`, `settings-support`, `settings-about`; segment keys from `ReamSegmented` are `Key('segment-<ThemeMode.xxx>')`.

- [ ] **Step 1: Write the failing SettingsScreen test**

Create `test/features/settings/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

Widget _host(ThemeController c, {bool feedbackAvailable = true}) => MaterialApp(
      theme: ReamTheme.light(),
      home: SettingsScreen(
        themeController: c,
        feedbackDependencies: const FeedbackDependencies(),
        feedbackAvailable: feedbackAvailable,
      ),
    );

void main() {
  testWidgets('shows the theme selector at the current mode', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore(), initial: ThemeMode.dark);
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-theme-mode')), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('tapping Light sets the controller to light', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore(), initial: ThemeMode.dark);
    await t.pumpWidget(_host(c));
    await t.tap(find.byKey(const Key('segment-ThemeMode.light')));
    await t.pump();
    expect(c.mode, ThemeMode.light);
  });

  testWidgets('feedback row navigates to the feedback screen', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.tap(find.byKey(const Key('settings-feedback')));
    await t.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
  });

  testWidgets('support row navigates to the donation screen', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.tap(find.byKey(const Key('settings-support')));
    await t.pumpAndSettle();
    expect(find.textContaining('no features, benefits, or content'), findsOneWidget);
  });

  testWidgets('feedback row is hidden when feedback is unavailable', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c, feedbackAvailable: false));
    expect(find.byKey(const Key('settings-feedback')), findsNothing);
  });

  testWidgets('about footer shows the app name and no "Ream"', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-about')), findsOneWidget);
    expect(find.textContaining('CamScanner-light'), findsOneWidget);
    expect(find.textContaining('Ream'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — `settings_screen.dart` does not exist.

- [ ] **Step 3: Create `SettingsDependencies`**

Create `lib/features/settings/settings_dependencies.dart`:

```dart
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
```

- [ ] **Step 4: Create `SettingsScreen`**

Create `lib/features/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/ream_colors.dart';
import '../../theme/widgets/ream_back_header.dart';
import '../../theme/widgets/ream_section_label.dart';
import '../../theme/widgets/ream_segmented.dart';
import '../../theme/theme_controller.dart';
import '../donation/donation_screen.dart';
import '../feedback/feedback_dependencies.dart';
import '../feedback/feedback_screen.dart';

/// App settings: theme selection (persisted via [ThemeController]), plus entry
/// points to feedback and support, and an About footer. Renders under the
/// active Ream theme (light or dark).
class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;
  final FeedbackDependencies feedbackDependencies;
  final bool feedbackAvailable;

  const SettingsScreen({
    super.key,
    required this.themeController,
    this.feedbackDependencies = const FeedbackDependencies(),
    this.feedbackAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: 'Settings',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const ReamSectionLabel('Appearance'),
            const SizedBox(height: 10),
            ReamSegmented<ThemeMode>(
              key: const Key('settings-theme-mode'),
              expanded: true,
              value: themeController.mode,
              onChanged: themeController.setMode,
              segments: const [
                ReamSegment(value: ThemeMode.light, label: 'Light'),
                ReamSegment(value: ThemeMode.dark, label: 'Dark'),
                ReamSegment(value: ThemeMode.system, label: 'System'),
              ],
            ),
            const SizedBox(height: 28),
            const ReamSectionLabel('Feedback & support'),
            const SizedBox(height: 10),
            if (feedbackAvailable)
              _NavRow(
                key: const Key('settings-feedback'),
                icon: Icons.chat_bubble_outline,
                label: 'Send feedback',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        FeedbackScreen(dependencies: feedbackDependencies),
                  ),
                ),
              ),
            _NavRow(
              key: const Key('settings-support'),
              icon: Icons.favorite_outline,
              label: 'Support the app',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DonationScreen()),
              ),
            ),
            const SizedBox(height: 36),
            _About(key: const Key('settings-about')),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavRow({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: r.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: r.line),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: r.ink2),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: r.ink,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: r.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Column(
      children: [
        Text(
          'CamScanner-light',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: r.ink2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your scans stay on your device — no account, no cloud.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            color: r.muted,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Replace the home gear popup with a push**

In `lib/features/library/home_screen.dart`, add the import:

```dart
import '../settings/settings_screen.dart';
```

Replace the whole `_buildSettingsMenu` method (currently a `PopupMenuButton`) with:

```dart
  Widget _buildSettingsMenu(BuildContext context) {
    final r = context.ream;
    return GestureDetector(
      key: const Key('home-settings'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            themeController: _themeController,
            feedbackDependencies: widget.feedbackDependencies,
            feedbackAvailable: _feedbackAvailable,
          ),
        ),
      ),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: r.surface,
          shape: BoxShape.circle,
          border: Border.all(color: r.line),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.settings_outlined, size: 18, color: r.ink2),
      ),
    );
  }
```

If removing the popup leaves `FeedbackScreen`/`MaterialPageRoute` imports unused in `home_screen.dart`, remove the now-unused import(s) — `flutter analyze` must stay clean. (The `FeedbackScreen` import is now only used by Settings; delete it from home_screen if analyze flags it.)

- [ ] **Step 6: Update `home_feedback_menu_test.dart` to the new nav path**

Replace `test/features/library/home_feedback_menu_test.dart` body so the two scenarios drive the new flow (gear pushes Settings; feedback reached via `settings-feedback`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_availability.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

class _StubAvailability implements FeedbackAvailability {
  final bool v;
  const _StubAvailability(this.v);
  @override
  Future<bool> isAvailable() async => v;
}

Widget _host(bool healthy) => MaterialApp(
      theme: ReamTheme.light(),
      home: HomeScreen(
        feedbackDependencies: FeedbackDependencies(
          createAvailability: () => _StubAvailability(healthy),
        ),
      ),
    );

void main() {
  testWidgets('settings gear opens settings, and feedback from there when healthy',
      (t) async {
    await t.pumpWidget(_host(true));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-settings')));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await t.tap(find.byKey(const Key('settings-feedback')));
    await t.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
  });

  testWidgets('feedback row is absent in settings when unhealthy', (t) async {
    await t.pumpWidget(_host(false));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-settings')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings-feedback')), findsNothing);
  });
}
```

- [ ] **Step 7: Run the settings + home tests, then the full suite**

Run: `flutter test test/features/settings/settings_screen_test.dart test/features/library/home_feedback_menu_test.dart`
Expected: PASS.
Run: `flutter test`
Expected: green except the 2 known opencv-env failures. Watch for any other test that tapped `home-menu-feedback` (grep first: `grep -rn "home-menu-feedback" test`) — none should remain.

- [ ] **Step 8: Analyze, format, commit**

```bash
flutter analyze lib/features/settings test/features/settings lib/features/library/home_screen.dart test/features/library/home_feedback_menu_test.dart
dart format lib/features/settings test/features/settings lib/features/library/home_screen.dart test/features/library/home_feedback_menu_test.dart
git add lib/features/settings/settings_screen.dart lib/features/settings/settings_dependencies.dart lib/features/library/home_screen.dart test/features/settings/settings_screen_test.dart test/features/library/home_feedback_menu_test.dart
git commit -m "feat(settings): Settings screen with theme selector; home gear pushes it"
```

---

### Task 5: Copy fix — "Support Ream" → "Support the app"

**Files:**
- Modify: `lib/features/donation/donation_screen.dart:56`
- Test: `test/features/donation/donation_screen_test.dart` (adjust if it asserts the old title)

**Interfaces:** none changed (pure copy).

- [ ] **Step 1: Check the current test expectation**

Run: `grep -rn "Support Ream\|Support the app" test lib`
Note whether `donation_screen_test.dart` asserts `'Support Ream'`.

- [ ] **Step 2: Update the header string**

In `lib/features/donation/donation_screen.dart`, change:

```dart
      appBar: ReamBackHeader(
        title: 'Support Ream',
```
to:
```dart
      appBar: ReamBackHeader(
        title: 'Support the app',
```

- [ ] **Step 3: Update any test asserting the old title**

If Step 1 found `find.text('Support Ream')` in `donation_screen_test.dart`, change it to `find.text('Support the app')`. If no test asserts the title, add one:

```dart
  testWidgets('header reads "Support the app" (no codename)', (t) async {
    await t.pumpWidget(const MaterialApp(home: DonationScreen()));
    expect(find.text('Support the app'), findsOneWidget);
    expect(find.textContaining('Ream'), findsNothing);
  });
```
(Match the existing test file's host/imports; reuse its pump helper if present.)

- [ ] **Step 4: Run the donation tests + full suite**

Run: `flutter test test/features/donation/donation_screen_test.dart`
Expected: PASS.
Run: `grep -rn "Support Ream" lib test` → no matches.
Run: `flutter test` → green except the 2 opencv-env failures.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/features/donation/donation_screen.dart test/features/donation/donation_screen_test.dart
dart format lib/features/donation/donation_screen.dart test/features/donation/donation_screen_test.dart
git add lib/features/donation/donation_screen.dart test/features/donation/donation_screen_test.dart
git commit -m "fix(donation): rename header to 'Support the app' (Ream is a codename)"
```

---

### Task 6: Dark verification — status-bar overlay + per-screen dark assertions

**Files:**
- Modify: `lib/theme/widgets/ream_back_header.dart` (brightness-aware status-bar overlay)
- Modify: `lib/features/library/home_screen.dart` (status-bar overlay on the home header)
- Test: `test/theme/dark_screens_test.dart` (create)
- Test: `test/theme/ream_back_header_overlay_test.dart` (create)

**Interfaces:**
- Produces: `ReamBackHeader` now wraps its bar in `AnnotatedRegion<SystemUiOverlayStyle>` derived from `Theme.of(context).brightness` (dark theme → light status-bar icons). No API change.

- [ ] **Step 1: Write the failing overlay test**

Create `test/theme/ream_back_header_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_back_header.dart';

SystemUiOverlayStyle _overlayOf(WidgetTester t) =>
    t.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(ReamBackHeader),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    ).value;

void main() {
  testWidgets('light theme → dark status-bar icons', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: ReamTheme.light(),
      home: const Scaffold(appBar: ReamBackHeader(title: 'X')),
    ));
    expect(_overlayOf(t).statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('dark theme → light status-bar icons', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: ReamTheme.dark(),
      home: const Scaffold(appBar: ReamBackHeader(title: 'X')),
    ));
    expect(_overlayOf(t).statusBarIconBrightness, Brightness.light);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/theme/ream_back_header_overlay_test.dart`
Expected: FAIL — no `AnnotatedRegion` inside `ReamBackHeader`.

- [ ] **Step 3: Make `ReamBackHeader` status-bar aware**

In `lib/theme/widgets/ream_back_header.dart`, add the import:

```dart
import 'package:flutter/services.dart';
```

Wrap the returned `SafeArea` in an `AnnotatedRegion`. Change the `build` return from `return SafeArea(...)` to:

```dart
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: SafeArea(
        // ... existing SafeArea body unchanged ...
      ),
    );
```

(Keep the entire existing `SafeArea(...)` subtree as the `child`.)

- [ ] **Step 4: Run the overlay test**

Run: `flutter test test/theme/ream_back_header_overlay_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the home-header overlay**

In `lib/features/library/home_screen.dart`, add `import 'package:flutter/services.dart';` if absent. Wrap the `_buildHeader` returned `Container(...)` in an `AnnotatedRegion` using the same brightness rule:

```dart
  Widget _buildHeader(BuildContext context) {
    final r = context.ream;
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Container(
        color: r.paper,
        // ... existing Container body (padding + Column) unchanged ...
      ),
    );
  }
```

- [ ] **Step 6: Write per-screen dark assertions**

Create `test/theme/dark_screens_test.dart`. For each in-scope light screen, pump it under `ReamTheme.dark()` and assert its `Scaffold` background is `ReamColors.dark.paper`. Use minimal hosting; where a screen needs deps, use the same fakes those screens' existing tests use (copy the smallest host from the sibling test file).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

Color _scaffoldBg(WidgetTester t) =>
    t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

void main() {
  Widget dark(Widget child) => MaterialApp(theme: ReamTheme.dark(), home: child);

  testWidgets('DonationScreen uses dark paper', (t) async {
    await t.pumpWidget(dark(const DonationScreen()));
    expect(_scaffoldBg(t), ReamColors.dark.paper);
  });

  testWidgets('FeedbackScreen uses dark paper', (t) async {
    await t.pumpWidget(dark(const FeedbackScreen()));
    await t.pumpAndSettle();
    expect(_scaffoldBg(t), ReamColors.dark.paper);
  });

  testWidgets('SettingsScreen uses dark paper', (t) async {
    await t.pumpWidget(dark(SettingsScreen(
      themeController: ThemeController(store: InMemoryThemeModeStore()),
      feedbackDependencies: const FeedbackDependencies(),
    )));
    expect(_scaffoldBg(t), ReamColors.dark.paper);
  });
}
```

(Note: `RecognizedTextScreen`, `PdfPreviewScreen`, and `HomeScreen` need document/page fixtures. If hosting them here is heavy, assert the dark background by reusing their existing test's host and adding one dark-theme variant to that sibling test file instead — implementer chooses the lighter path per screen and notes which screens are covered where. Every in-scope light screen must have at least one dark-bg assertion somewhere.)

- [ ] **Step 7: Run the dark tests + full suite**

Run: `flutter test test/theme/dark_screens_test.dart test/theme/ream_back_header_overlay_test.dart`
Expected: PASS.
Run: `flutter test` → green except the 2 opencv-env failures.

- [ ] **Step 8: Analyze, format, commit**

```bash
flutter analyze lib/theme/widgets/ream_back_header.dart lib/features/library/home_screen.dart test/theme/dark_screens_test.dart test/theme/ream_back_header_overlay_test.dart
dart format lib/theme test/theme lib/features/library/home_screen.dart
git add lib/theme/widgets/ream_back_header.dart lib/features/library/home_screen.dart test/theme/dark_screens_test.dart test/theme/ream_back_header_overlay_test.dart
git commit -m "feat(theme): brightness-aware status bar + per-screen dark verification tests"
```

---

### Task 7: BDD feature — theme settings (`t1_theme_settings`)

**Files:**
- Create: `integration_test/t1_theme_settings.feature`
- Create steps in `test/step/`: `i_open_settings_from_home.dart`, `i_select_the_light_theme.dart`, `the_app_is_shown_in_light_theme.dart`, `i_select_the_dark_theme.dart`, `the_app_is_shown_in_dark_theme.dart`
- Generated (via build_runner): `integration_test/t1_theme_settings_test.dart`

**Interfaces:**
- Consumes: `runCamScannerApp` (defaults to Dark), keys `home-settings`, `settings-theme-mode`, segment keys `segment-ThemeMode.light` / `segment-ThemeMode.dark`.

- [ ] **Step 1: Write the feature file**

Create `integration_test/t1_theme_settings.feature`:

```gherkin
Feature: Choose the app theme

  Scenario: Switch from the default dark theme to light
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I select the light theme
    Then the app is shown in light theme

  Scenario: Switch to dark theme
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I select the dark theme
    Then the app is shown in dark theme
```

- [ ] **Step 2: Write the step implementations**

`test/step/i_open_settings_from_home.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open settings from home
Future<void> iOpenSettingsFromHome(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-settings')));
  await tester.pumpAndSettle();
}
```

`test/step/i_select_the_light_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select the light theme
Future<void> iSelectTheLightTheme(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-ThemeMode.light')));
  await tester.pumpAndSettle();
}
```

`test/step/i_select_the_dark_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select the dark theme
Future<void> iSelectTheDarkTheme(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-ThemeMode.dark')));
  await tester.pumpAndSettle();
}
```

`test/step/the_app_is_shown_in_light_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the app is shown in light theme
Future<void> theAppIsShownInLightTheme(WidgetTester tester) async {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.themeMode, ThemeMode.light);
}
```

`test/step/the_app_is_shown_in_dark_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the app is shown in dark theme
Future<void> theAppIsShownInDarkTheme(WidgetTester tester) async {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.themeMode, ThemeMode.dark);
}
```

- [ ] **Step 3: Generate the test**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: creates `integration_test/t1_theme_settings_test.dart` importing the five steps.

- [ ] **Step 4: Run on host (compile/logic sanity) — note it is an integration test**

Run: `flutter test integration_test/t1_theme_settings_test.dart`
Expected: PASS on host for these two scenarios (no native calls — the store is `shared_preferences`, but the scenarios only tap + assert `themeMode`, and the default launch seeds Dark). If the host run cannot start the integration binding, note it and defer to the device run in Task 9. Do not weaken the scenarios.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze integration_test/t1_theme_settings_test.dart test/step/i_open_settings_from_home.dart test/step/i_select_the_light_theme.dart test/step/i_select_the_dark_theme.dart test/step/the_app_is_shown_in_light_theme.dart test/step/the_app_is_shown_in_dark_theme.dart
dart format integration_test/t1_theme_settings.feature integration_test/t1_theme_settings_test.dart test/step
git add integration_test/t1_theme_settings.feature integration_test/t1_theme_settings_test.dart test/step/i_open_settings_from_home.dart test/step/i_select_the_light_theme.dart test/step/i_select_the_dark_theme.dart test/step/the_app_is_shown_in_light_theme.dart test/step/the_app_is_shown_in_dark_theme.dart
git commit -m "test(settings): BDD feature for theme selection (t1_theme_settings)"
```

---

### Task 8: Deferred-minors polish

**Files (each item independent):**
- Modify: `test/theme/.../ream_colors_test.dart` (widen to 18 tokens, light + dark)
- Resolve: `test/theme/widgets/` vs `test/features/theme/` duplication
- Modify: list-row meta order → "N pages · date"
- Modify: grid placeholder color → `r.muted`
- Modify: `lib/features/feedback/feedback_screen.dart` `_fieldDecoration`
- Modify: `lib/theme/ream_typography.dart`, `lib/theme/ream_theme.dart` private ctors
- Clear the 6 pre-existing `flutter analyze` infos

**Interfaces:** none changed.

- [ ] **Step 1: Baseline analyze**

Run: `flutter analyze` and record the 6 infos.

- [ ] **Step 2: Widen `ream_colors_test`**

Locate it (`grep -rl "ReamColors" test`). Assert all 18 tokens are the exact constants from `lib/theme/ream_colors.dart` for BOTH `ReamColors.light` and `ReamColors.dark`. (Copy the hex values verbatim from that file.) Run the file; PASS.

- [ ] **Step 3: De-duplicate the theme test location**

Decide the canonical folder (prefer `test/theme/`). Move any stragglers from `test/features/theme/` into it (or vice-versa), delete the empty dir, fix imports. Run `flutter test test/theme` (and the moved files) → PASS. No orphaned/duplicated test names.

- [ ] **Step 4: List-row meta order**

In the list-row widget (`grep -rn "pages" lib/features/library/widgets/documents_list_view.dart`), render meta as "N pages · date" to match grid + design. Adjust/added the covering widget test. Run → PASS.

- [ ] **Step 5: Grid placeholder → `r.muted`**

In the grid placeholder (`grep -rn "placeholder\|Colors\." lib/features/library/widgets/documents_grid_view.dart`), swap the placeholder color to `context.ream.muted`. Adjust the covering test if it asserts the old color. Run → PASS.

- [ ] **Step 6: `_fieldDecoration` border**

In `feedback_screen.dart`, make `border` and `enabledBorder` intentionally distinct (e.g. `enabledBorder` uses `r.line`, `border` a subtler/neutral fallback), OR add a one-line comment documenting why identical is intended. Keep the feedback tests green.

- [ ] **Step 7: Private constructors**

Add `ReamTypography._();` and `ReamTheme._();` private constructors (these are static-only utility classes). Run their tests + `flutter analyze` → clean.

- [ ] **Step 8: Clear remaining analyze infos; full suite**

Address the remaining infos from Step 1 (unused imports, `prefer_const`, etc.).
Run: `flutter analyze` → **zero** issues.
Run: `flutter test` → green except the 2 opencv-env failures.
Run: `dart format lib test` → clean.

- [ ] **Step 9: Commit**

```bash
git add <the exact files touched in Steps 2-7>
git commit -m "chore(theme): clear carried deferred-minors polish (18-token test, dedup, meta order, analyze infos)"
```

---

### Task 9: Whole-branch review + combined device regression (dark + light, both platforms)

**Files:** none (verification task).

- [ ] **Step 1: Full host suite + analyze + format**

Run: `flutter test` → green except the 2 opencv-env failures.
Run: `flutter analyze` → zero issues.
Run: `dart format --output=none --set-exit-if-changed lib test` → clean.

- [ ] **Step 2: Device regression — Android emulator**

Boot `Medium_Phone_API_35` (or the RZCY51D0T1K device). Run the theme BDD + the four Phase-2 regression features:

```bash
flutter test integration_test/t1_theme_settings_test.dart integration_test/e1_crop_test.dart integration_test/o4_recognized_text_test.dart integration_test/c2_pdf_preview_test.dart integration_test/s1_donation_banner_test.dart -d <android-id>
```
Expected: all PASS. This exercises the default **dark** launch (dark verification evidence).

- [ ] **Step 3: Device regression — iOS simulator**

Same command with `-d 41E4AD9A-8F40-4170-9732-BDFC4E8BECBB` (iPad Pro 13" iOS 18.3). Expected: all PASS.

- [ ] **Step 4: Eyeball light + dark**

Install and manually confirm each in-scope screen (home, OCR, feedback, donation, PDF viewer, settings) renders correctly in BOTH light and dark — toggle via Settings. Note any visual defect as a finding; fix trivial ones, escalate anything structural.

- [ ] **Step 5: Finalize**

Update `.superpowers/sdd/progress.md`. Hand off to `superpowers:finishing-a-development-branch` (merge to master local + remote).

---

## Self-Review

- **Spec coverage:** store+persistence (T1), controller (T2), reactive app + default-dark (T3), Settings screen + gear consolidation (T4), copy fix (T5), dark verification (T6), BDD (T7), deferred-minors (T8), regression+merge (T9). All spec sections mapped.
- **Type consistency:** `ThemeController({required ThemeModeStore store, ThemeMode initial})`, `setMode`, `SettingsScreen({required ThemeController themeController, FeedbackDependencies, bool feedbackAvailable})`, `ReamSegmented<ThemeMode>` segment keys `Key('segment-ThemeMode.light')` — used consistently in T4 test and T7 steps. `SharedPrefsThemeModeStore.new` tear-off matches the `ThemeModeStoreFactory` typedef.
- **No placeholders:** every code step carries real code; T8's many-small-edits steps name the exact file + grep to locate the line and the concrete change.
- **Known risk noted:** T7 Step 4 flags that integration-binding tests may not run headless on host; the authoritative run is the device pass in T9.
