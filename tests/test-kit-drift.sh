#!/usr/bin/env bash
# agents/hooks/kit-drift.sh: one SessionStart reminder when the project is behind the
# kit, silent when it is in sync, when the kit path is wrong, or with --skip paths.
#
# Usage:  bash tests/test-kit-drift.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

new_project() { hook_project_new kit-drift.sh; }

event() { jq -r '.hookSpecificOutput.hookEventName // empty' <<<"$OUTPUT" 2>/dev/null || true; }

run_drift() {
  if OUTPUT="$(printf '{}' | "$HOOK" "$@" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi
}

test_a_fresh_project_is_reported() {
  new_project
  run_drift "$REPO_ROOT"
  assert_status 0 'the hook never fails a session'
  assert_equals 'SessionStart' "$(event)" 'the output is a SessionStart context'
  assert_contains 'is ahead of this project' 'the reminder says the kit is ahead'
  assert_contains 'project-update' 'the reminder names the skill to run'
}

test_synced_project_is_silent() {
  new_project
  "$REPO_ROOT/sync" --target "$ROOT" --apply --quiet >/dev/null
  run_drift "$REPO_ROOT"
  assert_equals '' "$OUTPUT" 'a synced project gets no reminder'
}

test_skip_paths_are_passed_through() {
  new_project
  "$REPO_ROOT/sync" --target "$ROOT" --apply --quiet --skip compose.worktree.yaml >/dev/null
  run_drift "$REPO_ROOT" compose.worktree.yaml
  assert_equals '' "$OUTPUT" 'the skipped file does not raise a reminder'
  run_drift "$REPO_ROOT"
  assert_contains 'is ahead' 'without the skip the file is reported'
}

test_a_harness_opened_in_a_worktree_checks_the_docker_root() {
  new_project
  "$REPO_ROOT/sync" --target "$ROOT" --apply --quiet >/dev/null
  hook_worktree_new
  run_drift "$REPO_ROOT"
  assert_equals '' "$OUTPUT" 'a synced project is silent from a worktree too'
  rm "$ROOT/bin/wt"
  run_drift "$REPO_ROOT"
  assert_contains 'is ahead' 'drift in the Docker root is reported from a worktree'
}

test_bad_kit_paths_are_silent() {
  new_project
  run_drift "$SANDBOX/not-a-kit"
  assert_status 0 'a missing kit path passes'
  assert_equals '' "$OUTPUT" 'a missing kit path prints nothing'
  mkdir -p "$SANDBOX/empty-kit"
  run_drift "$SANDBOX/empty-kit"
  assert_equals '' "$OUTPUT" 'a directory without sync prints nothing'
  run_drift
  assert_equals '' "$OUTPUT" 'no kit argument prints nothing'
}

run_tests
finish
