#!/usr/bin/env bash
# Test the profile file library (bin/lib/profile.sh) through a sandbox Docker root.
#
# Usage:  bash tests/test-profile-lib.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Load the profile in a clean shell then print the requested variables, one per line.
# An ambient KIT_* variable is set on purpose to prove it is ignored.
load_and_print() {
  local root="$1"
  shift
  # String for a subshell or a fixture, left with its literal $ character.
  # shellcheck disable=SC2016
  run_cmd env KIT_PHP_VERSION=ambient bash -c '
    source "$1/bin/lib/profile.sh"
    root="$2"; shift 2
    kit_profile_load "$root" || exit 1
    for k in "$@"; do printf "%s=[%s]\n" "$k" "${!k}"; done
  ' _ "$KIT_REPO_ROOT/dist/files" "$root" "$@"
}

new_root() {
  sandbox_new
  kit_new "${1:-shop}" >/dev/null
  ROOT="$SANDBOX/${1:-shop}"
}

write_profile() { printf '%s\n' "$@" > "$ROOT/project/profile.env"; }

test_template_has_every_key() {
  new_root
  local key
  for key in KIT_PROJECT_NAME KIT_DOMAIN KIT_GIT_REMOTE KIT_GIT_BASE_BRANCH KIT_GIT_TARGET_BRANCH \
    KIT_PHP_VERSION KIT_DB_ENGINE KIT_DB_VERSION KIT_REDIS_IMAGE KIT_HTTP_PORT KIT_HTTPS_PORT \
    KIT_DB_PORT KIT_REDIS_PORT KIT_OPENSEARCH_PORT KIT_OPENSEARCH_HEAP KIT_RABBITMQ_PORT \
    KIT_RABBITMQ_MANAGEMENT_PORT KIT_STATIC_LOCALES KIT_COMPOSE_PROFILES; do
    assert_file_matches "$ROOT/project/profile.env" "^#? ?$key=" "template lists $key"
  done
  # Required keys are empty and uncommented, keys with a default are written as comments.
  assert_file_line "$ROOT/project/profile.env" 'KIT_DOMAIN=' 'required key KIT_DOMAIN is present and empty'
  assert_file_line "$ROOT/project/profile.env" 'KIT_GIT_REMOTE=' 'required key KIT_GIT_REMOTE is present and empty'
  assert_file_line "$ROOT/project/profile.env" '# KIT_PHP_VERSION=8.3' 'default-valued key is a commented line'
  assert_file_line "$ROOT/project/profile.env" '# KIT_DB_PORT=3306' 'port default is a commented line'
}

test_defaults_when_missing() {
  new_root
  load_and_print "$ROOT" KIT_PHP_VERSION KIT_DB_ENGINE KIT_DB_VERSION KIT_REDIS_IMAGE KIT_HTTP_PORT \
    KIT_HTTPS_PORT KIT_DB_PORT KIT_REDIS_PORT KIT_OPENSEARCH_PORT KIT_OPENSEARCH_HEAP \
    KIT_RABBITMQ_PORT KIT_RABBITMQ_MANAGEMENT_PORT KIT_STATIC_LOCALES KIT_COMPOSE_PROFILES
  assert_status 0 'untouched template loads'
  assert_contains 'KIT_PHP_VERSION=[8.3]' 'PHP version default beats an ambient shell variable'
  assert_contains 'KIT_DB_ENGINE=[mariadb]' 'engine default'
  assert_contains 'KIT_DB_VERSION=[11.4]' 'mariadb version default'
  assert_contains 'KIT_REDIS_IMAGE=[valkey/valkey:8.1-alpine]' 'redis image default'
  assert_contains 'KIT_HTTP_PORT=[80]' 'http port default'
  assert_contains 'KIT_HTTPS_PORT=[443]' 'https port default'
  assert_contains 'KIT_DB_PORT=[3306]' 'db port default'
  assert_contains 'KIT_REDIS_PORT=[6379]' 'redis port default'
  assert_contains 'KIT_OPENSEARCH_PORT=[9200]' 'opensearch port default'
  assert_contains 'KIT_OPENSEARCH_HEAP=[1g]' 'opensearch heap default'
  assert_contains 'KIT_RABBITMQ_PORT=[5672]' 'rabbitmq port default'
  assert_contains 'KIT_RABBITMQ_MANAGEMENT_PORT=[15672]' 'rabbitmq management port default'
  assert_contains 'KIT_STATIC_LOCALES=[en_US]' 'static locales default'
  assert_contains 'KIT_COMPOSE_PROFILES=[]' 'compose profiles default is empty'
}

test_missing_profile_file_uses_defaults() {
  new_root
  rm -f "$ROOT/project/profile.env"
  load_and_print "$ROOT" KIT_PHP_VERSION
  assert_status 0 'absent profile file is not an error'
  assert_contains 'KIT_PHP_VERSION=[8.3]' 'absent profile file gives defaults'
}

test_mysql_version_default() {
  new_root
  write_profile 'KIT_DB_ENGINE=mysql'
  load_and_print "$ROOT" KIT_DB_VERSION
  assert_contains 'KIT_DB_VERSION=[8.4]' 'mysql without a version gets the mysql default'
  write_profile 'KIT_DB_ENGINE=mysql' 'KIT_DB_VERSION=8.0.45'
  load_and_print "$ROOT" KIT_DB_VERSION
  assert_contains 'KIT_DB_VERSION=[8.0.45]' 'explicit version wins'
}

test_values_comments_and_spaces() {
  new_root
  write_profile '# a comment' '' \
    'KIT_STATIC_LOCALES=en_US vi_VN' \
    'KIT_REDIS_IMAGE=redis:7.2-alpine   # trailing comment' \
    'KIT_DOMAIN=shop.test' \
    'KIT_DB_PORT=3307' 'KIT_DB_PORT=3308'
  load_and_print "$ROOT" KIT_STATIC_LOCALES KIT_REDIS_IMAGE KIT_DOMAIN KIT_DB_PORT
  assert_status 0 'comments, blank lines and spaces in values are accepted'
  assert_contains 'KIT_STATIC_LOCALES=[en_US vi_VN]' 'value with a space is kept whole'
  assert_contains 'KIT_REDIS_IMAGE=[redis:7.2-alpine]' 'trailing comment is dropped'
  assert_contains 'KIT_DOMAIN=[shop.test]' 'plain value'
  assert_contains 'KIT_DB_PORT=[3308]' 'the last duplicate wins'
}

test_project_name_defaults_to_directory() {
  new_root My_Shop.Test
  load_and_print "$ROOT" KIT_PROJECT_NAME
  assert_contains 'KIT_PROJECT_NAME=[my_shoptest]' 'project name defaults to the normalised directory name'
  write_profile 'KIT_PROJECT_NAME=format'
  load_and_print "$ROOT" KIT_PROJECT_NAME
  assert_contains 'KIT_PROJECT_NAME=[format]' 'explicit project name wins'
}

test_rejects_bad_syntax() {
  new_root
  local bad
  # String for a subshell or a fixture, left with its literal $ character.
  # shellcheck disable=SC2016
  for bad in 'KIT_DOMAIN="shop.test"' "KIT_DOMAIN='shop.test'" 'KIT_DOMAIN=${HOST}' 'KIT_DOMAIN=$(id)' \
    'KIT_DOMAIN =shop.test' 'KIT_DOMAIN= shop.test' 'DOMAIN=shop.test' 'KIT_domain=x' 'just text'; do
    write_profile 'KIT_PHP_VERSION=8.2' "$bad"
    load_and_print "$ROOT" KIT_PHP_VERSION
    assert_status_nonzero "rejects: $bad"
    assert_contains 'profile.env:2' "reports the file and line for: $bad"
  done
}

test_does_not_execute_values() {
  new_root
  write_profile "KIT_STATIC_LOCALES=en_US; touch $SANDBOX/pwned"
  load_and_print "$ROOT" KIT_STATIC_LOCALES
  assert_absent "$SANDBOX/pwned" 'a value is never executed'
}

test_require_reports_missing_key() {
  new_root
  write_profile 'KIT_DOMAIN=shop.test'
  # String for a subshell or a fixture, left with its literal $ character.
  # shellcheck disable=SC2016
  run_cmd bash -c '
    source "$1/bin/lib/profile.sh"; kit_profile_load "$2"
    kit_profile_require KIT_DOMAIN KIT_GIT_REMOTE KIT_GIT_BASE_BRANCH
  ' _ "$KIT_REPO_ROOT/dist/files" "$ROOT"
  assert_status_nonzero 'require fails when a required key is empty'
  assert_contains 'KIT_GIT_REMOTE' 'names the first missing key'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'names every missing key'
  assert_not_contains 'KIT_DOMAIN' 'does not name a key that is set'
  assert_contains 'project/profile.env' 'points at the profile file'
  # String for a subshell or a fixture, left with its literal $ character.
  # shellcheck disable=SC2016
  run_cmd bash -c '
    source "$1/bin/lib/profile.sh"; kit_profile_load "$2"
    kit_profile_require KIT_DOMAIN
  ' _ "$KIT_REPO_ROOT/dist/files" "$ROOT"
  assert_status 0 'require passes when keys are set'
}

test_runtime_env_overrides_profile() {
  new_root
  write_profile 'KIT_PHP_VARIANT=' 'KIT_PHP_VERSION=8.2'
  printf 'KIT_PHP_VARIANT=-xdebug\n' > "$ROOT/.kit/runtime.env"
  load_and_print "$ROOT" KIT_PHP_VARIANT KIT_PHP_VERSION
  assert_contains 'KIT_PHP_VARIANT=[-xdebug]' 'runtime.env is read after the profile'
  assert_contains 'KIT_PHP_VERSION=[8.2]' 'profile values stay'
}

test_unknown_keys_are_reported() {
  new_root
  write_profile 'KIT_TYPO_KEY=1' 'KIT_MODEL_CLAUDE_DEEP=opus'
  # String for a subshell or a fixture, left with its literal $ character.
  # shellcheck disable=SC2016
  run_cmd bash -c '
    source "$1/bin/lib/profile.sh"; kit_profile_load "$2"; printf "unknown=[%s]\n" "$KIT_PROFILE_UNKNOWN"
  ' _ "$KIT_REPO_ROOT/dist/files" "$ROOT"
  assert_contains 'unknown=[KIT_TYPO_KEY]' 'unknown KIT_ key is listed, model keys are not'
}

test_new_domain_fills_profile() {
  sandbox_new
  kit_new shop --domain x.test
  assert_status 0 'new --domain exits 0'
  assert_file_line "$SANDBOX/shop/project/profile.env" 'KIT_DOMAIN=x.test' 'KIT_DOMAIN is filled'
  assert_file_line "$SANDBOX/shop/project/profile.env" 'KIT_GIT_REMOTE=' 'other required keys stay empty'
  load_and_print "$SANDBOX/shop" KIT_DOMAIN KIT_PROJECT_NAME
  assert_contains 'KIT_DOMAIN=[x.test]' 'the library reads the filled domain'
  assert_contains 'KIT_PROJECT_NAME=[shop]' 'project name still defaults to the directory name'
}

test_new_domain_rejects_bad_value() {
  sandbox_new
  kit_new shop --domain 'a b;c'
  assert_status_nonzero 'new --domain rejects an invalid domain'
  assert_absent "$SANDBOX/shop" 'nothing is written for an invalid domain'
}

test_new_without_domain_leaves_it_empty() {
  sandbox_new
  kit_new shop
  assert_file_line "$SANDBOX/shop/project/profile.env" 'KIT_DOMAIN=' 'KIT_DOMAIN stays empty without --domain'
}

test_gitignore_template() {
  sandbox_new
  kit_new shop
  local entry
  for entry in src/ .kit/backup/ .kit/runtime.env .worktrees/ .active-src env/cloudflare.env; do
    assert_file_line "$SANDBOX/shop/.gitignore" "$entry" ".gitignore ignores $entry"
  done
  assert_absent "$SANDBOX/shop/.git" 'new does not git init'
}

test_env_templates_keep_upstream_names() {
  sandbox_new
  kit_new shop
  assert_file_line "$SANDBOX/shop/env/db.env" 'MYSQL_ROOT_PASSWORD=magento' 'db.env keeps MYSQL_ROOT_PASSWORD'
  assert_file_line "$SANDBOX/shop/env/db.env" 'MYSQL_DATABASE=magento' 'db.env keeps MYSQL_DATABASE'
  assert_file_line "$SANDBOX/shop/env/cloudflare.env" 'TUNNEL_TOKEN=' 'cloudflare.env keeps TUNNEL_TOKEN'
  local f
  for f in phpfpm opensearch rabbitmq redis magento; do
    assert_file "$SANDBOX/shop/env/$f.env" "env/$f.env template exists"
  done
}

run_tests
finish
