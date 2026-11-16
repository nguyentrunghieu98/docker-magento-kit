#!/usr/bin/env bash
# sync: report drift between the kit and a Docker root, copy on --apply, never
# delete, never write through a symlink.
#
# Usage:  bash tests/test-sync.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

new_target() {
  sandbox_new
  TARGET="$SANDBOX/project"
  mkdir -p "$TARGET"
}

sync_in_target() {
  run_in "$TARGET" "$REPO_ROOT/sync" "$@"
}

test_report_lists_missing_files() {
  new_target
  sync_in_target
  assert_status 1 'a fresh target reports drift'
  assert_contains 'A  bin/wt' 'the docker overlay maps onto the target root'
  assert_contains 'A  src/.agents/skills/plan-create/SKILL.md' 'agents/ maps onto src/.agents/'
  assert_contains 'A  src/.agents/agents/tdd-worker.md' 'the roles are part of the overlay'
  assert_contains 'unchanged' 'the summary counts unchanged files'
}

test_apply_copies_the_overlay() {
  new_target
  sync_in_target --apply
  assert_status 0 '--apply exits 0'
  assert_files_equal "$REPO_ROOT/docker/bin/wt" "$TARGET/bin/wt" 'bin/wt is copied'
  assert_files_equal "$REPO_ROOT/agents/hooks/ui-conventions.sh" \
    "$TARGET/src/.agents/hooks/ui-conventions.sh" 'the hook is copied'
  assert_files_equal "$REPO_ROOT/agents/agents/tdd-worker.md" \
    "$TARGET/src/.agents/agents/tdd-worker.md" 'a role is copied'
}

test_apply_keeps_the_executable_bit() {
  new_target
  sync_in_target --apply
  if [[ -x "$TARGET/bin/wt" && -x "$TARGET/src/.agents/hooks/ui-conventions.sh" ]]; then
    pass_ 'scripts stay executable after the copy'
  else
    fail_ 'scripts stay executable after the copy' "$(ls -l "$TARGET/bin/wt" "$TARGET/src/.agents/hooks/ui-conventions.sh" 2>&1)"
  fi
}

test_synced_target_is_clean() {
  new_target
  sync_in_target --apply
  sync_in_target
  assert_status 0 'a synced target exits 0'
  assert_contains '0 added, 0 changed' 'nothing is reported after a sync'
}

test_local_change_is_reported_and_replaced() {
  new_target
  sync_in_target --apply
  printf '\n# local edit\n' >> "$TARGET/bin/watch"
  sync_in_target
  assert_status 1 'a modified file reports drift'
  assert_contains 'M  bin/watch' 'the changed file is listed'
  sync_in_target --apply
  assert_files_equal "$REPO_ROOT/docker/bin/watch" "$TARGET/bin/watch" '--apply restores the kit version'
}

test_symlink_at_the_destination_is_not_written_through() {
  new_target
  sync_in_target --apply
  rm "$TARGET/bin/watch"
  ln -s "$SANDBOX/keep" "$TARGET/bin/watch"
  sync_in_target
  assert_status 1 'a symlink at the destination is a conflict'
  assert_contains 'X  bin/watch' 'the conflict is listed'
  sync_in_target --apply
  assert_status 1 '--apply reports the skipped conflict'
  assert_symlink_to "$TARGET/bin/watch" "$SANDBOX/keep" 'the symlink is left alone'
}

test_quiet_prints_only_the_summary() {
  new_target
  sync_in_target --quiet
  assert_contains 'added' 'the summary is printed'
  if [[ "$OUTPUT" == *'A  bin/wt'* ]]; then
    fail_ '--quiet hides the file list' "$OUTPUT"
  else
    pass_ '--quiet hides the file list'
  fi
}

test_missing_and_unsafe_targets() {
  new_target
  sync_in_target --target "$SANDBOX/nope"
  assert_status 2 'a missing target is a usage error'
  sync_in_target --target "$REPO_ROOT"
  assert_status 2 'the kit itself is refused as a target'
}

test_skip_leaves_one_file_alone() {
  new_target
  sync_in_target --skip compose.worktree.yaml
  assert_status 1 'the rest of the overlay is still reported'
  assert_contains '1 skipped' 'the skipped count is in the summary'
  if [[ "$OUTPUT" == *'A  compose.worktree.yaml'* ]]; then
    fail_ '--skip hides that file from the report' "$OUTPUT"
  else
    pass_ '--skip hides that file from the report'
  fi
  sync_in_target --apply --skip compose.worktree.yaml
  if [[ -e "$TARGET/compose.worktree.yaml" ]]; then
    fail_ '--skip does not copy that file' 'the file exists after --apply'
  else
    pass_ '--skip does not copy that file'
  fi
  if [[ -f "$TARGET/bin/wt" ]]; then
    pass_ 'the other files are still copied'
  else
    fail_ 'the other files are still copied' 'bin/wt is missing in the target'
  fi
}

run_tests
finish
