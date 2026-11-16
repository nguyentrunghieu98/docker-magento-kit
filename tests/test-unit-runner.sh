#!/usr/bin/env bash
# bin/test/unit: picks the command from the composer scripts test:unit /
# test:unit:parallel, falls back to vendor/bin/phpunit or paratest, fails loudly when
# --parallel has no ParaTest, and with --wt runs in a throwaway container (read-only
# worktree and vendor, tmpfs for generated/var/tmp). Docker is a fake that logs.
#
# Also bin/phpcs, which shares the same container path (bin/wt run) for --wt.
#
# Fixtures: (script, paratest), (no script, paratest), (no script, no paratest), (lock differs).
#
# Usage:  bash tests/test-unit-runner.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Fake docker: `compose ... ps -q phpfpm` prints an id unless $KIT_TEST_NO_PHPFPM is set,
# `inspect` prints an image name, `run` and `exec` exit with $KIT_TEST_EXIT (default 0).
install_docker() {
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then exit 0; fi
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
case "$*" in
  *'ps -q phpfpm'*) [[ -n "${KIT_TEST_NO_PHPFPM:-}" ]] || printf 'cid-phpfpm\n' ;;
  inspect*) printf 'shop/magento-php:8.2-fpm\n' ;;
  run* | *' exec '*) exit "${KIT_TEST_EXIT:-0}" ;;
esac
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
}

# Docker root with src/ (a Git repo) and one worktree .worktrees/feature-one.
#   $1: script | noscript    composer.json has test:unit / test:unit:parallel or not
#   $2: paratest | nopara    src/vendor/bin/paratest exists or not
new_root() {
  local scripts="$1" para="$2"
  sandbox_new
  install_docker
  root_new shop
  SRC="$ROOT/src"
  mkdir -p "$SRC"
  git -c init.defaultBranch=master init -q "$SRC"
  git -C "$SRC" config user.name t
  git -C "$SRC" config user.email t@example.invalid
  git -C "$SRC" config commit.gpgsign false
  if [[ "$scripts" == script ]]; then
    printf '{"scripts": {\n  "test:unit": "@php vendor/bin/phpunit",\n  "test:unit:parallel": "@php vendor/bin/paratest"\n}}\n' > "$SRC/composer.json"
  else
    printf '{"name": "kit/magento-test"}\n' > "$SRC/composer.json"
  fi
  printf '{"content-hash": "a"}\n' > "$SRC/composer.lock"
  printf '*\n!.gitignore\n!composer.json\n!composer.lock\n' > "$SRC/.gitignore"
  git -C "$SRC" add .gitignore composer.json composer.lock
  git -C "$SRC" commit -q -m init

  mkdir -p "$SRC/vendor/bin" "$SRC/vendor/phpunit/phpunit/src/Runner" "$SRC/dev/tests/unit/tmp" \
    "$SRC/bin" "$SRC/lib" "$SRC/setup" "$SRC/phpserver"
  printf "<?php\n\$v = new VersionId('9.6.20', __DIR__);\n" > "$SRC/vendor/phpunit/phpunit/src/Runner/Version.php"
  : > "$SRC/vendor/bin/phpunit"
  : > "$SRC/dev/tests/unit/phpunit.xml.dist"
  [[ "$para" == paratest ]] && : > "$SRC/vendor/bin/paratest"

  mkdir -p "$ROOT/.worktrees"
  git -C "$SRC" worktree add -q "$ROOT/.worktrees/feature-one" -b feature/one
  WT="$ROOT/.worktrees/feature-one"
  mkdir -p "$WT/generated" "$WT/var" "$WT/vendor" "$WT/dev" "$WT/bin" "$WT/lib" "$WT/setup" "$WT/phpserver"

  # Stand-in for upstream bin/debug-cli.
  cat > "$ROOT/bin/debug-cli" <<'STUB'
#!/usr/bin/env bash
printf 'debug-cli %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
STUB
  chmod 755 "$ROOT/bin/debug-cli"
  unset KIT_TEST_NO_PHPFPM KIT_TEST_EXIT TEST_PROCESSES
}

unit() {
  reset_calls
  run_in "$ROOT" bin/test/unit "$@"
}

calls() { cat "$KIT_LOG_DIR/docker.log" 2> /dev/null || true; }

test_info_with_scripts_and_paratest() {
  new_root script paratest
  unit --info
  assert_status 0 '--info exits 0'
  assert_contains 'checkout=main (active)' '--info names the checkout'
  assert_contains 'phpunit=9.6.20' '--info reads the PHPUnit version'
  assert_contains 'paratest=yes' '--info sees ParaTest'
  assert_contains 'processes=2' '--info shows the default process count'
  assert_contains 'serial=composer test:unit' '--info picks the composer script for serial'
  assert_contains 'parallel=composer test:unit:parallel' '--info picks the composer script for parallel'
  assert_equals 'serial=composer test:unit' "$(grep '^serial=' <<< "$OUTPUT")" '--info prints the serial command without the trailing --'
  assert_equals 'parallel=composer test:unit:parallel' "$(grep '^parallel=' <<< "$OUTPUT")" '--info prints the parallel command without the trailing --'
  assert_equals '' "$(calls)" '--info does not call docker'
}

test_info_without_scripts() {
  new_root noscript paratest
  TEST_PROCESSES=4 unit --info --wt feature-one
  assert_contains 'checkout=feature-one (container)' '--info --wt names the worktree and the container mode'
  assert_contains 'serial=vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist' 'serial falls back to phpunit'
  assert_contains 'parallel=vendor/bin/paratest -p 4 -c dev/tests/unit/phpunit.xml.dist' 'parallel falls back to paratest with TEST_PROCESSES'
  new_root noscript nopara
  unit --info
  assert_contains 'paratest=missing' '--info reports a missing ParaTest'
  assert_contains 'parallel=unavailable' '--info says parallel is unavailable'
}

test_serial_on_active_checkout_uses_phpfpm() {
  new_root script paratest
  unit app/code/Shop/Cart/Test/Unit/FooTest.php --filter testBar
  assert_status 0 'serial exits 0'
  assert_contains 'exec -T phpfpm composer test:unit -- --filter testBar app/code/Shop/Cart/Test/Unit/FooTest.php' 'serial runs the composer script in phpfpm' "$(calls)"
  KIT_TEST_EXIT=1 unit app/code/Shop
  assert_status 1 'the test exit code is passed through'
}

test_parallel() {
  new_root noscript paratest
  unit --parallel app/code/Shop
  assert_status 0 'parallel exits 0'
  assert_contains 'exec -T phpfpm vendor/bin/paratest -p 2 -c dev/tests/unit/phpunit.xml.dist app/code/Shop' 'parallel runs paratest' "$(calls)"
  unit --parallel app/code/Shop --filter testBar
  assert_status 2 '--parallel --filter is refused with exit 2'
  assert_contains 'pick a file or directory' 'the error suggests a narrower path'
}

test_parallel_without_paratest_fails_loudly() {
  new_root script nopara
  unit --parallel app/code/Shop
  assert_status 2 '--parallel without ParaTest exits 2'
  assert_contains 'brianium/paratest:^6' 'the hint matches PHPUnit 9'
  assert_equals '' "$(calls)" 'nothing runs, no silent fallback to serial'
}

test_wt_runs_in_a_throwaway_container() {
  new_root script paratest
  unit --wt feature-one app/code/Shop --filter testBar
  assert_status 0 '--wt exits 0'
  local c
  c="$(calls)"
  assert_contains 'docker run --rm --network none' '--wt uses a throwaway container without network' "$c"
  assert_contains "-v $WT:/var/www/html:ro" 'the worktree is mounted read-only' "$c"
  assert_contains "-v $SRC/vendor:/var/www/html/vendor:ro" 'the shared vendor is mounted read-only' "$c"
  assert_contains '--tmpfs /var/www/html/generated' 'generated is a tmpfs' "$c"
  assert_contains '--tmpfs /var/www/html/var' 'var is a tmpfs' "$c"
  assert_contains '--tmpfs /var/www/html/dev/tests/unit' 'dev/tests/unit is a tmpfs (result cache, Allure, tmp)' "$c"
  assert_contains "-v $SRC/dev/tests/unit:/opt/wt/unit-tests:ro" 'the unit test config is mounted read-only aside' "$c"
  assert_contains 'cp -R /opt/wt/unit-tests/. /var/www/html/dev/tests/unit/' 'the container copies it into the tmpfs first' "$c"
  assert_contains "allure-results/' . getmypid()" 'the copy gives each PHP process its own Allure directory (ParaTest workers)' "$c"
  assert_contains 'shop/magento-php:8.2-fpm sh -c' 'same image as phpfpm' "$c"
  assert_contains 'composer test:unit -- --filter testBar app/code/Shop' 'serial runs the composer script' "$c"
  assert_not_contains 'do-not-cache-result' 'no PHPUnit-specific cache flag is needed' "$c"
  assert_not_contains 'exec -T phpfpm' '--wt never runs inside the shared phpfpm' "$c"
  unit --wt main --parallel app/code/Shop
  assert_contains "-v $SRC:/var/www/html:ro" '--wt main also uses a container (one tmpfs per run)' "$(calls)"
  KIT_TEST_EXIT=3 unit --wt feature-one app/code/Shop
  assert_status 3 'the container exit code is passed through'
}

test_wt_refusals() {
  new_root script paratest
  printf '{"content-hash": "b"}\n' > "$WT/composer.lock"
  unit --wt feature-one app/code/Shop
  assert_status 2 'a differing composer.lock exits 2'
  assert_contains 'bin/wt use feature-one' 'the error says how to fix the lock'
  # After `bin/wt use feature-one && bin/composer install`, vendor/ follows the active lock.
  ln -s "$WT" "$ROOT/.active-src"
  unit --wt feature-one app/code/Shop
  assert_status 0 'the lock is compared with the active checkout, so the suggested fix works'
  unit --wt main app/code/Shop
  assert_status 2 'src/ is refused once vendor/ follows another lock'
  new_root script paratest
  KIT_TEST_NO_PHPFPM=1 unit --wt feature-one app/code/Shop
  assert_status 2 'no running phpfpm exits 2'
  assert_contains 'bin/start' 'the error says to start the stack'
  unit --wt nope app/code/Shop
  assert_status 2 'an unknown worktree exits 2'
  unit --wt feature-one --xdebug app/code/Shop
  assert_status 2 '--xdebug with --wt is refused'
}

test_xdebug_and_coverage_use_debug_cli() {
  new_root script paratest
  unit --xdebug app/code/Shop
  assert_contains 'debug-cli php vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist app/code/Shop' '--xdebug runs through bin/debug-cli' "$(calls)"
  unit --coverage app/code/Shop
  assert_contains 'debug-cli php -d xdebug.mode=coverage vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist --coverage-html dev/tests/unit/report app/code/Shop' '--coverage writes an HTML report' "$(calls)"
}

test_usage_errors() {
  new_root script paratest
  unit
  assert_status 2 'no path exits 2'
  assert_contains 'Usage: bin/test/unit' 'the usage is printed'
  unit --help
  assert_status 0 '--help exits 0'
  unit --nope app/code
  assert_status 2 'an unknown option exits 2'
}

test_phpcs_active_and_wt() {
  new_root script paratest
  reset_calls
  run_in "$ROOT" bin/phpcs app/code/Shop
  assert_status 0 'phpcs exits 0'
  assert_contains 'exec -T phpfpm vendor/bin/phpcs --standard=Magento2 --extensions=php,phtml --error-severity=10 --ignore-annotations app/code/Shop' 'without --wt phpcs runs like upstream' "$(calls)"
  reset_calls
  run_in "$ROOT" bin/phpcs --wt feature-one --report=summary app/code/Shop
  local c
  c="$(calls)"
  assert_contains "-v $WT:/var/www/html:ro" 'phpcs --wt mounts the worktree read-only' "$c"
  assert_contains 'vendor/bin/phpcs --standard=Magento2 --extensions=php,phtml --error-severity=10 --ignore-annotations --report=summary app/code/Shop' 'phpcs --wt runs in the throwaway container' "$c"
  run_in "$ROOT" bin/phpcs --wt
  assert_status 2 'phpcs --wt without a name exits 2'
}

run_tests
finish
