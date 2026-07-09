# Feedback App Feature Implementation Plan (Flutter)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app "Send feedback" flow (overflow menu → form → submit) that proves app authenticity (attestation primary, Turnstile fallback), collects non-personal diagnostics, and posts to the Feedback Worker, which creates the GitHub issue.

**Architecture:** A new `lib/features/feedback/` feature with a const-constructible `FeedbackDependencies` composition root (matching `LibraryDependencies`/`ScanDependencies`). `FeedbackService` orchestrates: fetch a one-time challenge from the Worker → obtain an attestation token over it (fallback: Turnstile token from the UI widget) → collect diagnostics → POST to the Worker → map the response to a `FeedbackResult`. Attestation/Turnstile/HTTP/diagnostics all sit behind injectable interfaces so host tests use fakes and device tests exercise the real natives.

**Tech Stack:** Flutter, `http`, `package_info_plus`, `device_info_plus`, `uuid`, `cloudflare_turnstile` (WebView-hosted), platform-channel/plugin attestation (App Attest / Play Integrity), `bdd_widget_test` for the device BDD test.

## Global Constraints

- Depends on the **Feedback Worker** (separate plan) being deployed to staging; its URL + Turnstile **site key** come in via `--dart-define` (safe to ship).
- DI: thread a new `FeedbackDependencies` through `runCamScannerApp` → `CamScannerApp` → `HomeScreen`, mirroring existing deps. Never `new` a collaborator inline.
- App is **not** localized — English strings, matching the rest of the app.
- TDD: failing test first (red) → minimal code (green). BDD: a `.feature` under `integration_test/` with steps shared in `test/step/` (per `build.yaml`).
- Both platforms: native-dependent behavior (attestation, package/device info, TLS) proven on a **real Android AND real iOS device** against the **staging** Worker. Any platform that can't run a path is named as an explicit gap.
- Categories (exact, must match Worker enum): `bug`, `idea`, `question`.
- Message max length: 4000 chars. Email optional; if present must look like an email.
- Email field shows the inline warning verbatim: **"Optional. This will be publicly visible on GitHub."**
- Diagnostics contain NO document data — only app version/build, OS, device model, locale.

---

## Prerequisites

- [ ] **P1** — From the Worker plan: `STAGING_WORKER_URL` and `TURNSTILE_SITE_KEY`. Production URL/key come later; use staging throughout development.
- [ ] **P2** — Decide the attestation delivery: evaluate `app_attest` (iOS) and a Play Integrity plugin for Android; if none is suitable, a thin platform channel (Task 3 shows both the interface and a platform-channel skeleton). This choice is finalized in Task 3.

---

## Task 1: Dependencies + FeedbackConfig

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Create: `apps/mobile/lib/features/feedback/feedback_config.dart`
- Test: `apps/mobile/test/features/feedback/feedback_config_test.dart`

**Interfaces:**
- Produces: `class FeedbackConfig { final String workerUrl; final String turnstileSiteKey; const FeedbackConfig({...}); factory FeedbackConfig.fromEnvironment(); bool get isConfigured; }`

- [ ] **Step 1: Add dependencies** to `apps/mobile/pubspec.yaml` under `dependencies:`:
```yaml
  http: ^1.2.2
  package_info_plus: ^8.0.2
  device_info_plus: ^10.1.2
  uuid: ^4.5.1
  cloudflare_turnstile: ^2.2.0
```
Run: `cd apps/mobile && flutter pub get`
Expected: resolves without conflict.

- [ ] **Step 2: Write the failing test**

`apps/mobile/test/features/feedback/feedback_config_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_config.dart';

void main() {
  test('isConfigured is false when the worker url is empty', () {
    const c = FeedbackConfig(workerUrl: '', turnstileSiteKey: 'k');
    expect(c.isConfigured, isFalse);
  });
  test('isConfigured is true when both values are present', () {
    const c = FeedbackConfig(workerUrl: 'https://w', turnstileSiteKey: 'k');
    expect(c.isConfigured, isTrue);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_config_test.dart`
Expected: FAIL — `feedback_config.dart` missing.

- [ ] **Step 4: Implementation**

`apps/mobile/lib/features/feedback/feedback_config.dart`:
```dart
/// Ship-safe configuration for the feedback feature. Both values are public:
/// the Worker URL and the Turnstile *site* key (not the secret).
class FeedbackConfig {
  final String workerUrl;
  final String turnstileSiteKey;

  const FeedbackConfig({required this.workerUrl, required this.turnstileSiteKey});

  factory FeedbackConfig.fromEnvironment() => const FeedbackConfig(
        workerUrl: String.fromEnvironment('FEEDBACK_WORKER_URL'),
        turnstileSiteKey: String.fromEnvironment('TURNSTILE_SITE_KEY'),
      );

  bool get isConfigured => workerUrl.isNotEmpty && turnstileSiteKey.isNotEmpty;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_config_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/features/feedback/feedback_config.dart apps/mobile/test/features/feedback/feedback_config_test.dart
git commit -m "feat(feedback): deps + FeedbackConfig"
```

---

## Task 2: Diagnostics model + collector

**Files:**
- Create: `apps/mobile/lib/features/feedback/diagnostics.dart`
- Test: `apps/mobile/test/features/feedback/diagnostics_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class Diagnostics {
    final String appVersion, build, os, device, locale;
    const Diagnostics({...});
    Map<String, dynamic> toJson();
  }
  abstract class DiagnosticsCollector { Future<Diagnostics> collect(); }
  // Production: PlatformDiagnosticsCollector (package_info_plus + device_info_plus).
  ```

- [ ] **Step 1: Write the failing test** (fake collector proves the shape + JSON)

`apps/mobile/test/features/feedback/diagnostics_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/diagnostics.dart';

void main() {
  test('toJson emits exactly the non-personal diagnostic fields', () {
    const d = Diagnostics(appVersion: '1.0.0', build: '42', os: 'iOS 18.3', device: 'iPhone15,2', locale: 'en_US');
    expect(d.toJson(), {
      'appVersion': '1.0.0', 'build': '42', 'os': 'iOS 18.3', 'device': 'iPhone15,2', 'locale': 'en_US',
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/feedback/diagnostics_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`apps/mobile/lib/features/feedback/diagnostics.dart`:
```dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Non-personal diagnostics. NEVER contains document content or file paths.
class Diagnostics {
  final String appVersion, build, os, device, locale;
  const Diagnostics({
    required this.appVersion,
    required this.build,
    required this.os,
    required this.device,
    required this.locale,
  });

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'build': build,
        'os': os,
        'device': device,
        'locale': locale,
      };
}

abstract class DiagnosticsCollector {
  Future<Diagnostics> collect();
}

class PlatformDiagnosticsCollector implements DiagnosticsCollector {
  const PlatformDiagnosticsCollector();

  @override
  Future<Diagnostics> collect() async {
    final pkg = await PackageInfo.fromPlatform();
    final info = DeviceInfoPlugin();
    String os = 'unknown', device = 'unknown';
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      os = 'iOS ${ios.systemVersion}';
      device = ios.utsname.machine; // e.g. iPhone15,2 — model id, not a serial
    } else if (Platform.isAndroid) {
      final a = await info.androidInfo;
      os = 'Android ${a.version.release}';
      device = '${a.manufacturer} ${a.model}';
    }
    return Diagnostics(
      appVersion: pkg.version,
      build: pkg.buildNumber,
      os: os,
      device: device,
      locale: ui.PlatformDispatcher.instance.locale.toString(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/feedback/diagnostics_test.dart`
Expected: PASS. (The `PlatformDiagnosticsCollector` itself is device-verified in Task 9 — it needs real plugins.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/feedback/diagnostics.dart apps/mobile/test/features/feedback/diagnostics_test.dart
git commit -m "feat(feedback): diagnostics model + platform collector"
```

---

## Task 3: Attestation + Turnstile provider interfaces (+ fakes)

**Files:**
- Create: `apps/mobile/lib/features/feedback/attestation_provider.dart`, `apps/mobile/lib/features/feedback/turnstile_provider.dart`
- Test: `apps/mobile/test/features/feedback/providers_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class Attestation { final String platform, token, challenge; final String? keyId; const Attestation({...}); }
  abstract class AttestationProvider {
    /// Returns an attestation over [challenge], or null when unavailable (→ Turnstile fallback).
    Future<Attestation?> attest(String challenge);
  }
  abstract class TurnstileToken { /* marker for a widget-produced token holder */ }
  ```

**Note:** The real `AppleAttestationProvider` / `PlayIntegrityProvider` call native APIs
(DCAppAttestService / Play Integrity) — they return `null` on host and are proven only
by the Task 9 device test. Host tests use `FakeAttestationProvider`.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/feedback/providers_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';

class _Fake implements AttestationProvider {
  final Attestation? result;
  _Fake(this.result);
  @override
  Future<Attestation?> attest(String challenge) async => result;
}

void main() {
  test('a provider can return an attestation carrying the challenge', () async {
    final p = _Fake(const Attestation(platform: 'ios', token: 't', challenge: 'c', keyId: 'k'));
    final a = await p.attest('c');
    expect(a!.challenge, 'c');
    expect(a.platform, 'ios');
  });
  test('a provider returns null when attestation is unavailable', () async {
    final p = _Fake(null);
    expect(await p.attest('c'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/feedback/providers_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`apps/mobile/lib/features/feedback/attestation_provider.dart`:
```dart
import 'dart:io';
import 'package:flutter/services.dart';

class Attestation {
  final String platform;
  final String token;
  final String challenge;
  final String? keyId;
  const Attestation({
    required this.platform,
    required this.token,
    required this.challenge,
    this.keyId,
  });

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'token': token,
        'challenge': challenge,
        if (keyId != null) 'keyId': keyId,
      };
}

abstract class AttestationProvider {
  Future<Attestation?> attest(String challenge);
}

/// Production provider. Uses a platform channel to the native App Attest /
/// Play Integrity APIs. Returns null when the platform/OS cannot attest, so the
/// caller falls back to Turnstile. The native side is validated by the device test.
class PlatformAttestationProvider implements AttestationProvider {
  static const _channel = MethodChannel('camscanner/attestation');
  const PlatformAttestationProvider();

  @override
  Future<Attestation?> attest(String challenge) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('attest', {'challenge': challenge});
      if (res == null || res['token'] == null) return null;
      return Attestation(
        platform: Platform.isIOS ? 'ios' : 'android',
        token: res['token'] as String,
        challenge: challenge,
        keyId: res['keyId'] as String?,
      );
    } on PlatformException {
      return null; // fall back to Turnstile
    }
  }
}

/// Host/test default: never attests, forcing the Turnstile path.
class NoAttestationProvider implements AttestationProvider {
  const NoAttestationProvider();
  @override
  Future<Attestation?> attest(String challenge) async => null;
}
```

`apps/mobile/lib/features/feedback/turnstile_provider.dart`:
```dart
/// The Turnstile token is produced by the on-screen Turnstile widget and passed
/// into the service at submit time. This holder keeps the service decoupled from
/// the widget package so host tests can supply a token directly.
class TurnstileResult {
  final String? token;
  const TurnstileResult(this.token);
}
```

**Native platform-channel skeletons** (implemented + verified in Task 9; listed here so the interface is complete):
- iOS `apps/mobile/ios/Runner/AttestationChannel.swift` — `DCAppAttestService.shared.generateKey` then `attestKey(_:clientDataHash:)` where `clientDataHash = SHA256(challenge)`, returns base64 attestation + keyId.
- Android `apps/mobile/android/app/src/main/kotlin/.../AttestationChannel.kt` — `IntegrityManager.requestIntegrityToken(...)` with `nonce = challenge`, returns the token.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/feedback/providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/feedback/attestation_provider.dart apps/mobile/lib/features/feedback/turnstile_provider.dart apps/mobile/test/features/feedback/providers_test.dart
git commit -m "feat(feedback): attestation + turnstile provider interfaces"
```

---

## Task 4: FeedbackResult + FeedbackService

**Files:**
- Create: `apps/mobile/lib/features/feedback/feedback_result.dart`, `apps/mobile/lib/features/feedback/feedback_service.dart`
- Test: `apps/mobile/test/features/feedback/feedback_service_test.dart`

**Interfaces:**
- Consumes: `FeedbackConfig`, `DiagnosticsCollector`, `AttestationProvider`, `http.Client`.
- Produces:
  ```dart
  sealed class FeedbackResult {}
  class FeedbackSuccess extends FeedbackResult { final String? issueUrl; }
  class FeedbackDuplicate extends FeedbackResult { final String? issueUrl; }
  class FeedbackRejectedUnverified extends FeedbackResult {}
  class FeedbackRateLimited extends FeedbackResult {}
  class FeedbackInvalid extends FeedbackResult {}
  class FeedbackOffline extends FeedbackResult {}
  class FeedbackServerError extends FeedbackResult {}

  class FeedbackDraft { final String category, message; final String? email; final String? turnstileToken; }
  class FeedbackService {
    FeedbackService({required config, required collector, required attestation, required httpClient, String Function()? newId});
    Future<FeedbackResult> submit(FeedbackDraft draft);
  }
  ```

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/feedback/feedback_service_test.dart`:
```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/diagnostics.dart';
import 'package:mobile/features/feedback/feedback_config.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

class _FakeCollector implements DiagnosticsCollector {
  @override
  Future<Diagnostics> collect() async =>
      const Diagnostics(appVersion: '1.0.0', build: '42', os: 'iOS 18.3', device: 'iPhone15,2', locale: 'en_US');
}

const _config = FeedbackConfig(workerUrl: 'https://worker.test', turnstileSiteKey: 'sk');
const _draft = FeedbackDraft(category: 'bug', message: 'It crashed', email: 'u@e.com', turnstileToken: 'ts');

FeedbackService _service(MockClient client, {AttestationProvider attestation = const NoAttestationProvider()}) =>
    FeedbackService(
      config: _config,
      collector: _FakeCollector(),
      attestation: attestation,
      httpClient: client,
      newId: () => '55555555-5555-5555-5555-555555555555',
    );

void main() {
  test('fetches a challenge then posts feedback; 201 → success with issueUrl', () async {
    final requests = <http.Request>[];
    final client = MockClient((req) async {
      requests.add(req as http.Request);
      if (req.url.path == '/challenge') return http.Response(jsonEncode({'challenge': 'CHAL'}), 200);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['category'], 'bug');
      expect(body['turnstileToken'], 'ts');
      expect(body['idempotencyKey'], '55555555-5555-5555-5555-555555555555');
      expect(body['diagnostics']['device'], 'iPhone15,2');
      return http.Response(jsonEncode({'ok': true, 'issueUrl': 'https://github.com/x/y/issues/3'}), 201);
    });
    final r = await _service(client).submit(_draft);
    expect(r, isA<FeedbackSuccess>());
    expect((r as FeedbackSuccess).issueUrl, contains('/issues/3'));
    expect(requests.first.url.path, '/challenge'); // challenge first
  });

  test('includes attestation when the provider returns one', () async {
    Map<String, dynamic>? posted;
    final client = MockClient((req) async {
      if (req.url.path == '/challenge') return http.Response(jsonEncode({'challenge': 'CHAL'}), 200);
      posted = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'ok': true, 'issueUrl': 'u'}), 201);
    });
    final attest = _StubAttest(const Attestation(platform: 'ios', token: 'attTok', challenge: 'CHAL', keyId: 'kid'));
    await _service(client, attestation: attest).submit(_draft);
    expect(posted!['attestation']['token'], 'attTok');
    expect(posted!['attestation']['challenge'], 'CHAL');
  });

  test('maps status codes to results', () async {
    Future<FeedbackResult> withStatus(int code, String body) {
      final client = MockClient((req) async {
        if (req.url.path == '/challenge') return http.Response(jsonEncode({'challenge': 'C'}), 200);
        return http.Response(body, code);
      });
      return _service(client).submit(_draft);
    }
    expect(await withStatus(200, jsonEncode({'ok': true, 'duplicate': true, 'issueUrl': 'u'})), isA<FeedbackDuplicate>());
    expect(await withStatus(400, '{}'), isA<FeedbackInvalid>());
    expect(await withStatus(401, '{}'), isA<FeedbackRejectedUnverified>());
    expect(await withStatus(429, '{}'), isA<FeedbackRateLimited>());
    expect(await withStatus(502, '{}'), isA<FeedbackServerError>());
  });

  test('network failure → offline', () async {
    final client = MockClient((req) async => throw http.ClientException('no net'));
    expect(await _service(client).submit(_draft), isA<FeedbackOffline>());
  });
}

class _StubAttest implements AttestationProvider {
  final Attestation a;
  _StubAttest(this.a);
  @override
  Future<Attestation?> attest(String challenge) async => a;
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_service_test.dart`
Expected: FAIL — modules missing.

- [ ] **Step 3: Implementation**

`apps/mobile/lib/features/feedback/feedback_result.dart`:
```dart
sealed class FeedbackResult {
  const FeedbackResult();
}
class FeedbackSuccess extends FeedbackResult {
  final String? issueUrl;
  const FeedbackSuccess(this.issueUrl);
}
class FeedbackDuplicate extends FeedbackResult {
  final String? issueUrl;
  const FeedbackDuplicate(this.issueUrl);
}
class FeedbackRejectedUnverified extends FeedbackResult { const FeedbackRejectedUnverified(); }
class FeedbackRateLimited extends FeedbackResult { const FeedbackRateLimited(); }
class FeedbackInvalid extends FeedbackResult { const FeedbackInvalid(); }
class FeedbackOffline extends FeedbackResult { const FeedbackOffline(); }
class FeedbackServerError extends FeedbackResult { const FeedbackServerError(); }
```

`apps/mobile/lib/features/feedback/feedback_service.dart`:
```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'attestation_provider.dart';
import 'diagnostics.dart';
import 'feedback_config.dart';
import 'feedback_result.dart';

class FeedbackDraft {
  final String category;
  final String message;
  final String? email;
  final String? turnstileToken;
  const FeedbackDraft({
    required this.category,
    required this.message,
    this.email,
    this.turnstileToken,
  });
}

class FeedbackService {
  final FeedbackConfig config;
  final DiagnosticsCollector collector;
  final AttestationProvider attestation;
  final http.Client httpClient;
  final String Function() _newId;

  FeedbackService({
    required this.config,
    required this.collector,
    required this.attestation,
    required this.httpClient,
    String Function()? newId,
  }) : _newId = newId ?? (() => const Uuid().v4());

  Future<FeedbackResult> submit(FeedbackDraft draft) async {
    try {
      final base = Uri.parse(config.workerUrl);

      // 1. One-time server-issued challenge (anti-replay for attestation).
      final chalRes = await httpClient.post(base.replace(path: '/challenge'));
      if (chalRes.statusCode != 200) return const FeedbackServerError();
      final challenge = (jsonDecode(chalRes.body) as Map<String, dynamic>)['challenge'] as String;

      // 2. Attestation over the challenge; null → rely on Turnstile.
      final att = await attestation.attest(challenge);

      // 3. Diagnostics (non-personal only).
      final diag = await collector.collect();

      final payload = <String, dynamic>{
        'category': draft.category,
        'message': draft.message,
        if (draft.email != null && draft.email!.isNotEmpty) 'email': draft.email,
        if (draft.turnstileToken != null) 'turnstileToken': draft.turnstileToken,
        if (att != null) 'attestation': att.toJson(),
        'idempotencyKey': _newId(),
        'diagnostics': diag.toJson(),
      };

      // 4. Submit.
      final res = await httpClient.post(
        base.replace(path: '/feedback'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(payload),
      );
      return _map(res);
    } on http.ClientException {
      return const FeedbackOffline();
    } catch (_) {
      return const FeedbackServerError();
    }
  }

  FeedbackResult _map(http.Response res) {
    switch (res.statusCode) {
      case 201:
        return FeedbackSuccess(_url(res));
      case 200:
        final body = _json(res);
        return body['duplicate'] == true ? FeedbackDuplicate(_url(res)) : FeedbackSuccess(_url(res));
      case 400:
        return const FeedbackInvalid();
      case 401:
        return const FeedbackRejectedUnverified();
      case 429:
        return const FeedbackRateLimited();
      default:
        return const FeedbackServerError();
    }
  }

  Map<String, dynamic> _json(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  String? _url(http.Response res) => _json(res)['issueUrl'] as String?;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/feedback/feedback_result.dart apps/mobile/lib/features/feedback/feedback_service.dart apps/mobile/test/features/feedback/feedback_service_test.dart
git commit -m "feat(feedback): FeedbackService (challenge->attest->submit) + result mapping"
```

---

## Task 5: FeedbackDependencies composition root

**Files:**
- Create: `apps/mobile/lib/features/feedback/feedback_dependencies.dart`
- Test: `apps/mobile/test/features/feedback/feedback_dependencies_test.dart`

**Interfaces:**
- Produces:
  ```dart
  typedef FeedbackServiceFactory = FeedbackService Function();
  class FeedbackDependencies {
    final FeedbackConfig config;
    final FeedbackServiceFactory createService;
    const FeedbackDependencies({this.config = ..., FeedbackServiceFactory? createService});
    FeedbackService service();
  }
  ```

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/feedback/feedback_dependencies_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

void main() {
  test('default deps expose a FeedbackService factory', () {
    const deps = FeedbackDependencies();
    expect(deps.service(), isA<FeedbackService>());
  });
  test('a test override factory is used', () {
    var called = false;
    final deps = FeedbackDependencies(createService: () {
      called = true;
      return FeedbackService(
        config: const FeedbackConfigStub(),
        collector: FakeCollectorStub(),
        attestation: const NoAttestationProviderStub(),
        httpClient: HttpStub(),
      );
    });
    deps.service();
    expect(called, isTrue);
  });
}
```
(For the override test, reuse the fakes from `feedback_service_test.dart` by extracting them into `test/features/feedback/_fakes.dart` and importing here — do that extraction as the first action of this step so both tests share one set of fakes. Names above are placeholders for those shared fakes.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_dependencies_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`apps/mobile/lib/features/feedback/feedback_dependencies.dart`:
```dart
import 'package:http/http.dart' as http;

import 'attestation_provider.dart';
import 'diagnostics.dart';
import 'feedback_config.dart';
import 'feedback_service.dart';

typedef FeedbackServiceFactory = FeedbackService Function();

/// Composition root for the Feedback feature (parallel to LibraryDependencies).
class FeedbackDependencies {
  final FeedbackConfig config;
  final FeedbackServiceFactory? _createService;

  const FeedbackDependencies({
    this.config = const FeedbackConfig(
      workerUrl: String.fromEnvironment('FEEDBACK_WORKER_URL'),
      turnstileSiteKey: String.fromEnvironment('TURNSTILE_SITE_KEY'),
    ),
    FeedbackServiceFactory? createService,
  }) : _createService = createService;

  FeedbackService service() =>
      _createService?.call() ??
      FeedbackService(
        config: config,
        collector: const PlatformDiagnosticsCollector(),
        attestation: const PlatformAttestationProvider(),
        httpClient: http.Client(),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_dependencies_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/feedback/feedback_dependencies.dart apps/mobile/test/features/feedback/feedback_dependencies_test.dart apps/mobile/test/features/feedback/_fakes.dart
git commit -m "feat(feedback): FeedbackDependencies composition root"
```

---

## Task 6: FeedbackScreen (form UI)

**Files:**
- Create: `apps/mobile/lib/features/feedback/feedback_screen.dart`
- Test: `apps/mobile/test/features/feedback/feedback_screen_test.dart`

**Interfaces:**
- Consumes: `FeedbackDependencies`, `FeedbackService`, `FeedbackResult`.
- Produces: `class FeedbackScreen extends StatefulWidget { final FeedbackDependencies dependencies; }`
  Widget keys: `feedback-category`, `feedback-message`, `feedback-email`, `feedback-diagnostics-toggle`, `feedback-submit`, `feedback-email-warning`.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/feedback/feedback_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

class _StubService extends FeedbackService {
  FeedbackResult result;
  FeedbackDraft? lastDraft;
  _StubService(this.result) : super(
    config: const FeedbackConfig(workerUrl: 'https://w', turnstileSiteKey: 'k'),
    collector: _NullCollector(), attestation: const NoAttestationProvider(), httpClient: _NullClient(),
  );
  @override
  Future<FeedbackResult> submit(FeedbackDraft draft) async { lastDraft = draft; return result; }
}
// (_NullCollector/_NullClient come from the shared test/features/feedback/_fakes.dart)

Widget _host(FeedbackService service) => MaterialApp(
  home: FeedbackScreen(dependencies: FeedbackDependencies(createService: () => service)),
);

void main() {
  testWidgets('blocks submit when the message is empty', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(_host(s));
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pump();
    expect(s.lastDraft, isNull); // never submitted
    expect(find.text('Please enter a message'), findsOneWidget);
  });

  testWidgets('shows the public-visibility warning next to the email field', (t) async {
    await t.pumpWidget(_host(_StubService(const FeedbackSuccess('u'))));
    expect(find.byKey(const Key('feedback-email-warning')), findsOneWidget);
    expect(find.text('Optional. This will be publicly visible on GitHub.'), findsOneWidget);
  });

  testWidgets('rejects a malformed email', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(_host(s));
    await t.enterText(find.byKey(const Key('feedback-message')), 'hello');
    await t.enterText(find.byKey(const Key('feedback-email')), 'not-an-email');
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pump();
    expect(s.lastDraft, isNull);
    expect(find.text('Enter a valid email or leave it blank'), findsOneWidget);
  });

  testWidgets('submits a valid message and shows success', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(_host(s));
    await t.enterText(find.byKey(const Key('feedback-message')), 'Great app, one bug');
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pumpAndSettle();
    expect(s.lastDraft!.message, 'Great app, one bug');
    expect(find.text('Thanks! Your feedback was sent.'), findsOneWidget);
  });

  testWidgets('toggling diagnostics reveals the preview', (t) async {
    await t.pumpWidget(_host(_StubService(const FeedbackSuccess('u'))));
    expect(find.textContaining('app:'), findsNothing);
    await t.tap(find.byKey(const Key('feedback-diagnostics-toggle')));
    await t.pumpAndSettle();
    expect(find.textContaining('Diagnostics attached'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_screen_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`apps/mobile/lib/features/feedback/feedback_screen.dart`:
```dart
import 'package:flutter/material.dart';

import 'feedback_dependencies.dart';
import 'feedback_result.dart';
import 'feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  final FeedbackDependencies dependencies;
  const FeedbackScreen({super.key, this.dependencies = const FeedbackDependencies()});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _email = TextEditingController();
  String _category = 'bug';
  bool _showDiagnostics = false;
  bool _submitting = false;
  late final FeedbackService _service = widget.dependencies.service();

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      // NOTE: on device, the Turnstile widget supplies a token here (Task 8 wiring).
      final result = await _service.submit(FeedbackDraft(
        category: _category,
        message: _message.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        turnstileToken: _turnstileToken,
      ));
      if (!mounted) return;
      _showResult(result);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _turnstileToken; // set by the Turnstile widget callback (device); null in host tests

  void _showResult(FeedbackResult r) {
    final msg = switch (r) {
      FeedbackSuccess() || FeedbackDuplicate() => 'Thanks! Your feedback was sent.',
      FeedbackRateLimited() => "You've sent a few already — please try again later.",
      FeedbackRejectedUnverified() => "Couldn't verify the app — please try again.",
      FeedbackOffline() => 'Check your connection and try again.',
      FeedbackInvalid() => 'Please check your message and try again.',
      FeedbackServerError() => "Couldn't send right now — please try again.",
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (r is FeedbackSuccess || r is FeedbackDuplicate) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send feedback')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('feedback-category'),
                value: _category,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'bug', child: Text('Bug')),
                  DropdownMenuItem(value: 'idea', child: Text('Idea')),
                  DropdownMenuItem(value: 'question', child: Text('Question')),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'bug'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('feedback-message'),
                controller: _message,
                maxLines: 5,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Your feedback', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a message' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('feedback-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());
                  return ok ? null : 'Enter a valid email or leave it blank';
                },
              ),
              const Padding(
                key: Key('feedback-email-warning'),
                padding: EdgeInsets.only(top: 4),
                child: Text('Optional. This will be publicly visible on GitHub.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('feedback-diagnostics-toggle'),
                onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
                child: Text(_showDiagnostics ? 'Hide what will be sent' : 'What will be sent?'),
              ),
              if (_showDiagnostics)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Diagnostics attached: app version, OS version, device model, and language. '
                    'No scanned documents or their contents are ever sent.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('feedback-submit'),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/feedback/feedback_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/feedback/feedback_screen.dart apps/mobile/test/features/feedback/feedback_screen_test.dart
git commit -m "feat(feedback): FeedbackScreen form with validation + diagnostics preview"
```

---

## Task 7: Overflow menu entry + DI threading

**Files:**
- Modify: `apps/mobile/lib/features/library/home_screen.dart` (add `feedbackDependencies` field + overflow menu in `_buildNormalAppBar`)
- Modify: `apps/mobile/lib/main.dart` (thread `feedbackDependencies` through `runCamScannerApp` → `CamScannerApp` → `HomeScreen`)
- Test: `apps/mobile/test/features/library/home_feedback_menu_test.dart`

**Interfaces:**
- Consumes: `FeedbackDependencies`, `FeedbackScreen`.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/library/home_feedback_menu_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';

void main() {
  testWidgets('overflow menu opens the feedback screen', (t) async {
    await t.pumpWidget(const MaterialApp(home: HomeScreen()));
    await t.pump(const Duration(milliseconds: 200)); // let cold-start settle
    await t.tap(find.byKey(const Key('home-overflow-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-menu-feedback')));
    await t.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/home_feedback_menu_test.dart`
Expected: FAIL — no overflow menu key.

- [ ] **Step 3: Implementation**

In `apps/mobile/lib/features/library/home_screen.dart`:
- Add the import:
  ```dart
  import '../feedback/feedback_dependencies.dart';
  import '../feedback/feedback_screen.dart';
  ```
- Add a field to `HomeScreen`:
  ```dart
  final FeedbackDependencies feedbackDependencies;
  ```
  and to its constructor: `this.feedbackDependencies = const FeedbackDependencies(),`
- Add this action to the end of `_buildNormalAppBar()`'s `actions` list:
  ```dart
      PopupMenuButton<String>(
        key: const Key('home-overflow-menu'),
        onSelected: (v) {
          if (v == 'feedback') {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FeedbackScreen(dependencies: widget.feedbackDependencies),
            ));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(key: Key('home-menu-feedback'), value: 'feedback', child: Text('Send feedback')),
        ],
      ),
  ```

In `apps/mobile/lib/main.dart`:
- Add `import 'features/feedback/feedback_dependencies.dart';`
- Add `FeedbackDependencies feedbackDependencies = const FeedbackDependencies(),` param to `runCamScannerApp` and the `CamScannerApp` constructor + field.
- Pass it into `HomeScreen(... feedbackDependencies: feedbackDependencies)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/home_feedback_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full host suite + analyze** (no regressions)

Run: `cd apps/mobile && flutter analyze && flutter test`
Expected: analyze clean; all host tests green.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/home_screen.dart apps/mobile/lib/main.dart apps/mobile/test/features/library/home_feedback_menu_test.dart
git commit -m "feat(feedback): overflow-menu entry + DI threading"
```

---

## Task 8: Wire Turnstile widget on device

**Files:**
- Modify: `apps/mobile/lib/features/feedback/feedback_screen.dart`
- (No host test — the widget renders a real Cloudflare challenge in a WebView; verified in Task 9.)

- [ ] **Step 1:** Add the `cloudflare_turnstile` widget to the form, above the Send button, gated on `widget.dependencies.config.isConfigured`:
```dart
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
// ...inside build(), before the submit button:
if (widget.dependencies.config.turnstileSiteKey.isNotEmpty)
  CloudflareTurnstile(
    siteKey: widget.dependencies.config.turnstileSiteKey,
    options: TurnstileOptions(mode: TurnstileMode.managed),
    onTokenReceived: (token) => _turnstileToken = token,
    onTokenExpired: () => _turnstileToken = null,
  ),
```
(Guarding on config keeps host widget tests — which have no real site key — from trying to load a WebView. Confirm the exact `cloudflare_turnstile` API against its README during implementation; adjust prop names if the package version differs.)

- [ ] **Step 2:** `cd apps/mobile && flutter analyze` → clean. `flutter test` → still green (host tests skip the widget via the config guard).

- [ ] **Step 3: Commit**
```bash
git add apps/mobile/lib/features/feedback/feedback_screen.dart
git commit -m "feat(feedback): Turnstile widget (fallback human-proof) on device"
```

---

## Task 9: BDD device test — real submission on Android AND iOS

**Files:**
- Create: `apps/mobile/integration_test/feedback_submit.feature`
- Create: `apps/mobile/test/step/the_feedback_form_is_open.dart`, `.../feedback_is_submitted_with_message.dart`, `.../a_confirmation_is_shown.dart`
- Generated: `apps/mobile/integration_test/feedback_submit_test.dart` (via build_runner)
- Native: `apps/mobile/ios/Runner/AttestationChannel.swift`, `apps/mobile/android/app/src/main/kotlin/.../AttestationChannel.kt` (register on the `camscanner/attestation` channel)

**Interfaces:**
- Consumes: real `FeedbackService` pointed at the **staging** Worker via `--dart-define`.

- [ ] **Step 1: Implement the native attestation channels**
  - iOS `AttestationChannel.swift`: on `attest`, use `DCAppAttestService.shared`; `generateKey`, compute `clientDataHash = SHA256(challenge)`, `attestKey(keyId, clientDataHash:)`, return `{ "token": base64Attestation, "keyId": keyId }`. Register in `AppDelegate`.
  - Android `AttestationChannel.kt`: on `attest`, `IntegrityManagerFactory.create(context).requestIntegrityToken(IntegrityTokenRequest.builder().setNonce(challenge).build())`, return `{ "token": token }`. Register in `MainActivity`.

- [ ] **Step 2: Write the `.feature`**

`apps/mobile/integration_test/feedback_submit.feature`:
```gherkin
Feature: Send feedback creates a GitHub issue
  Scenario: A user submits feedback from the app
    Given the feedback form is open
    When feedback is submitted with message "Device round-trip test"
    Then a confirmation is shown
```

- [ ] **Step 3: Write the step implementations** in `test/step/`:

`the_feedback_form_is_open.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';

Future<void> theFeedbackFormIsOpen(WidgetTester tester) async {
  // Drive the real screen with the real (env-configured) dependencies.
  await tester.pumpWidget(MaterialApp(
    home: FeedbackScreen(dependencies: FeedbackDependencies()),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Send feedback'), findsOneWidget);
}
```

`feedback_is_submitted_with_message.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> feedbackIsSubmittedWithMessage(WidgetTester tester, String message) async {
  await tester.enterText(find.byKey(const Key('feedback-message')), message);
  await tester.pumpAndSettle(const Duration(seconds: 2)); // allow Turnstile token
  await tester.tap(find.byKey(const Key('feedback-submit')));
  await tester.pumpAndSettle(const Duration(seconds: 8)); // challenge + attest + POST
}
```

`a_confirmation_is_shown.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

Future<void> aConfirmationIsShown(WidgetTester tester) async {
  expect(find.text('Thanks! Your feedback was sent.'), findsOneWidget);
}
```

- [ ] **Step 4: Generate the test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: creates `integration_test/feedback_submit_test.dart`.

- [ ] **Step 5: Run on a real ANDROID device** (staging Worker + test repo):

Run:
```bash
cd apps/mobile && flutter test integration_test/feedback_submit_test.dart \
  -d <android-device-id> \
  --dart-define=FEEDBACK_WORKER_URL=$STAGING_WORKER_URL \
  --dart-define=TURNSTILE_SITE_KEY=$TURNSTILE_SITE_KEY
```
Expected: PASS; a new issue appears in the **test repo**; Worker log shows Play Integrity `ok`.

- [ ] **Step 6: Run on a real iOS device** (same, `-d <ios-device-id>`):

Expected: PASS; a new issue appears; Worker log shows App Attest `ok`. If App Attest cannot run (e.g. simulator only available), record it as an explicit named gap — do NOT claim iOS done.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/integration_test/feedback_submit.feature apps/mobile/integration_test/feedback_submit_test.dart apps/mobile/test/step/the_feedback_form_is_open.dart apps/mobile/test/step/feedback_is_submitted_with_message.dart apps/mobile/test/step/a_confirmation_is_shown.dart apps/mobile/ios/Runner/AttestationChannel.swift "apps/mobile/android/app/src/main/kotlin"
git commit -m "test(feedback): BDD device round-trip + native attestation channels"
```

---

## Task 10: Privacy disclosures (release blockers)

**Files:**
- Modify: `apps/web/privacy.html`
- Create: `docs/superpowers/store-disclosure-checklist.md`

- [ ] **Step 1: Add a Feedback section to `apps/web/privacy.html`** describing: what is collected (the message; optional email; device diagnostics = app version, OS, device model, language), that it is sent to a Cloudflare Worker and becomes a **public GitHub issue**, that email — if provided — is publicly visible, and that no scanned documents or their contents are ever sent. Match the page's existing heading/markup style.

- [ ] **Step 2: Write `docs/superpowers/store-disclosure-checklist.md`** listing the exact store-console updates to make before the release that ships this feature:
  - **Apple App Privacy:** declare "Contact Info → Email Address" (optional, linked to App Functionality, not tracking) and "Diagnostics" (or "Identifiers" if the device model counts) linked to App Functionality.
  - **Google Play Data Safety:** declare the same data types; purpose "App functionality"; not shared for advertising; encrypted in transit.
  - Link to the updated `privacy.html`.

- [ ] **Step 3: Commit**

```bash
git add apps/web/privacy.html docs/superpowers/store-disclosure-checklist.md
git commit -m "docs(feedback): privacy.html feedback disclosure + store data-safety checklist"
```

---

## Self-review notes (coverage vs spec)

- Overflow-menu entry point → Task 7. ✅
- Category / message (req, ≤4000) / optional email w/ public warning → Task 6. ✅
- Transparent diagnostics preview; no document data → Tasks 2, 6. ✅
- Attestation primary + Turnstile fallback (client side) → Tasks 3, 8, 4 (service prefers attestation, always allows Turnstile). ✅
- Server-issued challenge fetched before submit (anti-replay) → Task 4. ✅
- Idempotency key per submission → Task 4. ✅
- Result mapping incl. duplicate/unverified/rate-limited/offline; message preserved on failure (form not cleared) → Tasks 4, 6. ✅
- DI via FeedbackDependencies, threaded through main.dart → Tasks 5, 7. ✅
- TDD host tests + BDD `.feature` device test on Android AND iOS → all tasks; Task 9. ✅ (App Attest success path is device-only — named gap if a real iOS device is unavailable)
- Privacy: privacy.html + store disclosures → Task 10. ✅

## Known gaps to state, never hide
- App Attest / Play Integrity success paths are provable ONLY on real hardware (Task 9). If either device is unavailable at execution time, that platform's attestation is an explicit gap — the Turnstile fallback still gives a working, human-verified path.
- The exact `cloudflare_turnstile` and attestation plugin APIs must be confirmed against their current READMEs during Tasks 3/8 (versions move); the interfaces here are stable regardless of the package chosen.
