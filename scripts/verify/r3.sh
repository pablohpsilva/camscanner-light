#!/usr/bin/env bash
# Verify R3 (sharing leftovers: link-share + fax interfaces + not-available UX).
# Run: bash scripts/verify/r3.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== R3 verification =="
require_tool flutter
require_tool git

# ---- Interfaces exist ----
assert_file_has "FaxProvider interface" \
  "apps/mobile/lib/features/library/fax_provider.dart" "abstract interface class FaxProvider"
assert_file_has "UnavailableFaxProvider default" \
  "apps/mobile/lib/features/library/fax_provider.dart" "class UnavailableFaxProvider"
assert_file_has "LinkShareChannel interface" \
  "apps/mobile/lib/features/library/link_share_channel.dart" "abstract interface class LinkShareChannel"
assert_file_has "UnavailableLinkShareChannel default" \
  "apps/mobile/lib/features/library/link_share_channel.dart" "class UnavailableLinkShareChannel"

# ---- Wired into the composition root ----
assert_file_has "library_dependencies injects linkShare" \
  "apps/mobile/lib/features/library/library_dependencies.dart" "UnavailableLinkShareChannel()"
assert_file_has "library_dependencies injects fax" \
  "apps/mobile/lib/features/library/library_dependencies.dart" "UnavailableFaxProvider()"

# ---- Shared menu module present ----
assert_file_has "shared share-menu module" \
  "apps/mobile/lib/features/library/widgets/share_menu_button.dart" "shareExtraMenuItems"

# ---- Unit + widget tests green ----
assert_cmd "share leftovers unit + widget tests pass" "All tests passed" \
  bash -c "cd apps/mobile && flutter test test/features/library/fax_provider_test.dart test/features/library/link_share_channel_test.dart test/features/library/widgets/share_menu_button_test.dart test/features/library/library_dependencies_share_test.dart 2>&1"

verify_summary
