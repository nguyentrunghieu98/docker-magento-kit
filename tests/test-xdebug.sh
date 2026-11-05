#!/usr/bin/env bash
# S1 tests for bin/xdebug: runtime state and the recreate command in the docker log.
#
# Usage:  bash tests/test-xdebug.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

new_root() {
  sandbox_new
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then exit 0; fi
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
  kit_new shop >/dev/null
  ROOT="$SANDBOX/shop"
  printf 'KIT_PROJECT_NAME=shop\nKIT_PHP_VERSION=8.2\n' > "$ROOT/project/profile.env"
}

xdebug() { reset_calls; run_in "$ROOT" "$ROOT/bin/xdebug" "$@"; }

test_status_defaults_to_off() {
  new_root
  xdebug
  assert_status 0 'status exits 0'
  assert_contains 'Xdebug: off' 'no runtime file means off'
  assert_docker_not_called 'status does not call docker'
  assert_absent "$ROOT/.kit/runtime.env" 'status writes nothing'
}

test_on_writes_runtime_and_recreates_phpfpm() {
  new_root
  xdebug on
  assert_status 0 'on exits 0'
  assert_file_line "$ROOT/.kit/runtime.env" 'KIT_PHP_VARIANT=-xdebug' 'runtime.env holds the -xdebug variant'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' up -d --no-deps --force-recreate phpfpm$' 'only phpfpm is recreated'
  assert_file_line_count 1 "$KIT_LOG_DIR/docker.log" 'phpfpm' 'one docker call'
  xdebug
  assert_contains 'Xdebug: on' 'status reports on'
}

test_off_writes_empty_value_and_recreates() {
  new_root
  xdebug on
  xdebug off
  assert_status 0 'off exits 0'
  assert_file_line "$ROOT/.kit/runtime.env" 'KIT_PHP_VARIANT=' 'runtime.env holds an empty variant'
  assert_file_line_count 1 "$ROOT/.kit/runtime.env" '^KIT_PHP_VARIANT=' 'a single KIT_PHP_VARIANT line'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' up -d --no-deps --force-recreate phpfpm$' 'phpfpm is recreated again'
  xdebug
  assert_contains 'Xdebug: off' 'status reports off'
}

test_other_runtime_keys_are_kept() {
  new_root
  mkdir -p "$ROOT/.kit"
  printf 'KIT_HTTP_PORT=8081\n' > "$ROOT/.kit/runtime.env"
  xdebug on
  assert_file_line "$ROOT/.kit/runtime.env" 'KIT_HTTP_PORT=8081' 'other runtime keys survive'
}

test_invalid_argument() {
  new_root
  xdebug debug
  assert_status_nonzero 'unknown mode is refused'
  assert_docker_not_called 'nothing recreated'
  assert_absent "$ROOT/.kit/runtime.env" 'nothing written'
}

test_no_php_ini_editing() {
  new_root
  assert_file_does_not_match "$ROOT/bin/xdebug" 'php\.ini|xdebug\.mode|USR2' 'bin/xdebug no longer edits php.ini in the container'
}

test_runtime_env_ignored_and_outside_manifest() {
  new_root
  assert_file_line "$ROOT/.gitignore" '.kit/runtime.env' '.gitignore ignores runtime.env'
  assert_file_does_not_match "$ROOT/.kit/manifest" 'runtime\.env' 'runtime.env is not in the manifest'
}

run_tests
finish
