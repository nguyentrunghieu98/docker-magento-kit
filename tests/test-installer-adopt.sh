#!/usr/bin/env bash
# Test S1 cho `install.sh adopt`: Docker root giả lập kiểu Format (markshust đã
# sửa tay: MySQL 8.0.45, Redis cổng 6378, service tunnel, image PHP tự build,
# file lạ), nhận bằng --source, không cần mạng. Tự dựng fixture, không đọc dự án thật.
#
# Usage:  bash tests/test-installer-adopt.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

DIST="$KIT_REPO_ROOT/dist"

# compose.yaml kiểu Format: có phần comment chứa giá trị khác để thử parser.
write_format_compose() {
  cat > "$1" <<'YAML'
services:
  app:
    image: markoshust/magento-nginx:1.24-0
    ports:
      - "80:8000"
      - "443:8443"
  phpfpm:
    image: format/magento-php:8.2.35-fpm
    build:
      context: ./images/php/8.2
  # db:
  #   image: mariadb:11.4
  #   ports:
  #     - "3307:3306"
  db:
   image: mysql:8.0.45
   ports:
     - "3306:3306"
  # redis:
  #   image: valkey/valkey:8.1-alpine
  redis:
   image: redis:7.2-alpine
   ports:
     - "6378:6379"
  opensearch:
    image: markoshust/magento-opensearch:2.12-0
    ports:
      - "9200:9200"
    environment:
      - "discovery.type=single-node"
      - "OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g"
  rabbitmq:
    image: markoshust/magento-rabbitmq:4.1-0
    ports:
      - "15672:15672"
      - "5672:5672"
  tunnel:
   container_name: cloudflared-tunnel
   image: cloudflare/cloudflared:latest
   command: tunnel --protocol http2 --retries 2 run
volumes:
  dbdata:
YAML
}

# Dựng $SANDBOX/format: mọi file của gói đúng bản kit, trừ compose.yaml (sửa
# tay), bin/setup (sửa tay) và bin/wt (chưa có). Kèm template tùy biến, file lạ,
# src/ là clone git với remote tên `orgin`, .worktrees/ và .active-src.
fixture_format() {
  local root="$SANDBOX/${1:-format}"
  mkdir -p "$root"
  cp -a "$DIST/files/." "$root/"
  write_format_compose "$root/compose.yaml"
  printf '\n# sửa tay\nexport FOO=1\n' >> "$root/bin/setup"
  rm -f "$root/bin/wt"
  mkdir -p "$root/env" "$root/images/php/8.2" "$root/src" "$root/.worktrees/feat-x"
  printf 'MYSQL_ROOT_PASSWORD=doi-roi\n' > "$root/env/db.env"
  printf 'FROM php:8.2-fpm\n' > "$root/images/php/8.2/dockerfile"
  printf 'echo hi\n' > "$root/deploy-format.sh"
  printf 'x\n' > "$root/.worktrees/feat-x/file"
  printf '%s\n' "$root/.worktrees/feat-x" > "$root/.active-src"
  git_remote_new
  rm -rf "$root/src"
  git clone -q -o orgin "$BARE_REMOTE" "$root/src"
  printf 'mới\n' > "$root/src/untracked.txt"
  FIXTURE="$root"
}

adopt() {
  run_installer adopt "$FIXTURE" --source "$KIT_REPO_ROOT" "$@"
}

# Đưa file của gói về đúng bản gói, như khi người dùng đã chuyển phần tùy biến đi.
restore_pkg_file() {
  cp -p "$DIST/files/$1" "$FIXTURE/$1"
}

untouchable_digest() {
  tree_digest "$FIXTURE/src"
  tree_digest "$FIXTURE/.worktrees"
  cat "$FIXTURE/.active-src"
  git -C "$FIXTURE/src" status --porcelain
}

test_adopt_dry_run_lists_conflicts_and_writes_nothing() {
  sandbox_new
  fixture_format
  local before after
  before="$(tree_digest "$FIXTURE")"
  adopt --dry-run
  assert_status 1 'adopt reports conflicts with a non-zero exit'
  assert_contains 'XUNG ĐỘT: compose.yaml' 'compose.yaml is an update conflict'
  assert_contains 'XUNG ĐỘT: bin/setup' 'a hand-edited bin script is an update conflict'
  assert_equals 2 "$(grep -c 'XUNG ĐỘT' <<< "$OUTPUT")" 'exactly the two edited package files conflict'
  assert_not_contains 'XUNG ĐỘT: bin/start' 'an identical package file is not a conflict'
  assert_contains 'compose.override.yaml' 'the compose conflict hints at compose.override.yaml'
  assert_contains 'project/bin/' 'the bin conflict hints at project/bin/'
  assert_contains 'project/profile.env' 'conflict hints name the profile file'
  assert_contains 'ghi mới: bin/wt' 'a missing package file is planned as a write'
  assert_contains 'images/' 'stray directory images/ is reported'
  assert_contains 'deploy-format.sh' 'stray file is reported'
  assert_not_contains '  env/db.env' 'a template target that exists is not reported as stray'
  assert_not_contains '.worktrees' 'adopt does not list .worktrees/'
  assert_not_contains '  src/' 'adopt does not list src/'
  after="$(tree_digest "$FIXTURE")"
  assert_equals "$before" "$after" 'adopt with conflicts writes nothing'
  assert_absent "$FIXTURE/.kit" 'no .kit state while conflicts remain'
  assert_docker_not_called 'adopt never calls docker'
}

test_adopt_guesses_profile_keys() {
  sandbox_new
  fixture_format
  adopt --dry-run
  assert_contains 'KIT_PROJECT_NAME=format' 'preview shows the project name from the directory'
  assert_contains 'KIT_DB_ENGINE=mysql' 'preview shows the DB engine'
  assert_contains 'KIT_DB_VERSION=8.0.45' 'preview shows the DB version'
  assert_contains 'KIT_REDIS_PORT=6378' 'preview shows the Redis port'
  assert_not_contains 'KIT_DB_PORT=3307' 'commented-out compose lines are not parsed'
}

test_adopt_without_force_stops_and_round_trips() {
  sandbox_new
  fixture_format
  adopt
  assert_status 1 'a first round with conflicts stops'
  assert_absent "$FIXTURE/.kit/manifest" 'no manifest after a stopped round'
  restore_pkg_file bin/setup
  adopt
  assert_status 1 'a second round with one conflict left still stops'
  assert_equals 1 "$(grep -c 'XUNG ĐỘT: ' <<< "$OUTPUT")" 'the conflict list shrinks as customizations move out'
  restore_pkg_file compose.yaml
  adopt
  assert_status 0 'adopt succeeds once no conflict is left'
  assert_file "$FIXTURE/.kit/manifest" 'manifest is written'
  assert_files_equal "$DIST/manifest" "$FIXTURE/.kit/manifest" 'manifest equals the release manifest'
  assert_file "$FIXTURE/bin/wt" 'a missing package file is written'
  assert_executable "$FIXTURE/bin/wt" 'written package file keeps its mode'
  assert_docker_not_called 'adopt never calls docker'
}

test_adopt_writes_guessed_profile() {
  sandbox_new
  fixture_format
  adopt --force
  assert_status 0 'adopt --force succeeds'
  local profile="$FIXTURE/project/profile.env"
  assert_file "$profile" 'profile is created from the template'
  assert_file_line "$profile" 'KIT_PROJECT_NAME=format  # adopt đoán, kiểm tra lại' 'project name guessed from the directory'
  assert_file_line "$profile" 'KIT_GIT_REMOTE=orgin  # adopt đoán, kiểm tra lại' 'Git remote guessed from src/'
  assert_file_line "$profile" 'KIT_GIT_BASE_BRANCH=master  # adopt đoán, kiểm tra lại' 'base branch guessed'
  assert_file_line "$profile" 'KIT_GIT_TARGET_BRANCH=staging  # adopt đoán, kiểm tra lại' 'target branch guessed'
  assert_file_line "$profile" 'KIT_PHP_VERSION=8.2  # adopt đoán, kiểm tra lại' 'PHP version from the phpfpm image'
  assert_file_line "$profile" 'KIT_DB_ENGINE=mysql  # adopt đoán, kiểm tra lại' 'DB engine from compose.yaml'
  assert_file_line "$profile" 'KIT_DB_VERSION=8.0.45  # adopt đoán, kiểm tra lại' 'DB version from compose.yaml'
  assert_file_line "$profile" 'KIT_REDIS_IMAGE=redis:7.2-alpine  # adopt đoán, kiểm tra lại' 'Redis image from compose.yaml'
  assert_file_line "$profile" 'KIT_REDIS_PORT=6378  # adopt đoán, kiểm tra lại' 'Redis host port from compose.yaml'
  assert_file_line "$profile" 'KIT_HTTPS_PORT=443  # adopt đoán, kiểm tra lại' 'HTTPS port from compose.yaml'
  assert_file_line "$profile" 'KIT_OPENSEARCH_HEAP=2g  # adopt đoán, kiểm tra lại' 'OpenSearch heap from compose.yaml'
  assert_file_line "$profile" 'KIT_DOMAIN=' 'KIT_DOMAIN stays empty'
  assert_file_line_count 0 "$profile" '^KIT_DB_PORT=3307' 'no value comes from commented lines'
  assert_file_does_not_match "$profile" '^KIT_COMPOSE_PROFILES=' 'cloudflared profile is not guessed'
  assert_docker_not_called 'adopt never calls docker'
}

test_adopt_force_backs_up_conflicts() {
  sandbox_new
  fixture_format
  adopt --force
  assert_status 0 'adopt --force exits 0'
  local backup
  backup="$(find "$FIXTURE/.kit/backup" -name compose.yaml | head -n 1)"
  assert_file_line "$backup" '  tunnel:' 'the hand-edited compose.yaml was backed up'
  assert_file_line "$(find "$FIXTURE/.kit/backup" -name setup | head -n 1)" 'export FOO=1' 'the hand-edited bin/setup was backed up'
  assert_files_equal "$DIST/files/compose.yaml" "$FIXTURE/compose.yaml" 'compose.yaml now matches the package'
  assert_files_equal "$DIST/manifest" "$FIXTURE/.kit/manifest" 'manifest equals the release manifest'
}

test_adopt_keeps_project_state_and_files() {
  sandbox_new
  fixture_format
  local before after
  before="$(untouchable_digest)"
  adopt --force
  after="$(untouchable_digest)"
  assert_equals "$before" "$after" 'src/, .worktrees/ and .active-src are untouched'
  assert_file_line "$FIXTURE/env/db.env" 'MYSQL_ROOT_PASSWORD=doi-roi' 'an existing template target is kept'
  assert_file "$FIXTURE/images/php/8.2/dockerfile" 'stray directory is not removed'
  assert_file "$FIXTURE/deploy-format.sh" 'stray file is not removed'
  assert_docker_not_called 'adopt never calls docker'
}

test_adopt_keeps_existing_profile() {
  sandbox_new
  fixture_format
  mkdir -p "$FIXTURE/project"
  printf 'KIT_PROJECT_NAME=giu-nguyen\n' > "$FIXTURE/project/profile.env"
  adopt --force
  assert_status 0 'adopt succeeds with an existing profile'
  assert_equals 'KIT_PROJECT_NAME=giu-nguyen' "$(cat "$FIXTURE/project/profile.env")" 'an existing profile is never touched'
}

test_adopt_git_keys_need_unambiguous_remote() {
  sandbox_new
  fixture_format
  git -C "$FIXTURE/src" remote add other "$BARE_REMOTE"
  adopt --force
  assert_status 0 'adopt succeeds with two remotes'
  assert_file_line "$FIXTURE/project/profile.env" 'KIT_GIT_REMOTE=' 'two remotes: Git keys are left empty'
  assert_file_does_not_match "$FIXTURE/project/profile.env" '^KIT_GIT_BASE_BRANCH=.*adopt' 'two remotes: base branch is not guessed'

  sandbox_new
  fixture_format
  git -C "$FIXTURE/src" push -q orgin --delete staging
  git -C "$FIXTURE/src" fetch -q --prune orgin
  adopt --force
  assert_file_line "$FIXTURE/project/profile.env" 'KIT_GIT_TARGET_BRANCH=' 'no staging branch: Git keys are left empty'
  assert_file_does_not_match "$FIXTURE/project/profile.env" '^KIT_GIT_REMOTE=.*adopt' 'no staging branch: remote is not guessed'
}

test_adopt_then_self_update_is_clean() {
  sandbox_new
  fixture_format
  adopt --force
  run_in "$FIXTURE" bin/self-update --source "$KIT_REPO_ROOT" --dry-run
  assert_status 0 'self-update right after adopt has no conflict'
  assert_not_contains 'XUNG ĐỘT' 'self-update reports no conflict'
}

test_adopt_refuses_managed_root_and_non_root() {
  sandbox_new
  kit_new shop
  run_installer adopt "$SANDBOX/shop" --source "$KIT_REPO_ROOT"
  assert_status_nonzero 'adopt refuses a root that is already managed'
  assert_contains 'self-update' 'the refusal points to bin/self-update'
  mkdir -p "$SANDBOX/empty"
  run_installer adopt "$SANDBOX/empty" --source "$KIT_REPO_ROOT"
  assert_status_nonzero 'adopt refuses a directory without compose.yaml'
  run_installer adopt "$SANDBOX/khong-co" --source "$KIT_REPO_ROOT"
  assert_status_nonzero 'adopt refuses a missing directory'
  run_installer adopt "$SANDBOX/shop" --domain x.test --source "$KIT_REPO_ROOT"
  assert_status_nonzero 'adopt does not take --domain'
}

run_tests
finish
