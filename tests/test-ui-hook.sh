#!/usr/bin/env bash
# agents/hooks/ui-conventions.sh <rules path>: PreToolUse hook that injects the UI rules
# when an edit targets a UI file. Silent for other files, full text once per session then
# a one-line reminder, Claude (file_path) and Codex (apply_patch) inputs, rules looked up
# in the edited checkout then in <project>/src, a warning on stderr when they are missing.
#
# Usage:  bash tests/test-ui-hook.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

HOOK="$REPO_ROOT/agents/hooks/ui-conventions.sh"
RULES='docs/agents/ui-conventions.md'

new_project() {
  sandbox_new
  PROJECT="$SANDBOX/project"
  mkdir -p "$PROJECT/src/docs/agents" "$PROJECT/.worktrees/feat-x/docs/agents"
  printf 'SRC RULES\n' > "$PROJECT/src/$RULES"
  export TMPDIR="$SANDBOX/tmp"
  mkdir -p "$TMPDIR"
}

# hook <session> <json tool_input> [rules arg]
hook() {
  local sid="$1" tool_input="$2" arg="${3-$RULES}" json
  json="$(jq -n --arg s "$sid" --arg c "$PROJECT" --argjson t "$tool_input" '{session_id:$s, cwd:$c, tool_input:$t}')"
  local err="$SANDBOX/stderr"
  if OUTPUT="$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PROJECT" "$HOOK" ${arg:+"$arg"} 2> "$err")"; then
    STATUS=0
  else
    STATUS=$?
  fi
  STDERR="$(cat "$err")"
}

context() { jq -r '.hookSpecificOutput.additionalContext' <<< "$OUTPUT"; }

test_non_ui_file_is_silent() {
  new_project
  hook s1 "{\"file_path\":\"$PROJECT/src/app/code/V/M/Model/Foo.php\"}"
  assert_status 0 'a PHP model exits 0'
  assert_equals '' "$OUTPUT" 'a PHP model gets no output'
  hook s1 "{\"file_path\":\"$PROJECT/src/app/code/V/M/Test/Unit/view/x.phtml\"}"
  assert_equals '' "$OUTPUT" 'a test file is not a UI file'
}

test_ui_file_full_text_then_reminder() {
  new_project
  hook s2 "{\"file_path\":\"$PROJECT/src/app/code/V/M/view/frontend/templates/a.phtml\"}"
  assert_status 0 'a template exits 0'
  assert_equals 'PreToolUse' "$(jq -r '.hookSpecificOutput.hookEventName' <<< "$OUTPUT")" 'the output is a PreToolUse context'
  assert_contains 'SRC RULES' 'the first edit gets the full rules' "$(context)"
  hook s2 "{\"file_path\":\"$PROJECT/src/app/code/V/M/view/frontend/web/css/source/_x.less\"}"
  assert_not_contains 'SRC RULES' 'the second edit in the session gets a reminder only' "$(context)"
  assert_contains "$RULES" 'the reminder names the rules file' "$(context)"
  hook s3 "{\"file_path\":\"$PROJECT/src/app/design/frontend/V/t/web/css/a.less\"}"
  assert_contains 'SRC RULES' 'another session gets the full text again' "$(context)"
}

test_rules_of_the_edited_worktree_win() {
  new_project
  printf 'WT RULES\n' > "$PROJECT/.worktrees/feat-x/$RULES"
  hook s4 "{\"file_path\":\"$PROJECT/.worktrees/feat-x/app/code/V/M/view/adminhtml/ui_component/f.xml\"}"
  assert_contains 'WT RULES' 'the worktree rules are used' "$(context)"
  rm "$PROJECT/.worktrees/feat-x/$RULES"
  hook s5 "{\"file_path\":\"$PROJECT/.worktrees/feat-x/app/code/V/M/view/adminhtml/ui_component/f.xml\"}"
  assert_contains 'SRC RULES' 'falls back to <project>/src' "$(context)"
}

test_codex_apply_patch() {
  new_project
  local patch='*** Begin Patch\n*** Update File: src/app/code/V/M/view/frontend/templates/b.phtml\n*** End Patch'
  hook s6 "{\"command\":\"$patch\"}"
  assert_contains 'SRC RULES' 'a relative path in apply_patch resolves against cwd' "$(context)"
}

test_missing_rules_and_argument_fail_loudly() {
  new_project
  rm "$PROJECT/src/$RULES"
  hook s7 "{\"file_path\":\"$PROJECT/src/app/code/V/M/view/frontend/templates/a.phtml\"}"
  assert_status 0 'missing rules do not block the edit'
  assert_equals '' "$OUTPUT" 'missing rules inject nothing'
  assert_contains "$RULES" 'missing rules print a warning on stderr' "$STDERR"
  hook s8 "{\"file_path\":\"$PROJECT/src/app/code/V/M/view/frontend/templates/a.phtml\"}" ''
  assert_status 1 'a missing argument is a non-blocking error'
  assert_contains 'Usage' 'the usage is printed' "$STDERR"
}

run_tests
finish
