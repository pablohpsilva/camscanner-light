#!/usr/bin/env bash
# Verify D2 (delete document) acceptance criteria.
# Run: bash scripts/verify/d2.sh
#
# NOTE: D2 (delete document) was implemented as part of B3 (page viewer +
# delete) rather than as a standalone step. All D2 assertions — repository
# deleteDocument interface, transactional Drift implementation, UI confirmation
# dialog, widget tests, and BDD integration test — live in b3.sh.
# This script delegates to b3.sh so the D2 gate is still runnable by name.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/b3.sh" "$@"
