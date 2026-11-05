#!/usr/bin/env bash
# Seam S2: `docker compose config` thật (không cần daemon) cho mọi tổ hợp engine
# DB và overlay worktree, kiểm tên project và tên volume theo KIT_PROJECT_NAME.
#
# Không có docker compose thì bỏ qua, trừ khi đặt KIT_REQUIRE_DOCKER=1 (CI đặt).
#
# Usage:  bash tests/test-compose-config.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

if ! docker compose version >/dev/null 2>&1; then
  if [[ "${KIT_REQUIRE_DOCKER:-}" == 1 ]]; then
    printf 'cần docker compose để chạy seam S2\n' >&2
    exit 1
  fi
  printf '# bỏ qua S2: không có docker compose\n1..0\n'
  exit 0
fi

# Docker thật: sandbox chỉ dùng để có Docker root, bỏ docker giả ra khỏi PATH.
new_root() {
  sandbox_new
  export PATH="$ORIG_PATH"
  kit_new "${1:-shop}" >/dev/null
  ROOT="$SANDBOX/${1:-shop}"
}

config() {
  run_in "$SANDBOX" "$ROOT/bin/docker-compose" config "$@"
}

# Giá trị `name:` ở dòng đầu của `docker compose config`.
project_of() { printf '%s\n' "$OUTPUT" | sed -n 's/^name: //p' | head -n 1; }

check_matrix_case() {
  local engine="$1" overlay="$2" nodev="${3:-}" label args=()
  label="engine=$engine overlay=$overlay${nodev:+ no-dev}"
  new_root
  printf 'KIT_PROJECT_NAME=acme\nKIT_DB_ENGINE=%s\n' "$engine" > "$ROOT/project/profile.env"
  if [[ "$overlay" == yes ]]; then
    mkdir "$ROOT/src"
    ln -s src "$ROOT/.active-src"
  fi
  [[ -z "$nodev" ]] || args=(--no-dev)
  run_in "$SANDBOX" "$ROOT/bin/docker-compose" ${args[@]+"${args[@]}"} config
  assert_status 0 "config is valid: $label"
  assert_equals acme "$(project_of)" "project name follows KIT_PROJECT_NAME: $label"
  assert_contains 'name: acme_dbdata' "volume dbdata is prefixed by the project: $label"
  assert_contains 'name: acme_sockdata' "volume sockdata is prefixed by the project: $label"
  assert_contains "image: $engine:" "db image matches the engine: $label"
  assert_contains '--max_allowed_packet=64M' "db carries max_allowed_packet: $label"
  assert_contains '--log_bin_trust_function_creators=1' "db carries log_bin_trust_function_creators: $label"
  if [[ "$overlay" == yes && -z "$nodev" ]]; then
    assert_contains "$ROOT/.active-src" "overlay mounts .active-src: $label"
  else
    assert_not_contains '.active-src' "no overlay mount: $label"
  fi
}

test_matrix() {
  local engine overlay
  for engine in mariadb mysql; do
    for overlay in no yes; do
      check_matrix_case "$engine" "$overlay"
    done
    check_matrix_case "$engine" yes no-dev
  done
}

test_db_service_only_from_engine_file() {
  new_root
  config --services
  assert_status 0 'services listed'
  assert_contains 'db' 'db service exists through the engine file'
  run_in "$ROOT" docker compose -f compose.yaml config --services
  assert_not_contains 'db' 'base file alone has no db service'
}

test_profile_values_reach_compose() {
  new_root
  cat > "$ROOT/project/profile.env" <<'PROFILE'
KIT_PROJECT_NAME=acme
KIT_DB_ENGINE=mysql
KIT_DB_VERSION=8.0.45
KIT_REDIS_IMAGE=redis:7.2-alpine
KIT_HTTP_PORT=8080
KIT_HTTPS_PORT=8443
KIT_DB_PORT=3307
KIT_REDIS_PORT=6378
KIT_OPENSEARCH_PORT=9201
KIT_OPENSEARCH_HEAP=2g
KIT_RABBITMQ_PORT=5673
KIT_RABBITMQ_MANAGEMENT_PORT=15673
PROFILE
  config
  assert_status 0 'config with a full profile is valid'
  assert_contains 'image: mysql:8.0.45' 'DB version from the key'
  assert_contains 'image: redis:7.2-alpine' 'Redis image from the key'
  assert_contains 'published: "8080"' 'HTTP port from the key'
  assert_contains 'published: "8443"' 'HTTPS port from the key'
  assert_contains 'published: "3307"' 'DB port from the key'
  assert_contains 'published: "6378"' 'Redis port from the key'
  assert_contains 'published: "9201"' 'OpenSearch port from the key'
  assert_contains 'published: "5673"' 'RabbitMQ port from the key'
  assert_contains 'published: "15673"' 'RabbitMQ management port from the key'
  assert_contains 'OPENSEARCH_JAVA_OPTS: -Xms2g -Xmx2g' 'OpenSearch heap from the key'
}

test_defaults_match_upstream() {
  new_root
  printf 'KIT_PROJECT_NAME=acme\n' > "$ROOT/project/profile.env"
  config
  assert_contains 'image: mariadb:11.4' 'default DB'
  assert_contains 'image: valkey/valkey:8.1-alpine' 'default Redis image'
  assert_contains 'published: "3306"' 'default DB port'
  assert_contains 'published: "6379"' 'default Redis port'
  assert_contains 'published: "9200"' 'default OpenSearch port'
  assert_contains 'OPENSEARCH_JAVA_OPTS: -Xms1g -Xmx1g' 'default heap'
}

test_override_is_merged_last() {
  new_root
  printf 'KIT_PROJECT_NAME=acme\n' > "$ROOT/project/profile.env"
  printf 'services:\n  redis:\n    command: redis-server --appendonly yes\n' > "$ROOT/compose.override.yaml"
  config
  assert_status 0 'config with an override is valid'
  assert_contains 'appendonly' 'override content is merged'
}

test_cloudflared_profile() {
  new_root
  printf 'KIT_PROJECT_NAME=acme\n' > "$ROOT/project/profile.env"
  config --services
  assert_status 0 'services without the profile'
  assert_not_contains 'tunnel' 'no tunnel service without the cloudflared profile'
  config
  assert_status 0 'config without the profile is valid'
  assert_not_contains 'cloudflare/cloudflared' 'no cloudflared image without the profile'

  printf 'KIT_PROJECT_NAME=acme\nKIT_COMPOSE_PROFILES=cloudflared\n' > "$ROOT/project/profile.env"
  config --services
  assert_contains 'tunnel' 'tunnel service with the cloudflared profile'
  config
  assert_status 0 'config with the profile is valid'
  assert_contains 'image: cloudflare/cloudflared:2026.10.1' 'tunnel image is pinned to a version'
  assert_not_contains ':latest' 'tunnel image is not latest'
  assert_contains '- --no-autoupdate' 'tunnel command has --no-autoupdate'
  assert_contains '- http2' 'tunnel command uses http2'
  assert_contains '- --retries' 'tunnel command has --retries'
  assert_not_contains 'container_name' 'tunnel has no container_name'
  assert_contains 'TUNNEL_TOKEN' 'token comes from env/cloudflare.env'
}

test_cloudflared_with_engine_and_worktree() {
  local engine
  for engine in mariadb mysql; do
    new_root
    printf 'KIT_PROJECT_NAME=acme\nKIT_DB_ENGINE=%s\nKIT_COMPOSE_PROFILES=cloudflared\n' "$engine" > "$ROOT/project/profile.env"
    mkdir "$ROOT/src"
    ln -s src "$ROOT/.active-src"
    config
    assert_status 0 "config valid with cloudflared, engine=$engine, overlay"
  done
}

test_php_image_pin_and_variant() {
  local n tag
  n="$(tr -d '[:space:]' < "$KIT_REPO_ROOT/images/php/IMAGE_VERSION")"
  tag='ghcr.io/nguyentrunghieu98/magento-php'
  new_root
  printf 'KIT_PROJECT_NAME=acme\n' > "$ROOT/project/profile.env"
  config
  assert_status 0 'config valid with the default variant'
  assert_contains "image: $tag:8.3-fpm-$n"$'\n' 'default PHP 8.3, pinned n, empty variant' "$OUTPUT"$'\n'
  assert_not_contains "-fpm-$n-xdebug" 'no xdebug tag by default'
  printf 'KIT_PROJECT_NAME=acme\nKIT_PHP_VERSION=8.2\n' > "$ROOT/project/profile.env"
  config
  assert_contains "image: $tag:8.2-fpm-$n"$'\n' 'KIT_PHP_VERSION selects the PHP version' "$OUTPUT"$'\n'
  mkdir -p "$ROOT/.kit"
  printf 'KIT_PHP_VARIANT=-xdebug\n' > "$ROOT/.kit/runtime.env"
  config
  assert_contains "image: $tag:8.2-fpm-$n-xdebug" 'runtime variant -xdebug gives the xdebug tag'
  printf 'KIT_PHP_VARIANT=\n' > "$ROOT/.kit/runtime.env"
  config
  assert_contains "image: $tag:8.2-fpm-$n"$'\n' 'empty runtime variant gives the main tag' "$OUTPUT"$'\n'
  assert_not_contains 'markoshust/magento-php' 'no upstream PHP image left'
}

run_tests
finish
