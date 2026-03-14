#!/bin/bash
set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
BASE_REV="${2:-}"
cd "$TARGET_DIR"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

note() {
  echo "VERIFY: $*"
}

require_file() {
  local path="$1"
  [ -f "$path" ] || fail "missing required file: $path"
  note "found $path"
}

detect_package_manager() {
  if [ -f package-lock.json ]; then
    echo "npm"
  elif [ -f pnpm-lock.yaml ]; then
    echo "pnpm"
  elif [ -f yarn.lock ]; then
    echo "yarn"
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then
    echo "bun"
  else
    echo ""
  fi
}

has_package_script() {
  local script_name="$1"
  node -e "const pkg=require('./package.json'); process.exit(pkg.scripts && pkg.scripts['$script_name'] ? 0 : 1)"
}

run_package_script() {
  local pm="$1" script_name="$2"
  case "$pm" in
    npm) npm run "$script_name" ;;
    pnpm) pnpm run "$script_name" ;;
    yarn) yarn "$script_name" ;;
    bun) bun run "$script_name" ;;
    *) fail "unsupported package manager: $pm" ;;
  esac
}

[ -d .git ] || fail "not a git repository: $TARGET_DIR"
[ -f package.json ] || fail "missing package.json"

PACKAGE_MANAGER="$(detect_package_manager)"
[ -n "$PACKAGE_MANAGER" ] || fail "could not determine package manager from lock file"
note "using $PACKAGE_MANAGER"

has_package_script test || fail "missing package.json script: test"
has_package_script build || fail "missing package.json script: build"

note "running test"
run_package_script "$PACKAGE_MANAGER" test

note "running build"
run_package_script "$PACKAGE_MANAGER" build

require_file "docs/SESSION_PLAN.md"

if [ -n "$BASE_REV" ] && git rev-parse --verify "$BASE_REV^{commit}" >/dev/null 2>&1; then
  UNEXPECTED_DOC_MARKDOWN_CHANGES="$(
    git diff --name-only "$BASE_REV..HEAD" -- docs |
      grep '^docs/.*\.md$' |
      grep -v '^docs/SESSION_PLAN\.md$' |
      grep -v '^docs/SESSION_BET\.md$' |
      grep -v '^docs/RESEARCH_AGENDA\.md$' || true
  )"
  if [ -n "$UNEXPECTED_DOC_MARKDOWN_CHANGES" ]; then
    echo "$UNEXPECTED_DOC_MARKDOWN_CHANGES" >&2
    fail "unexpected docs markdown outside SESSION_PLAN.md was modified during actor run"
  fi
  note "non-session-plan docs markdown unchanged since $BASE_REV"
fi

TRACKED_STATUS="$(git status --short --untracked-files=no)"
if [ -n "$TRACKED_STATUS" ]; then
  echo "$TRACKED_STATUS" >&2
  fail "tracked files are still modified after actor run"
fi
note "tracked files are clean"

if [ "${SKIP_UPSTREAM_CHECK:-0}" != "1" ]; then
  UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
  if [ -n "$UPSTREAM" ]; then
    AHEAD_COUNT="$(git rev-list --count "${UPSTREAM}..HEAD")"
    if [ "$AHEAD_COUNT" -ne 0 ]; then
      fail "local branch is ahead of upstream by $AHEAD_COUNT commit(s)"
    fi
    note "branch is in sync with $UPSTREAM"
  else
    note "no upstream configured; skipping push verification"
  fi
else
  note "upstream check skipped (deferred push mode)"
fi

note "verification passed"
