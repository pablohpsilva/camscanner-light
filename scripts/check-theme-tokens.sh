#!/usr/bin/env bash
# P15 token-bypass guard: no hardcoded `Color(0x…)` hex literals may live outside
# the Ream palette (lib/theme/ream_colors.dart). Named scrim/shadow/ink consts
# and the light/dark palettes are defined there; every other color must reference
# a ReamColors token or one of those named consts.
#
# NOTE: `Colors.*` and raw `TextStyle(` are intentionally NOT guarded. The
# scan/photo UI is legitimately theme-INDEPENDENT — black photo canvases, white
# crop handles + scrims painted over images, detection-confidence cues
# (green/amber/blue), the QR code's required white background, and
# `statusBarColor: transparent`. Forcing those onto warm-paper/dark theme tokens
# would be a visual regression, so they stay as explicit Material colors.
#
# Usage (from repo root):  bash scripts/check-theme-tokens.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APP="$ROOT/apps/mobile"
cd "$APP"

hits="$(grep -rn 'Color(0x' lib/features lib/theme/widgets || true)"
if [ -n "$hits" ]; then
  echo "❌ Hardcoded Color(0x…) outside the Ream palette:"
  echo "$hits"
  echo "→ Use a ReamColors token or a named const in lib/theme/ream_colors.dart."
  exit 1
fi
echo "✓ No hardcoded Color(0x…) in lib/features or lib/theme/widgets."
