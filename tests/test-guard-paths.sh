#!/usr/bin/env bash
# agents/hooks/guard-paths.sh: deny a write into build output, warn on src/ while it
# sits on a protected branch, stay silent everywhere else.
#
# Usage:  bash tests/test-guard-paths.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

HOOK="$REPO_ROOT/agents/hooks/guard-paths.sh"
export CLAUDE_PROJECT_DIR=''

run_hook() {
  local payload="$1"
  if OUTPUT="$(printf '%s' "$payload" | "$HOOK" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi
}

decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$OUTPUT" 2>/dev/null || true; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$OUTPUT" 2>/dev/null || true; }
context() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUTPUT" 2>/dev/null || true; }

payload_for() {
  jq -n --arg cwd "$1" --arg f "$2" '{cwd:$cwd,tool_input:{file_path:$f}}'
}

patch_payload_for() {
  jq -n --arg cwd "$1" --arg f "$2" \
    '{cwd:$cwd,tool_input:{command:("*** Begin Patch\n*** Update File: " + $f + "\n*** End Patch")}}'
}

project_on_branch() {
  PROJECT="$SANDBOX/project"
  mkdir -p "$PROJECT/src/app/code/Vendor/Module"
  git -c init.defaultBranch=master init -q "$PROJECT/src"
  git -C "$PROJECT/src" config user.name 'kit tests'
  git -C "$PROJECT/src" config user.email 'tests@example.invalid'
  git -C "$PROJECT/src" config commit.gpgsign false
  printf 'seed\n' > "$PROJECT/src/README.md"
  git -C "$PROJECT/src" add README.md
  git -C "$PROJECT/src" commit -q -m seed
  if [[ "${1:-master}" != 'master' ]]; then
    git -C "$PROJECT/src" checkout -q -b "$1"
  fi
  export CLAUDE_PROJECT_DIR="$PROJECT"
}

test_output_directories_are_denied() {
  sandbox_new
  run_hook "$(payload_for "$SANDBOX" 'src/vendor/acme/lib/a.php')"
  assert_status 0 'a write into vendor/ does not fail the hook'
  assert_equals 'deny' "$(decision)" 'vendor/ is denied'
  assert_contains 'build output' 'the reason names the cause' "$(reason)"
}

test_generated_and_pub_static_are_denied() {
  sandbox_new
  run_hook "$(payload_for "$SANDBOX" 'src/generated/code/a.php')"
  assert_equals 'deny' "$(decision)" 'generated/ is denied'
  run_hook "$(payload_for "$SANDBOX" 'src/pub/static/frontend/a.js')"
  assert_equals 'deny' "$(decision)" 'pub/static/ is denied'
}

test_relative_paths_resolve_against_cwd() {
  sandbox_new
  run_hook "$(payload_for "$SANDBOX" 'vendor/a.php')"
  assert_equals 'deny' "$(decision)" 'a relative path is resolved before matching'
}

test_codex_patch_payload_is_checked() {
  sandbox_new
  run_hook "$(patch_payload_for "$SANDBOX" 'src/generated/a.php')"
  assert_equals 'deny' "$(decision)" 'an apply_patch payload is checked too'
}

test_a_normal_source_file_is_silent() {
  sandbox_new
  run_hook "$(payload_for "$SANDBOX" 'src/app/code/Vendor/Module/Model/Thing.php')"
  assert_status 0 'a normal file passes'
  assert_equals '' "$OUTPUT" 'a normal file prints nothing'
}

test_empty_and_invalid_payloads_are_ignored() {
  sandbox_new
  run_hook '{}'
  assert_status 0 'an empty payload passes'
  assert_equals '' "$OUTPUT" 'an empty payload prints nothing'
  run_hook 'not json'
  assert_status 0 'a payload without JSON passes'
}

test_src_on_master_warns() {
  sandbox_new
  project_on_branch
  run_hook "$(payload_for "$PROJECT" "$PROJECT/src/app/code/Vendor/Module/Model/Thing.php")"
  assert_status 0 'the write is allowed'
  assert_contains 'src/ is on master' 'a reminder names the branch' "$(context)"
  if [[ "$OUTPUT" == *'"deny"'* ]]; then
    fail_ 'the write is not denied' "$OUTPUT"
  else
    pass_ 'the write is not denied'
  fi
}

test_src_on_a_feature_branch_is_silent() {
  sandbox_new
  project_on_branch feat/thing
  run_hook "$(payload_for "$PROJECT" "$PROJECT/src/app/code/Vendor/Module/Model/Thing.php")"
  assert_equals '' "$OUTPUT" 'a feature branch gets no reminder'
}

test_worktree_paths_are_not_the_served_src() {
  sandbox_new
  project_on_branch
  mkdir -p "$PROJECT/.worktrees/feat-thing/app/code"
  run_hook "$(payload_for "$PROJECT" "$PROJECT/.worktrees/feat-thing/app/code/A.php")"
  assert_equals '' "$OUTPUT" 'a worktree path gets no reminder'
}

run_tests
finish
