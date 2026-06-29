#!/usr/bin/env bash
# Manual real-plugin (real camera + real permission_handler) verification — Android.
#
# WHY THIS IS MANUAL (not in the gate): the real camera2 API needs the OS runtime
# CAMERA permission. Under `flutter test`, the app is installed fresh (ungranted)
# and the real permission request raises the system permission dialog
# (GrantPermissionsActivity), which the Flutter integration_test driver cannot
# tap — so a real preview can never render there. This script bypasses the dialog
# by installing the APK with `-g` (grant all runtime permissions at install), then
# launches the app so you can SEE the real, live camera preview.
#
# Usage: bash apps/mobile/tool/manual_real_camera_check.sh
# Requires: a booted Android emulator/device with a virtual camera (the default
# Medium_Phone_API_35 AVD has hw.camera.back=virtualscene).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
APP_ID="com.camscannerlight.mobile"
APK="$ROOT/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"

dev="$("$ADB" devices | awk '/emulator-.*device$|device$/{print $1; exit}')"
[ -z "$dev" ] && { echo "FAIL: no Android device booted (boot one: flutter emulators --launch Medium_Phone_API_35)"; exit 1; }
echo "Device: $dev"

echo "1/4 Building debug APK..."
( cd "$ROOT/apps/mobile" && flutter build apk --debug ) || { echo "FAIL: build"; exit 1; }

echo "2/4 Installing WITH runtime permissions granted (-g, bypasses the dialog)..."
"$ADB" -s "$dev" install -r -g "$APK" || { echo "FAIL: install"; exit 1; }
"$ADB" -s "$dev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null

echo "3/4 Launching the app and opening Scan..."
"$ADB" -s "$dev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 6
# Tap the Scan FAB. Compute its position from the actual screen size (the
# extended FAB sits near the bottom-right: ~84% width, ~93.5% height).
size="$("$ADB" -s "$dev" shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
w="${size%x*}"; h="${size#*x}"
tx=$(( w * 84 / 100 )); ty=$(( h * 935 / 1000 ))
echo "    screen ${w}x${h} → tapping Scan FAB at (${tx},${ty})"
"$ADB" -s "$dev" shell input tap "$tx" "$ty" >/dev/null 2>&1
sleep 6

echo "4/4 Capturing a screenshot for you to inspect..."
shot="$ROOT/apps/mobile/build/manual-real-camera.png"
"$ADB" -s "$dev" exec-out screencap -p > "$shot" 2>/dev/null
echo
echo "DONE. Open: $shot"
echo "EXPECT: a live camera preview (the emulator's virtual scene), NOT the"
echo "        'Camera access is needed' rationale and NOT 'Camera unavailable'."
echo "If you see the rationale, the grant didn't take; re-run on a fresh emulator."
