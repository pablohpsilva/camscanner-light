# Installing a build on a physical device

> Load this before installing a build on a real device. `flutter install` does
> NOT build.

## `flutter install` does NOT build

**Trap that has bitten us:** `flutter install` never compiles. It side-loads
whatever artifact already sits in `build/` — so `flutter install --release`
finishes in seconds *without building* and can silently install a **stale Debug**
`Runner.app` from an earlier run. A Debug Flutter build crashes ~2–10ms into cold
launch on-device (the VSyncClient SIGSEGV below), so the app "opens then closes"
even though the install reported success. On Android the same command instead
fails loudly (`app-release.apk does not exist`) when nothing was pre-built.

**Always BUILD first, then install** — on both platforms:

```bash
# iOS (physical device)
flutter build ios --release && flutter install -d <ios-device-id>

# Android
flutter build apk --release && flutter install -d <android-device-id>
```

## Verify the artifact is actually Release before trusting it

Run `bash scripts/verify-artifact.sh` (asserts Release + prints size), or check
by hand:

```bash
APP=build/ios/iphoneos/Runner.app
ls -lh "$APP/Frameworks/App.framework/App"           # Release: multi-MB AOT dylib. Debug: ~34KB stub
ls "$APP/Frameworks/App.framework/flutter_assets/"   # Debug ONLY has kernel_blob.bin + *_snapshot_data
```

If `App` is tiny and `kernel_blob.bin` / `vm_snapshot_data` / `isolate_snapshot_data`
are present, it's a Debug build — do NOT install it, rebuild with `--release`.

## Diagnosing a launch crash

Diagnose a launch crash with the on-device crash log: `idevicecrashreport -k <dir>`
then read the newest `Runner-*.ips`. The Debug-JIT signature is `EXC_BAD_ACCESS`
(SIGSEGV) in `-[VSyncClient initWithTaskRunner:callback:]` during
`-[FlutterViewController viewDidLoad]`.
