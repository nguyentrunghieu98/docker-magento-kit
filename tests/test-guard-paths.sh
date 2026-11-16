#!/usr/bin/env bash
# agents/hooks/guard-paths.sh: deny a write into build output, warn on the main checkout
# while it sits on a protected branch, stay silent everywhere else.
#
# Usage:  bash tests/test-guard-paths.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

new_project() { hook_project_new guard-paths.sh; }

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

# Turns the main checkout into a repository on master, or on the branch given.
project_on_branch() {
  mkdir -p "$PROJECT/app/code/Vendor/Module"
  git -c init.defaultBranch=master init -q "$PROJECT"
  git -C "$PROJECT" config user.name 'kit tests'
  git -C "$PROJECT" config user.email 'tests@example.invalid'
  git -C "$PROJECT" config commit.gpgsign false
  printf 'seed\n' > "$PROJECT/README.md"
  printf '/.scratch/\n/.agents/\n' > "$PROJECT/.gitignore"
  git -C "$PROJECT" add README.md .gitignore
  git -C "$PROJECT" commit -q -m seed
  if [[ "${1:-master}" != 'master' ]]; then
    git -C "$PROJECT" checkout -q -b "$1"
  fi
}

test_output_directories_are_denied() {
  new_project
  run_hook "$(payload_for "$SANDBOX" 'src/vendor/acme/lib/a.php')"
  assert_status 0 'a write into vendor/ does not fail the hook'
  assert_equals 'deny' "$(decision)" 'vendor/ is denied'
  assert_contains 'build output' 'the reason names the cause' "$(reason)"
}

test_generated_and_pub_static_are_denied() {
  new_project
  run_hook "$(payload_for "$SANDBOX" 'src/generated/code/a.php')"
  assert_equals 'deny' "$(decision)" 'generated/ is denied'
  run_hook "$(payload_for "$SANDBOX" 'src/pub/static/frontend/a.js')"
  assert_equals 'deny' "$(decision)" 'pub/static/ is denied'
}

test_relative_paths_resolve_against_cwd() {
  new_project
  run_hook "$(payload_for "$SANDBOX" 'vendor/a.php')"
  assert_equals 'deny' "$(decision)" 'a relative path is resolved before matching'
}

test_codex_patch_payload_is_checked() {
  new_project
  run_hook "$(patch_payload_for "$SANDBOX" 'src/generated/a.php')"
  assert_equals 'deny' "$(decision)" 'an apply_patch payload is checked too'
}

test_a_normal_source_file_is_silent() {
  new_project
  run_hook "$(payload_for "$SANDBOX" 'src/app/code/Vendor/Module/Model/Thing.php')"
  assert_status 0 'a normal file passes'
  assert_equals '' "$OUTPUT" 'a normal file prints nothing'
}

test_empty_and_invalid_payloads_are_ignored() {
  new_project
  run_hook '{}'
  assert_status 0 'an empty payload passes'
  assert_equals '' "$OUTPUT" 'an empty payload prints nothing'
  run_hook 'not json'
  assert_status 0 'a payload without JSON passes'
}

test_main_checkout_on_master_warns() {
  new_project
  project_on_branch
  run_hook "$(payload_for "$PROJECT" "$PROJECT/app/code/Vendor/Module/Model/Thing.php")"
  assert_status 0 'the write is allowed'
  assert_contains 'it is on master' 'a reminder names the branch' "$(context)"
  if [[ "$OUTPUT" == *'"deny"'* ]]; then
    fail_ 'the write is not denied' "$OUTPUT"
  else
    pass_ 'the write is not denied'
  fi
}

test_ignored_files_in_the_main_checkout_are_silent() {
  new_project
  project_on_branch
  run_hook "$(payload_for "$PROJECT" '.scratch/feature/spec.md')"
  assert_equals '' "$OUTPUT" 'a file Git ignores gets no reminder'
}

test_main_checkout_on_a_feature_branch_is_silent() {
  new_project
  project_on_branch feat/thing
  run_hook "$(payload_for "$PROJECT" "$PROJECT/app/code/Vendor/Module/Model/Thing.php")"
  assert_equals '' "$OUTPUT" 'a feature branch gets no reminder'
}

test_worktree_paths_are_not_the_main_checkout() {
  new_project
  project_on_branch
  mkdir -p "$ROOT/.worktrees/feat-thing/app/code"
  run_hook "$(payload_for "$PROJECT" "$ROOT/.worktrees/feat-thing/app/code/A.php")"
  assert_equals '' "$OUTPUT" 'a worktree path gets no reminder'
}

test_a_harness_opened_in_a_worktree_still_finds_the_main_checkout() {
  new_project
  project_on_branch
  hook_worktree_new
  run_hook "$(payload_for "$WORKTREE" "$PROJECT/app/code/Vendor/Module/Model/Thing.php")"
  assert_contains 'it is on master' 'a write to the main checkout is still reminded' "$(context)"
  run_hook "$(payload_for "$WORKTREE" 'app/code/Vendor/Module/Model/Thing.php')"
  assert_equals '' "$OUTPUT" 'a write inside the worktree gets no reminder'
}

run_tests
finish
