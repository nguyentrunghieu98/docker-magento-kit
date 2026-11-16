#!/usr/bin/env bash
# bin/docker-compose: upstream file list, plus compose.worktree.yaml right after
# compose.dev.yaml when .active-src is a symlink, never with --no-dev.
#
# Usage:  bash tests/test-docker-compose.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

new_root() {
  sandbox_new
  root_new shop
  mkdir -p "$ROOT/src"
}

dc() {
  reset_calls
  run_in "$ROOT" bin/docker-compose "$@"
}

last_call() { tail -n1 "$TEST_LOG_DIR/docker.log"; }

test_without_active_src_matches_upstream() {
  new_root
  dc ps
  assert_status 0 'docker-compose exits 0'
  assert_equals 'docker compose -f compose.yaml -f compose.healthcheck.yaml -f compose.dev.yaml ps' "$(last_call)" 'no overlay without .active-src'
}

test_overlay_after_dev_when_active_src_is_a_symlink() {
  new_root
  ln -s "$ROOT/src" "$ROOT/.active-src"
  printf 'services: {}\n' > "$ROOT/compose.override.yaml"
  dc ps
  assert_equals 'docker compose -f compose.yaml -f compose.healthcheck.yaml -f compose.dev.yaml -f compose.worktree.yaml -f compose.override.yaml ps' "$(last_call)" 'overlay loads after dev, override stays last'
  dc --no-dev ps
  assert_equals 'docker compose -f compose.yaml -f compose.healthcheck.yaml -f compose.override.yaml ps' "$(last_call)" '--no-dev drops dev and the overlay, keeps the override'
}

test_active_src_directory_is_not_an_overlay_trigger() {
  new_root
  mkdir "$ROOT/.active-src"
  dc ps
  assert_not_contains 'compose.worktree.yaml' 'a plain directory does not load the overlay' "$(last_call)"
}

run_tests
finish
