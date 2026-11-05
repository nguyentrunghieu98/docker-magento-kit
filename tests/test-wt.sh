#!/usr/bin/env bash
# S1 test for bin/wt (core): create from the remote, refuse bad names, use refuses paths
# outside .worktrees/, prepare, list, status, path, shell, remove, mounts, and bin/watch
# following the target of .active-src. The Docker root is installed with install.sh new
# --source, git is real with a bare remote having master and staging, and docker is a
# fake that logs. Ported from tests/test-magento-wt.sh of the Format project.
#
# Usage:  bash tests/test-wt.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Fake docker: logs every command, `docker info` follows the online flag, and when online
# `compose ... ps --services --status running` returns app, phpfpm, db. KIT_TEST_FAIL_UP=1
# makes `compose ... up` fail.
install_docker() {
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then exit 0; fi
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
case "$*" in
  info*)
    [[ -e "${KIT_DOCKER_ONLINE:?}" ]] && exit 0
    exit 1
    ;;
  *'ps --services --status running'*)
    printf '%s\n' app phpfpm db
    ;;
  *' up '*)
    [[ "${KIT_TEST_FAIL_UP:-0}" == 1 ]] && exit 1
    ;;
esac
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
}

# Docker root `shop` with src/ cloned from the bare remote (remote named origin, with
# master and staging). master holds a Magento-style whitelist .gitignore and
# composer.json, while the core files (bootstrap.php, env.php...) exist only in src/ and
# are ignored by Git. The profile declares the Git keys unless $1 is no-git-keys.
new_root() {
  sandbox_new
  install_docker
  git_remote_new
  kit_new shop --domain shop.test > /dev/null
  ROOT="$SANDBOX/shop"
  SRC="$ROOT/src"

  rm -rf "$SRC"
  git clone -q "$BARE_REMOTE" "$SRC"
  git -C "$SRC" config user.name 'kit tests'
  git -C "$SRC" config user.email 'tests@example.invalid'
  git -C "$SRC" config commit.gpgsign false
  printf '*\n!.gitignore\n!composer.json\n!composer.lock\n' > "$SRC/.gitignore"
  printf '{"name": "kit/magento-test"}\n' > "$SRC/composer.json"
  printf '{"content-hash": "a"}\n' > "$SRC/composer.lock"
  git -C "$SRC" add .gitignore composer.json composer.lock
  git -C "$SRC" commit -q -m 'magento sandbox'
  git -C "$SRC" push -q origin master

  mkdir -p "$SRC/app/etc" "$SRC/pub/media" "$SRC/vendor" "$SRC/node_modules" \
    "$SRC/bin" "$SRC/dev" "$SRC/lib" "$SRC/phpserver" "$SRC/setup"
  printf '<?php // bootstrap\n' > "$SRC/app/bootstrap.php"
  printf '<?php // autoload\n' > "$SRC/app/autoload.php"
  printf "<?php return ['db' => ['host' => 'db']];\n" > "$SRC/app/etc/env.php"
  printf '<?php // index\n' > "$SRC/pub/index.php"
  printf 'server {}\n' > "$SRC/nginx.conf.sample"

  if [[ "${1:-}" != no-git-keys ]]; then
    set_profile KIT_GIT_REMOTE origin
    set_profile KIT_GIT_BASE_BRANCH master
    set_profile KIT_GIT_TARGET_BRANCH staging
  fi
}

# Write KEY=value into project/profile.env (replace the existing KEY= line).
set_profile() {
  sed -i "s|^$1=.*|$1=$2|" "$ROOT/project/profile.env"
}

wt() {
  run_in "$ROOT" bin/wt "$@"
}

calls() { cat "$KIT_LOG_DIR/docker.log" 2> /dev/null || true; }

test_help() {
  new_root
  wt help
  assert_status 0 'help exits 0'
  assert_contains 'Usage: bin/wt <command>' 'help prints the usage line'
  local cmd
  for cmd in 'create <type>/<slug>' 'use <name|path|branch>' 'list' 'status' 'path' 'prepare' 'shell' 'remove' 'mounts'; do
    assert_contains "$cmd" "help lists '$cmd'"
  done
  wt frobnicate
  assert_status_nonzero 'unknown command exits nonzero'
  assert_contains 'Unknown command: frobnicate' 'the unknown command is named'
}

test_create_from_remote_base() {
  new_root
  # Push one more commit to the remote master that src/ does not have, to prove create
  # fetches and creates from origin/master, not from the local branch.
  local other="$SANDBOX/other"
  git clone -q "$BARE_REMOTE" "$other"
  git -C "$other" config user.name t
  git -C "$other" config user.email t@example.invalid
  git -C "$other" config commit.gpgsign false
  printf 'new\n' > "$other/NEW"
  git -C "$other" add -f NEW
  git -C "$other" commit -q -m 'remote new'
  git -C "$other" push -q origin master
  local remote_sha local_sha
  remote_sha="$(git -C "$other" rev-parse HEAD)"
  local_sha="$(git -C "$SRC" rev-parse master)"
  assert_equals 1 "$([[ "$remote_sha" != "$local_sha" ]] && echo 1 || echo 0)" 'precondition: the local master is behind the remote'

  wt create feature/cart
  local wt_dir="$ROOT/.worktrees/feature-cart"
  assert_status 0 'create exits 0'
  assert_dir "$wt_dir" '<dir> is the branch name with / turned into -'
  assert_equals 'feature/cart' "$(git -C "$wt_dir" rev-parse --abbrev-ref HEAD)" 'the worktree is on the new branch'
  assert_equals "$remote_sha" "$(git -C "$wt_dir" rev-parse HEAD)" 'the branch comes from origin/master after the fetch, not from the local master'
  assert_equals "$local_sha" "$(git -C "$SRC" rev-parse master)" 'the local master is not touched'
  assert_file "$wt_dir/NEW" 'the worktree has the new remote commit'
  assert_symlink_to "$ROOT/.active-src" "$SRC" 'create makes .active-src -> src when missing'
}

test_create_prepares_core_files() {
  new_root
  wt create fix/payment-bug
  local d="$ROOT/.worktrees/fix-payment-bug"
  assert_files_equal "$SRC/app/bootstrap.php" "$d/app/bootstrap.php" 'create copies app/bootstrap.php'
  assert_files_equal "$SRC/pub/index.php" "$d/pub/index.php" 'create copies pub/index.php'
  assert_files_equal "$SRC/app/etc/env.php" "$d/app/etc/env.php" 'create copies app/etc/env.php'
  assert_files_equal "$SRC/nginx.conf.sample" "$d/nginx.conf" 'create generates nginx.conf from nginx.conf.sample'
  assert_equals '' "$(git -C "$d" status --porcelain)" 'a freshly prepared worktree has no dirty or untracked files'
}

test_create_rejects_bad_names() {
  new_root
  local bad
  for bad in 'cart' 'Feature/x' 'feature/' '/x' 'feature/a b' 'feature/..x' 'feature/x.lock' 'feature//x'; do
    wt create "$bad"
    assert_status_nonzero "create refuses the name '$bad'"
  done
  wt create cart
  assert_contains '<type>/<slug>' 'the error names the expected pattern'
  assert_absent "$ROOT/.worktrees" 'a bad name creates nothing'
  assert_absent "$ROOT/.active-src" 'a bad name does not create .active-src'
}

test_create_missing_git_keys() {
  new_root no-git-keys
  wt create feature/x
  assert_status_nonzero 'create stops when the Git keys are missing'
  assert_contains 'KIT_GIT_REMOTE' 'the error names KIT_GIT_REMOTE'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'the error names KIT_GIT_BASE_BRANCH'
  assert_absent "$ROOT/.worktrees/feature-x" 'no worktree is created when a key is missing'
  set_profile KIT_GIT_REMOTE origin
  wt create feature/x
  assert_status_nonzero 'still stops when one key is missing'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'the error names the missing key'
  assert_not_contains 'KIT_GIT_REMOTE' 'the error does not mention the key already set'
}

test_create_bad_ref_after_fetch() {
  new_root
  set_profile KIT_GIT_BASE_BRANCH no-such-branch
  wt create feature/x
  assert_status_nonzero 'create stops when the base branch is not on the remote'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'the error names the key to fix'
  assert_contains 'origin/no-such-branch' 'the error names the missing ref'
  assert_absent "$ROOT/.worktrees/feature-x" 'no worktree is created'
  set_profile KIT_GIT_BASE_BRANCH master
  set_profile KIT_GIT_REMOTE no-such-remote
  wt create feature/x
  assert_status_nonzero 'create stops when the remote is not in src/'
  assert_contains 'KIT_GIT_REMOTE=no-such-remote' 'the error names the wrong remote'
}

test_create_refuses_existing_branch_and_dir() {
  new_root
  wt create feature/a
  assert_status 0 'the first create succeeds'
  wt create feature/a
  assert_status_nonzero 'creating the same name again is refused'
  git -C "$SRC" branch feature/old
  wt create feature/old
  assert_status_nonzero 'an existing local branch is refused, not created from the local branch'
  assert_contains 'already exists' 'the error gives the reason'
}

test_create_review_mr() {
  new_root
  local other="$SANDBOX/other" sha
  git clone -q "$BARE_REMOTE" "$other"
  git -C "$other" config user.name t
  git -C "$other" config user.email t@example.invalid
  git -C "$other" config commit.gpgsign false
  git -C "$other" checkout -q -b mr-seven
  printf 'mr\n' > "$other/MR"
  git -C "$other" add -f MR
  git -C "$other" commit -q -m 'mr 7'
  sha="$(git -C "$other" rev-parse HEAD)"
  git -C "$other" push -q origin "mr-seven:refs/merge-requests/7/head"

  wt create --review-mr 7
  local d="$ROOT/.worktrees/review-mr7"
  assert_status 0 'create --review-mr exits 0'
  assert_dir "$d" 'the review worktree is named review-mr<id>'
  assert_equals 'HEAD' "$(git -C "$d" rev-parse --abbrev-ref HEAD)" 'the review worktree is detached'
  assert_equals "$sha" "$(git -C "$d" rev-parse HEAD)" 'the review worktree is on the MR commit'
  assert_file "$d/MR" 'the review worktree has the MR content'

  wt create --review-mr abc
  assert_status_nonzero 'a non-numeric MR number is refused'
  wt create --review-mr 99
  assert_status_nonzero 'an MR missing on the remote is refused'
  assert_contains '--ref' 'the error suggests --ref'
  wt create --review-mr 8 --ref staging
  assert_status 0 'create --review-mr --ref takes origin/<branch>'
  assert_equals "$(git -C "$SRC" rev-parse origin/staging)" "$(git -C "$ROOT/.worktrees/review-mr8" rev-parse HEAD)" 'review --ref sits on the origin/staging commit'
}

test_use_switches_and_recreates_php_only() {
  new_root
  wt create feature/one
  set_docker_online
  reset_calls
  wt use feature-one
  assert_status 0 'use exits 0 when Docker is online'
  assert_symlink_to "$ROOT/.active-src" "$ROOT/.worktrees/feature-one" 'use points .active-src at the worktree'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' stop app phpfpm$' 'only app and phpfpm are stopped'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' up -d --no-deps --force-recreate app phpfpm$' 'app and phpfpm are recreated'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" ' (stop|up) .*(db|redis|opensearch|rabbitmq)' 'db, redis, search and queue are not touched'
  assert_file_matches "$KIT_LOG_DIR/docker.log" 'exec phpfpm bin/magento cache:clean' 'use clears the Magento cache'
  assert_contains 'Active worktree: feature-one' 'use reports the new worktree'
}

test_use_by_branch_name_and_already_active() {
  new_root
  wt create feature/one
  set_docker_online
  wt use feature/one
  assert_status 0 'use accepts a branch name'
  reset_calls
  wt use feature-one
  assert_status 0 'using the same worktree again exits 0'
  assert_contains 'Already active' 'using it again reports it is already active'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" ' (stop|up) ' 'using it again does not restart'
}

test_use_without_docker() {
  new_root
  wt create feature/one
  reset_calls
  wt use feature-one
  assert_status 0 'use exits 0 when Docker is off'
  assert_symlink_to "$ROOT/.active-src" "$ROOT/.worktrees/feature-one" 'use still changes .active-src'
  assert_contains 'bin/start' 'use reminds to start the stack'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" ' (stop|up) ' 'no restart when Docker is off'
}

test_use_back_to_main() {
  new_root
  wt create feature/one
  wt use feature-one
  wt use main
  assert_status 0 'use main exits 0'
  assert_symlink_to "$ROOT/.active-src" "$SRC" 'use main points back to src/'
}

test_use_rolls_back_on_failure() {
  new_root
  wt create feature/one
  set_docker_online
  reset_calls
  export KIT_TEST_FAIL_UP=1
  wt use feature-one
  unset KIT_TEST_FAIL_UP
  assert_status_nonzero 'use fails when recreating the container fails'
  assert_contains 'Worktree switch cancelled' 'use reports the cancellation'
  assert_symlink_to "$ROOT/.active-src" "$SRC" '.active-src is restored to its old target'
  assert_file_line_count 2 "$KIT_LOG_DIR/docker.log" ' up -d --no-deps --force-recreate ' 'the restore tries the recreate again'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" 'cache:clean' 'a failed switch does not clean the cache'
}

test_use_refuses_outside_paths() {
  new_root
  wt create feature/one
  mkdir -p "$ROOT/.codex-worktrees"
  git -C "$SRC" worktree add -q "$ROOT/.codex-worktrees/agent1" -b agent1
  printf '{}\n' > "$ROOT/.codex-worktrees/agent1/composer.json"
  wt use "$ROOT/.codex-worktrees/agent1"
  assert_status_nonzero 'use refuses a worktree outside .worktrees/'
  assert_contains 'bin/wt adopt' 'the error suggests adopt'
  assert_contains '.codex-worktrees/agent1' 'the error names the refused path'
  wt use agent1
  assert_status_nonzero 'use refuses it even when called by branch name'
  assert_contains 'bin/wt adopt' 'the error suggests adopt when called by branch name'
  local plain="$SANDBOX/not-a-worktree"
  mkdir -p "$plain"
  wt use "$plain"
  assert_status_nonzero 'use refuses an arbitrary directory'
  assert_symlink_to "$ROOT/.active-src" "$SRC" '.active-src is unchanged after the refusals'
}

test_prepare_restores_and_preserves() {
  new_root
  wt create feature/one
  local d="$ROOT/.worktrees/feature-one"
  rm -f "$d/app/etc/env.php" "$d/pub/index.php"
  printf '<?php // custom\n' > "$d/app/bootstrap.php"
  wt prepare feature-one
  assert_status 0 'prepare exits 0'
  assert_files_equal "$SRC/app/etc/env.php" "$d/app/etc/env.php" 'prepare copies app/etc/env.php back'
  assert_files_equal "$SRC/pub/index.php" "$d/pub/index.php" 'prepare copies pub/index.php back'
  assert_equals '<?php // custom' "$(head -n 1 "$d/app/bootstrap.php")" 'prepare keeps an existing file'
  assert_equals '' "$(git -C "$d" status --porcelain)" 'prepare leaves no untracked files'
}

test_prepare_warns_on_lock_mismatch() {
  new_root
  wt create feature/one
  printf '{"content-hash": "b"}\n' > "$ROOT/.worktrees/feature-one/composer.lock"
  wt prepare feature-one
  assert_status 0 'prepare exits 0 when composer.lock differs'
  assert_contains 'composer.lock differs from src/' 'prepare warns that composer.lock differs'
}

test_prepare_runs_agent_install_only_when_present() {
  new_root
  wt create feature/one
  assert_status 0 'create exits 0 when bin/agent is not there yet'
  rm -f "$ROOT/bin/agent"
  cat > "$ROOT/bin/agent" <<'STUB'
#!/usr/bin/env bash
printf 'agent %s cwd=%s\n' "$*" "$PWD" >> "${KIT_LOG_DIR:?}/agent.log"
STUB
  chmod 755 "$ROOT/bin/agent"
  wt prepare feature-one
  assert_status 0 'prepare exits 0 when bin/agent exists'
  assert_file_line "$KIT_LOG_DIR/agent.log" "agent install cwd=$ROOT/.worktrees/feature-one" 'prepare runs bin/agent install in the worktree'
  : > "$KIT_LOG_DIR/agent.log"
  wt prepare main
  assert_equals '' "$(cat "$KIT_LOG_DIR/agent.log")" 'prepare main does not install the agent kit'
}

test_list_marks_active() {
  new_root
  wt create feature/one
  wt use feature-one
  wt list
  assert_status 0 'list exits 0'
  assert_contains 'Active worktree: feature-one' 'list reports the active worktree'
  local line stars=0 star_line=''
  while IFS= read -r line; do
    if [[ "$line" == '*'* ]]; then
      stars=$((stars + 1))
      star_line="$line"
    fi
  done <<< "$OUTPUT"
  assert_equals 1 "$stars" 'list marks exactly one worktree'
  assert_contains 'feature-one' 'the * mark is on the active worktree' "$star_line"
  assert_contains 'main' 'list has the main checkout'
}

test_list_before_any_worktree() {
  new_root
  wt list
  assert_status 0 'list works without .active-src'
  assert_contains 'Active worktree: main' 'without .active-src, src/ is treated as active'
  assert_absent "$ROOT/.active-src" 'list does not create .active-src'
}

test_path_resolves_and_fails() {
  new_root
  wt create feature/dup
  wt create hotfix/dup
  wt path main
  assert_equals "$SRC" "$OUTPUT" 'path main prints src/'
  wt path feature-dup
  assert_equals "$ROOT/.worktrees/feature-dup" "$OUTPUT" 'path accepts a directory name'
  wt path feature/dup
  assert_equals "$ROOT/.worktrees/feature-dup" "$OUTPUT" 'path accepts a branch name'
  wt path missing
  assert_status_nonzero 'path with an unknown name exits nonzero'
  assert_contains 'No worktree named: missing' 'path reports the unknown name'
  wt path dup
  assert_status_nonzero 'path with a nonexistent name exits nonzero'
}

test_status() {
  new_root
  wt create feature/one
  wt use feature-one
  wt status
  assert_status 0 'status exits 0'
  assert_contains 'Active worktree: feature-one' 'status reports the active worktree'
  assert_contains 'Branch: feature/one' 'status reports the branch'
  assert_contains 'Docker daemon is off' 'status reports Docker is off'
  set_docker_online
  reset_calls
  wt status
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' ps$' 'status calls compose ps when Docker is online'
}

test_mounts() {
  new_root
  wt mounts
  assert_status_nonzero 'mounts fails when Docker is off'
  assert_contains 'Docker daemon is off' 'mounts explains it'
  set_docker_online
  reset_calls
  wt mounts
  assert_status 0 'mounts exits 0 when Docker is online'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' config$' 'mounts calls compose config'
}

test_shell() {
  new_root
  wt create feature/one
  cat > "$SANDBOX/.fakebin/stub-shell" <<'STUB'
#!/usr/bin/env bash
printf 'shell-pwd=%s\n' "$PWD"
STUB
  chmod 755 "$SANDBOX/.fakebin/stub-shell"
  SHELL="$SANDBOX/.fakebin/stub-shell" wt shell feature-one
  assert_status 0 'shell exits 0'
  assert_contains "shell-pwd=$ROOT/.worktrees/feature-one" 'shell opens in the worktree'
  wt shell
  assert_status_nonzero 'shell without a name exits nonzero'
  assert_contains 'Usage: bin/wt shell' 'shell without a name prints the usage'
}

test_remove() {
  new_root
  wt create feature/one
  wt remove main
  assert_status_nonzero 'remove refuses the main checkout'
  assert_contains 'Cannot delete the main checkout' 'remove gives the reason'
  wt use feature-one
  wt remove feature-one
  assert_status_nonzero 'remove refuses the active worktree'
  assert_contains 'Cannot delete the active worktree' 'remove gives the reason for the active worktree'
  assert_dir "$ROOT/.worktrees/feature-one" 'the worktree is still there'
  wt use main
  wt remove feature-one
  assert_status 0 'remove deletes an inactive worktree'
  assert_contains 'local branch kept' 'remove reports the kept branch'
  assert_absent "$ROOT/.worktrees/feature-one" 'the worktree directory is gone'
  assert_cmd_status 0 'the local branch is still there' git -C "$SRC" show-ref --verify --quiet refs/heads/feature/one
  assert_dir "$ROOT/.worktrees" '.worktrees/ is still there'
}

test_remove_refuses_dirty_and_outside() {
  new_root
  wt create feature/one
  printf '\n' >> "$ROOT/.worktrees/feature-one/composer.json"
  wt remove feature-one
  assert_status_nonzero 'remove refuses a worktree with modified files'
  assert_dir "$ROOT/.worktrees/feature-one" 'the worktree is kept'
  git -C "$SRC" worktree add -q "$ROOT/outside" -b agent1
  wt remove "$ROOT/outside"
  assert_status_nonzero 'remove refuses a path outside .worktrees/'
  assert_dir "$ROOT/outside" 'the outside worktree is not deleted'
}

test_overlay_mounts_active_src_and_shares_dirs() {
  local f="$KIT_REPO_ROOT/dist/files/compose.worktree.yaml" t
  assert_file_matches "$f" '\./\.active-src:/var/www/html:cached' 'the overlay mounts .active-src at /var/www/html'
  for t in vendor node_modules pub/media; do
    assert_file_matches "$f" "\./src/$t:/var/www/html/$t" "the overlay shares $t from src/"
  done
  for t in app/code app/design app/etc generated var; do
    assert_file_matches "$f" "\./\.active-src/$t:/var/www/html/$t" "the overlay takes $t from the worktree, not shadowed by ./src"
  done
}

test_watch_follows_active_src() {
  command -v node > /dev/null 2>&1 || { pass_ 'skipping the watch test because node is missing'; return 0; }
  new_root
  run_in "$ROOT" node bin/watch --print-target
  assert_equals "$SRC" "$OUTPUT" 'without .active-src, watch follows src/'
  wt create feature/one
  assert_equals "$SRC" "$(cd "$ROOT" && node bin/watch --print-target)" 'with .active-src -> src, watch follows src/'
  wt use feature-one
  run_in "$ROOT" node bin/watch --print-target
  assert_equals "$ROOT/.worktrees/feature-one" "$OUTPUT" 'watch follows the target of .active-src'
}

run_tests
finish
