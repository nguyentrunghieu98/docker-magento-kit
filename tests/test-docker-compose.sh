#!/usr/bin/env bash
# S1 test for bin/docker-compose: arguments are assembled correctly per DB engine, override,
# worktree overlay and runtime state. The fake Docker records arguments and environment.
#
# Usage:  bash tests/test-docker-compose.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# The fake Docker records arguments in docker.log and related variables in docker.env.
install_recording_docker() {
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then exit 0; fi
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
env | grep -E '^(KIT_|COMPOSE_PROFILES|LOAD_DEV_FILES)' | LC_ALL=C sort > "${KIT_LOG_DIR:?}/docker.env" || true
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
}

# Fake uname to test both the Linux and Darwin branches.
install_uname() {
  printf '#!/usr/bin/env bash\necho %s\n' "$1" > "$SANDBOX/.fakebin/uname"
  chmod 755 "$SANDBOX/.fakebin/uname"
}

new_root() {
  sandbox_new
  install_recording_docker
  install_uname Linux
  kit_new shop >/dev/null
  ROOT="$SANDBOX/shop"
}

compose() {
  reset_calls
  run_in "$SANDBOX" "$ROOT/bin/docker-compose" "$@"
}

# The list of -f files in order, on one line.
files_called() {
  grep -Eo ' -f [^ ]+' "$KIT_LOG_DIR/docker.log" | sed 's/^ -f //' | tr '\n' ' ' | sed 's/ $//'
}

called_line() { cat "$KIT_LOG_DIR/docker.log"; }
env_dump() { cat "$KIT_LOG_DIR/docker.env"; }

test_default_order_mariadb() {
  new_root
  compose ps
  assert_status 0 'wrapper exits 0'
  assert_equals 'compose.yaml compose.db-mariadb.yaml compose.healthcheck.yaml compose.dev.yaml compose.dev-linux.yaml' \
    "$(files_called)" 'default engine loads base, mariadb file, healthcheck, dev and the Linux file'
  assert_contains 'docker compose -p shop ' 'passes -p with the directory-derived project name' "$(called_line)"
  assert_contains ' ps' 'forwards the remaining arguments' "$(called_line)"
}

test_mysql_engine() {
  new_root
  printf 'KIT_DB_ENGINE=mysql\nKIT_DB_VERSION=8.0.45\n' > "$ROOT/project/profile.env"
  compose config
  assert_equals 'compose.yaml compose.db-mysql.yaml compose.healthcheck.yaml compose.dev.yaml compose.dev-linux.yaml' \
    "$(files_called)" 'mysql engine swaps the DB file'
  assert_contains 'KIT_DB_ENGINE=mysql' 'exports the engine' "$(env_dump)"
  assert_contains 'KIT_DB_VERSION=8.0.45' 'exports the version' "$(env_dump)"
}

test_bad_engine_is_rejected() {
  new_root
  printf 'KIT_DB_ENGINE=postgres\n' > "$ROOT/project/profile.env"
  compose config
  assert_status_nonzero 'unknown engine fails'
  assert_contains 'KIT_DB_ENGINE' 'names the key'
  assert_docker_not_called 'docker is not called for a bad engine'
}

test_project_name_from_profile() {
  new_root
  printf 'KIT_PROJECT_NAME=format\n' > "$ROOT/project/profile.env"
  compose up -d
  assert_contains 'docker compose -p format ' 'KIT_PROJECT_NAME becomes -p' "$(called_line)"
}

test_non_linux_skips_linux_file() {
  new_root
  install_uname Darwin
  compose config
  assert_equals 'compose.yaml compose.db-mariadb.yaml compose.healthcheck.yaml compose.dev.yaml' \
    "$(files_called)" 'the Linux file is not loaded on Darwin'
}

test_override_is_last() {
  new_root
  : > "$ROOT/compose.override.yaml"
  compose config
  assert_equals 'compose.yaml compose.db-mariadb.yaml compose.healthcheck.yaml compose.dev.yaml compose.dev-linux.yaml compose.override.yaml' \
    "$(files_called)" 'compose.override.yaml is loaded last when present'
}

test_worktree_overlay_requires_symlink() {
  new_root
  mkdir -p "$ROOT/src"
  compose config
  assert_not_contains 'compose.worktree.yaml' 'no overlay without .active-src' "$(called_line)"
  mkdir "$ROOT/.active-src"
  compose config
  assert_not_contains 'compose.worktree.yaml' 'a plain directory is not an overlay trigger' "$(called_line)"
  rmdir "$ROOT/.active-src"
  ln -s src "$ROOT/.active-src"
  : > "$ROOT/compose.override.yaml"
  compose config
  assert_equals 'compose.yaml compose.db-mariadb.yaml compose.healthcheck.yaml compose.dev.yaml compose.dev-linux.yaml compose.worktree.yaml compose.override.yaml' \
    "$(files_called)" 'overlay comes after dev and Linux files, before the override'
}

test_no_dev() {
  new_root
  ln -s src "$ROOT/.active-src"
  compose --no-dev config
  assert_equals 'compose.yaml compose.db-mariadb.yaml compose.healthcheck.yaml' "$(files_called)" '--no-dev drops dev, Linux and overlay files'
  assert_not_contains '--no-dev' '--no-dev is not forwarded to docker compose' "$(called_line)"
  assert_contains 'LOAD_DEV_FILES=0' '--no-dev sets LOAD_DEV_FILES=0' "$(env_dump)"
}

test_env_is_exported() {
  new_root
  cat > "$ROOT/project/profile.env" <<'PROFILE'
KIT_COMPOSE_PROFILES=cloudflared
KIT_REDIS_IMAGE=redis:7.2-alpine
KIT_REDIS_PORT=6378
KIT_OPENSEARCH_HEAP=2g
PROFILE
  KIT_PHP_VERSION=ambient COMPOSE_PROFILES=ambient compose config
  local dump
  dump="$(env_dump)"
  assert_contains 'COMPOSE_PROFILES=cloudflared' 'KIT_COMPOSE_PROFILES becomes COMPOSE_PROFILES' "$dump"
  assert_contains 'LOAD_DEV_FILES=1' 'LOAD_DEV_FILES=1 in dev mode' "$dump"
  assert_contains 'KIT_REDIS_IMAGE=redis:7.2-alpine' 'redis image exported' "$dump"
  assert_contains 'KIT_REDIS_PORT=6378' 'redis port exported' "$dump"
  assert_contains 'KIT_OPENSEARCH_HEAP=2g' 'heap exported' "$dump"
  assert_contains 'KIT_PHP_VERSION=8.3' 'default exported and ambient value ignored' "$dump"
  assert_contains 'KIT_DB_PORT=3306' 'defaults exported for unset keys' "$dump"
}

test_runtime_env_after_profile() {
  new_root
  printf 'KIT_PHP_VARIANT=\n' > "$ROOT/project/profile.env"
  printf 'KIT_PHP_VARIANT=-xdebug\n' > "$ROOT/.kit/runtime.env"
  compose config
  assert_contains 'KIT_PHP_VARIANT=-xdebug' 'runtime state wins over the profile' "$(env_dump)"
  rm "$ROOT/.kit/runtime.env"
  compose config
  assert_not_contains 'KIT_PHP_VARIANT=-xdebug' 'no runtime state, no variant' "$(env_dump)"
}

test_bad_profile_stops_before_docker() {
  new_root
  printf 'KIT_DOMAIN="x.test"\n' > "$ROOT/project/profile.env"
  compose config
  assert_status_nonzero 'a quoted value fails the wrapper'
  assert_contains 'profile.env:1' 'reports the offending line'
  assert_docker_not_called 'docker is not called'
}

test_works_from_any_directory() {
  new_root
  mkdir "$SANDBOX/elsewhere"
  reset_calls
  run_in "$SANDBOX/elsewhere" "$ROOT/bin/docker-compose" config
  assert_status 0 'running from another directory works'
  assert_contains 'docker compose -p shop ' 'still resolves the project from the Docker root' "$(called_line)"
}

test_db_files_carry_required_flags() {
  local engine
  for engine in mariadb mysql; do
    assert_file_matches "$KIT_REPO_ROOT/dist/files/compose.db-$engine.yaml" '^  db:$' "compose.db-$engine.yaml defines service db"
    assert_file_matches "$KIT_REPO_ROOT/dist/files/compose.db-$engine.yaml" '--max_allowed_packet=64M' "compose.db-$engine.yaml sets max_allowed_packet"
    assert_file_matches "$KIT_REPO_ROOT/dist/files/compose.db-$engine.yaml" '--log_bin_trust_function_creators=1' "compose.db-$engine.yaml sets log_bin_trust_function_creators"
  done
  assert_file_does_not_match "$KIT_REPO_ROOT/dist/files/compose.yaml" '^  db:$' 'base compose.yaml has no db service'
}

run_tests
finish
