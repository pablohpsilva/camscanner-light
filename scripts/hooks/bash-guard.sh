#!/usr/bin/env bash
# PreToolUse(Bash) guard for this repo. Registered in .claude/settings.json.
#
# It does three cheap, safe things and otherwise gets out of the way:
#   1. Blocks a `flutter install` that would side-load a DEBUG build (the
#      "opens then closes" VSyncClient crash). Blocks ONLY on a confirmed Debug
#      verdict from scripts/verify-artifact.sh -- never on a Release build.
#   2. Blocks a `git commit` whose staged set contains obvious secrets
#      (signing keys, PEM private keys, AWS/GitHub tokens, App Store Connect
#      API key/issuer with a real value).
#   3. Warns (permission "ask", non-blocking) on `git add -A`/`.`/`--all` --
#      the long-lived uncommitted WIP pile can otherwise contaminate a commit.
#
# FAIL-OPEN by construction: any internal error, missing tool, or unmatched
# command falls through to `allow` (exit 0). A guard must never wedge a session.
#
# Hook exit contract (Claude Code PreToolUse):
#   exit 0            -> allow (optionally with JSON on stdout for "ask")
#   exit 2 + stderr   -> block; stderr is shown to the model
set +e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"   # scripts/hooks
ROOT="$(cd "$DIR/../.." 2>/dev/null && pwd -P)"                      # repo root
[ -n "$ROOT" ] || exit 0

allow() { exit 0; }

input="$(cat 2>/dev/null)"     # PreToolUse JSON payload (contains tool_input.command)
[ -n "$input" ] || allow

# --- 1) flutter install guard ------------------------------------------------
if printf '%s' "$input" | grep -Eq 'flutter[[:space:]]+install'; then
  verify="$ROOT/scripts/verify-artifact.sh"
  if [ -f "$verify" ]; then
    out="$(cd "$ROOT" && bash "$verify" 2>&1)"; rc=$?   # anchor detection to this project
    if [ "$rc" -eq 1 ]; then     # 1 == confirmed DEBUG (0 Release, 2 not found)
      {
        echo "BLOCKED: 'flutter install' would side-load a DEBUG build that crashes"
        echo "~2-10ms into cold launch on-device (VSyncClient SIGSEGV; the JIT needs a"
        echo "debugger). flutter install never compiles -- it installs whatever sits in build/."
        echo
        echo "$out"
        echo
        echo "Fix: build Release first, then install --"
        echo "  flutter build ios --release   (or: bash scripts/build-ios-release.sh)"
        echo "  flutter build apk --release"
      } >&2
      exit 2
    fi
  fi
  allow
fi

# --- 3) git add -A / . / --all : warn (ask), do not block --------------------
if printf '%s' "$input" | grep -Eq 'git[[:space:]]+add[[:space:]]+(-A([[:space:]]|"|$)|--all([[:space:]]|"|$)|\.([[:space:]]|"|$))'; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git add -A/./--all can sweep the long-lived uncommitted WIP pile into this commit. Prefer named paths (git add <path> ...). Approve only if you truly mean to stage everything, and verify with git show <sha> --stat afterward."}}'
  exit 0
fi

# --- 2) git commit : secret scan of the staged set ---------------------------
if printf '%s' "$input" | grep -Eq 'git[[:space:]]+commit'; then
  cd "$ROOT" 2>/dev/null || allow
  names="$(git diff --cached --name-only 2>/dev/null)"
  [ -n "$names" ] || allow

  # (a) secret-bearing file types
  if printf '%s\n' "$names" | grep -Eiq '\.(p8|p12|pfx|keystore|jks|mobileprovision)$'; then
    hit="$(printf '%s\n' "$names" | grep -Ei '\.(p8|p12|pfx|keystore|jks|mobileprovision)$' | head -3)"
    { echo "BLOCKED: staged files look like signing/secret material:"; echo "$hit"
      echo "Unstage them (git reset <file>) and keep them out of git."; } >&2
    exit 2
  fi

  # (b) secret-looking content in the staged diff. Patterns require a REAL value
  #     so placeholders like <KEY_ID> in docs never trip them.
  if git diff --cached 2>/dev/null | grep -Eq \
    '(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|--apiKey[= ]+[A-Za-z0-9]{6,}|--apiIssuer[= ]+[0-9a-fA-F]{4,})'; then
    { echo "BLOCKED: the staged diff contains what looks like a live credential"
      echo "(PEM private key / AWS key / GitHub token / App Store Connect API key)."
      echo "Remove it or replace with a placeholder before committing."; } >&2
    exit 2
  fi
  allow
fi

allow
