#!/usr/bin/env bash
# Test cho chính thư viện tests/lib.sh: docker giả, bare remote, assert_*.
#
# Usage:  bash tests/test-lib.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

test_fake_docker_logs_every_call() {
  sandbox_new
  docker ps -a
  docker compose up -d
  assert_docker_called 'docker ps -a' 'the fake docker records ps'
  assert_docker_called 'docker compose up -d' 'the fake docker records compose up'
  assert_equals "$SANDBOX/.fakebin/docker" "$(command -v docker)" 'the fake docker shadows the real one on PATH'
}

test_fake_docker_info_follows_online_flag() {
  sandbox_new
  assert_cmd_status 1 'docker info fails while offline' docker info
  set_docker_online
  assert_cmd_status 0 'docker info succeeds while online' docker info
  set_docker_offline
  assert_cmd_status 1 'docker info fails again once offline' docker info
}

test_reset_calls_clears_logs() {
  sandbox_new
  docker ps
  reset_calls
  assert_docker_not_called 'reset_calls clears the docker log'
}

test_bare_remote_has_master_and_staging() {
  sandbox_new
  git_remote_new
  local heads
  heads="$(git ls-remote --heads "$BARE_REMOTE" | awk '{print $2}' | LC_ALL=C sort | tr '\n' ' ')"
  assert_equals 'refs/heads/master refs/heads/staging ' "$heads" 'the bare remote has exactly master and staging'
  git clone -q "$BARE_REMOTE" "$SANDBOX/clone"
  assert_file "$SANDBOX/clone/README" 'the bare remote is cloneable'
}

test_sandboxes_are_isolated() {
  sandbox_new
  local first="$SANDBOX"
  sandbox_new
  assert_equals 'different' "$([[ "$first" != "$SANDBOX" ]] && echo different || echo same)" 'each sandbox_new gives a new directory'
}

test_asserts_report_failures() {
  local fails_before="$FAILED" checks_before="$CHECKS"
  assert_equals a b 'deliberate failure' >/dev/null
  local delta=$((FAILED - fails_before))
  # hoàn tác lỗi cố ý để bộ test này không tự đỏ
  FAILED=$((FAILED - delta))
  CHECKS=$((checks_before))
  pass_ 'a failing assert increments the failure counter'
  [[ "$delta" -eq 1 ]] || fail_ 'a failing assert counts exactly one failure' "delta=$delta"
}

run_tests
finish
