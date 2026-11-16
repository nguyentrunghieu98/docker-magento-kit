#!/usr/bin/env bash
# bin/test/ui-regression: runs the project's Playwright Test suite in the official Playwright
# image of the version package.json pins, on the served checkout only, one worker, as the host
# user. Stops with exit 2 before docker when the suite, the pin or the served checkout is wrong.
# Docker is a fake that logs the run arguments.
#
# Usage:  bash tests/test-ui-regression.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Fake docker: `run` logs its arguments and exits with $TEST_EXIT (default 0).
install_docker() {
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "${TEST_LOG_DIR:?}/docker.log"
case "${1:-}" in run) exit "${TEST_EXIT:-0}" ;; esac
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
}

# Docker root with src/ (a Git repo), one worktree .worktrees/feature-one, and a suite in src/
# that pins @playwright/test 1.49.1.
new_root() {
  sandbox_new
  install_docker
  root_new shop
  SRC="$ROOT/src"
  mkdir -p "$SRC"
  git -c init.defaultBranch=master init -q "$SRC"
  git -C "$SRC" config user.name t
  git -C "$SRC" config user.email t@example.invalid
  git -C "$SRC" config commit.gpgsign false
  printf '{"name": "kit/magento-test"}\n' > "$SRC/composer.json"
  git -C "$SRC" add composer.json
  git -C "$SRC" commit -q -m init
  mkdir -p "$ROOT/.worktrees"
  git -C "$SRC" worktree add -q "$ROOT/.worktrees/feature-one" -b feature/one
  WT="$ROOT/.worktrees/feature-one"
  suite_new "$SRC"
  unset TEST_EXIT BASE_URL
}

# A valid suite in checkout $1.
suite_new() {
  local dir="$1/dev/tests/ui-regression"
  mkdir -p "$dir"
  : > "$dir/playwright.config.ts"
  printf '{"devDependencies": {"@playwright/test": "1.49.1"}}\n' > "$dir/package.json"
}

shot() {
  reset_calls
  run_in "$ROOT" bin/test/ui-regression "$@"
}

calls() { cat "$TEST_LOG_DIR/docker.log" 2> /dev/null || true; }

test_info() {
  new_root
  shot --info
  assert_status 0 '--info exits 0'
  assert_contains 'checkout=main (served)' '--info names the served checkout'
  assert_contains "suite=$SRC/dev/tests/ui-regression" '--info names the suite'
  assert_contains 'playwright=1.49.1' '--info reads the pinned version'
  assert_contains 'image=mcr.microsoft.com/playwright:v1.49.1-noble' '--info names the image of that version'
  assert_contains 'env-file=none' '--info says there is no env file'
  assert_contains 'workers=1' '--info says one worker'
  assert_equals '' "$(calls)" '--info does not call docker'
}

test_run_serves_the_suite_in_the_pinned_image() {
  new_root
  shot
  assert_status 0 'a run exits 0'
  local c
  c="$(calls)"
  assert_contains 'run --rm --init --ipc=host' 'the container is throwaway, with an init and the shared IPC chromium needs' "$c"
  assert_contains "--user $(id -u):$(id -g)" 'it runs as the host user, so the baselines belong to you' "$c"
  assert_contains "-v $SRC/dev/tests/ui-regression:/work -w /work" 'the suite directory is mounted as the working directory' "$c"
  assert_contains 'mcr.microsoft.com/playwright:v1.49.1-noble bash -c' 'it uses the official image of the pinned version' "$c"
  assert_contains 'npx playwright test --workers=1' 'it runs Playwright Test with one worker' "$c"
  assert_not_contains '--update-snapshots' 'a plain run never rewrites a baseline' "$c"
  shot login-390.spec.ts -- -g cart
  assert_contains 'npx playwright test --workers=1 login-390.spec.ts -g cart' 'specs and filters go to Playwright' "$(calls)"
}

test_update_rewrites_the_baselines() {
  new_root
  shot --update cart.spec.ts
  assert_contains 'npx playwright test --workers=1 --update-snapshots cart.spec.ts' '--update passes --update-snapshots' "$(calls)"
}

test_only_the_served_checkout_runs() {
  new_root
  shot --wt feature-one
  assert_status 2 'a worktree that is not served exits 2'
  assert_contains 'feature-one is not the served checkout' 'the message names it'
  assert_contains 'bin/wt use feature-one' 'the message gives the switch command'
  assert_equals '' "$(calls)" 'docker is not called'

  ln -s .worktrees/feature-one "$ROOT/.active-src"
  suite_new "$WT"
  shot
  assert_status 0 'the served worktree runs without --wt'
  assert_contains "-v $WT/dev/tests/ui-regression:/work" 'the suite of the served worktree is mounted' "$(calls)"
  shot --wt main
  assert_status 2 'the main checkout is refused while a worktree is served'
  shot --wt nope
  assert_status 2 'an unknown worktree exits 2'
  assert_contains 'Unknown worktree' 'the message says so'
}

test_a_broken_suite_stops_before_docker() {
  new_root
  rm -rf "$SRC/dev/tests/ui-regression"
  shot
  assert_status 2 'no suite exits 2'
  assert_contains 'No suite at dev/tests/ui-regression' 'the message says where the suite goes'

  suite_new "$SRC"
  rm "$SRC/dev/tests/ui-regression/playwright.config.ts"
  shot
  assert_status 2 'no config exits 2'

  suite_new "$SRC"
  rm "$SRC/dev/tests/ui-regression/package.json"
  shot
  assert_status 2 'no package.json exits 2'

  suite_new "$SRC"
  printf '{"devDependencies": {"@playwright/test": "^1.49.1"}}\n' > "$SRC/dev/tests/ui-regression/package.json"
  shot
  assert_status 2 'a range instead of an exact version exits 2'
  assert_contains 'exact version' 'the message asks for an exact version'
  assert_equals '' "$(calls)" 'docker is never called for a broken suite'
}

test_env_file() {
  new_root
  mkdir -p "$ROOT/env"
  : > "$ROOT/env/ui-regression.env"
  shot
  assert_contains "--env-file $ROOT/env/ui-regression.env" 'env/ui-regression.env is used when it exists' "$(calls)"
  : > "$ROOT/env/cf.env"
  shot --env-file env/cf.env
  assert_contains "--env-file $ROOT/env/cf.env" '--env-file overrides the default' "$(calls)"
  shot --env-file /etc/passwd
  assert_status 2 'an absolute env file exits 2'
  shot --env-file env/missing.env
  assert_status 2 'a missing env file exits 2'
  rm "$ROOT/env/ui-regression.env"
  shot
  assert_not_contains '--env-file' 'no env file, no flag' "$(calls)"
  reset_calls
  BASE_URL=https://shop.test run_in "$ROOT" bin/test/ui-regression
  assert_contains '-e BASE_URL' 'a BASE_URL set in the shell is passed on' "$(calls)"
}

test_failure_points_at_the_diff_images() {
  new_root
  TEST_EXIT=1 shot
  assert_status 1 'the Playwright exit code is passed through'
  assert_contains "Diff images (expected, actual, diff): $SRC/dev/tests/ui-regression/test-results" 'a failure says where the diff images are'
  assert_contains 'approves --update' 'and who decides about a new baseline'
  TEST_EXIT=1 shot --update
  assert_status 1 'a failed update exits with the code too'
  assert_not_contains 'Diff images' 'an update failure does not point at diffs' "$OUTPUT"
}

test_usage() {
  new_root
  shot --help
  assert_status 0 '--help exits 0'
  assert_contains 'Usage: bin/test/ui-regression' 'the usage is printed'
  shot --nope
  assert_status 2 'an unknown option exits 2'
}

run_tests
finish
