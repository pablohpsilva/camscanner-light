#!/usr/bin/env bash
# Fails if the committed legal artifacts differ from what the generators
# produce. The generated Dart, the 33 web pages, and the inline-parity test
# fixture are all committed (Pages uploads apps/web verbatim, with no build
# step), so this is what stops the app, the website, and the parity test from
# drifting apart from libs/legal-content/content/.
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUTS=(
  "apps/mobile/lib/features/legal/generated/legal_content.g.dart"
  "apps/web/terms.html"
  "apps/web/privacy.html"
  "apps/web/faq.html"
  "apps/web/legal"
  "apps/mobile/test/features/legal/inline_parity_fixture.json"
)

# Invoke node directly rather than through `pnpm --filter ... <script>`: pnpm's
# implicit dependency check spawns an inner `pnpm install` that corrupts
# pnpm-workspace.yaml in some local environments (it has, twice, on this repo's
# dev machine, for every workspace package, including ones this work never
# touched). Calling node keeps the guard identical locally and in CI.
echo "==> Running the content test suite"
( cd libs/legal-content && node --test )

echo "==> Regenerating legal artifacts"
( cd libs/legal-content && node src/generate.mjs )
( cd libs/legal-content && node src/inline-parity-fixture.mjs )

echo "==> Checking for drift"
# Untracked files matter as much as modified ones: `git diff` is blind to a
# brand-new apps/web/legal/*.html that was generated but never committed.
UNTRACKED="$(git ls-files --others --exclude-standard -- "${OUTPUTS[@]}")"
if [ -n "$UNTRACKED" ]; then
  echo
  echo "FAIL: generated legal content includes files that were never committed:"
  echo "$UNTRACKED"
  echo "Fix: git add them, or delete them if they are no longer generated."
  exit 1
fi

if ! git diff --quiet -- "${OUTPUTS[@]}"; then
  echo
  echo "FAIL: generated legal content is out of date."
  echo "Someone edited a generated file by hand, or edited content/ without regenerating."
  echo "Fix (from the repo root):"
  echo "  node libs/legal-content/src/generate.mjs"
  echo "  node libs/legal-content/src/inline-parity-fixture.mjs"
  echo "then commit the result."
  echo
  git diff --stat -- "${OUTPUTS[@]}"
  exit 1
fi

echo "OK: legal content is in sync (3 documents x 11 locales)."
