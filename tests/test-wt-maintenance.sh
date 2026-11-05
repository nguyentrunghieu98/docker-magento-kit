#!/usr/bin/env bash
# S1 test for bin/wt adopt, prune and doctor. The Docker root is installed with install.sh
# new --source, git is real with a bare remote having master and staging, and docker is a
# fake that logs. Covers: adopt from an outside path, prune with a clean merged worktree,
# with changes, not merged, review and outside the standard location, doctor reporting a
# wrong mount, a base_url mismatch, an unknown key and a missing required key.
#
# Usage:  bash tests/test-wt-maintenance.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Fake docker: `docker info` follows the online flag, `compose ps -q phpfpm` returns an id,
# `docker inspect` returns $KIT_TEST_MOUNT_SRC, and an exec command with core_config_data
# returns $KIT_TEST_BASE_URL (standing in for bin/mysql).
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
  *'ps -q phpfpm'*) printf 'cid-phpfpm\n' ;;
  inspect*) printf '%s\n' "${KIT_TEST_MOUNT_SRC:-}" ;;
  *core_config_data*) printf '%s\n' "${KIT_TEST_BASE_URL:-}" ;;
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
  # staging starts from the same base branch tree, like a real project that already has .gitignore.
  git -C "$SRC" push -q origin master:staging

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

# Push the commit to the remote staging so the branch counts as merged.
merge_into_staging() {
  git -C "$SRC" push -q origin "$1:staging"
}

# Create a <branch> worktree with bin/wt, add one commit then return the path via WT_DIR.
make_commit_wt() {
  local branch="$1" dir="${1//\//-}"
  wt create "$branch"
  WT_DIR="$ROOT/.worktrees/$dir"
  git -C "$WT_DIR" config user.name t
  git -C "$WT_DIR" config user.email t@example.invalid
  git -C "$WT_DIR" config commit.gpgsign false
  printf '%s\n' "$branch" > "$WT_DIR/CHANGE-$dir"
  git -C "$WT_DIR" add -f "CHANGE-$dir"
  git -C "$WT_DIR" commit -q -m "change $branch"
}

test_adopt_moves_outside_worktree() {
  new_root
  git -C "$SRC" worktree add -q "$ROOT/outside" -b feature/misplaced
  wt use "$ROOT/outside"
  assert_status_nonzero 'use still refuses the outside path'
  wt adopt "$ROOT/outside"
  assert_status 0 'adopt exits 0'
  assert_dir "$ROOT/.worktrees/feature-misplaced" 'the worktree is in .worktrees/<dir>'
  assert_absent "$ROOT/outside" 'the old directory was moved away'
  assert_equals 'feature/misplaced' "$(git -C "$ROOT/.worktrees/feature-misplaced" rev-parse --abbrev-ref HEAD)" 'the branch is unchanged'
  assert_file "$ROOT/.worktrees/feature-misplaced/app/etc/env.php" 'adopt runs prepare, env.php is there'
  assert_file "$ROOT/.worktrees/feature-misplaced/nginx.conf" 'adopt runs prepare, nginx.conf is there'
  assert_contains 'bin/wt use' 'adopt suggests the next step'
  wt use feature-misplaced
  assert_status 0 'use works after adopt'
}

test_adopt_detached_and_refusals() {
  new_root
  git -C "$SRC" worktree add -q --detach "$ROOT/outside-rv" HEAD
  wt adopt "$ROOT/outside-rv"
  assert_status 0 'adopt worktree detached'
  assert_dir "$ROOT/.worktrees/outside-rv" 'a detached worktree takes the original directory name'
  wt adopt "$ROOT/missing"
  assert_status_nonzero 'adopt refuses a path that does not exist'
  mkdir "$SANDBOX/odd"
  wt adopt "$SANDBOX/odd"
  assert_status_nonzero 'adopt refuses a directory that is not a worktree of src/'
  assert_contains 'Not a worktree' 'adopt gives the reason'
  wt adopt "$SRC"
  assert_status_nonzero 'adopt refuses the main checkout'
  git -C "$SRC" worktree add -q "$ROOT/outside2" -b feature/duplicate
  wt create feature/duplicate2
  mkdir -p "$ROOT/.worktrees/feature-duplicate"
  wt adopt "$ROOT/outside2"
  assert_status_nonzero 'adopt refuses when the target already exists'
  assert_dir "$ROOT/outside2" 'the worktree is not moved when the target is taken'
}

test_adopt_refuses_active() {
  new_root
  git -C "$SRC" worktree add -q "$ROOT/outside" -b feature/serving
  ln -s "$ROOT/outside" "$ROOT/.active-src"
  wt adopt "$ROOT/outside"
  assert_status_nonzero 'adopt refuses the active worktree'
  assert_contains 'This worktree is active' 'adopt gives the reason'
  assert_dir "$ROOT/outside" 'it is not moved'
}

test_prune_selects_by_state() {
  new_root
  make_commit_wt feature/merged
  make_commit_wt feature/unmerged
  make_commit_wt feature/dirty
  printf 'dirty\n' >> "$ROOT/.worktrees/feature-dirty/composer.json"
  wt create --review-mr 7 --ref staging
  git -C "$SRC" worktree add -q "$ROOT/outside" -b feature/outside-unmerged
  merge_into_staging feature/merged
  local before_branches
  before_branches="$(git -C "$SRC" branch --format='%(refname:short)' | sort)"

  wt prune --dry-run
  assert_status 0 'prune --dry-run exits 0'
  local out="$OUTPUT" listed
  # The "Will delete" part comes before the "Has changes" part.
  listed="${out%%Has changes*}"
  if [[ "$listed" == *feature-merged* ]]; then
    pass_ 'dry run lists the clean merged worktree'
  else
    fail_ 'dry run is missing the merged worktree'
  fi
  if [[ "$listed" == *review-mr7* ]]; then
    pass_ 'dry run lists the review worktree'
  else
    fail_ 'dry run is missing the review worktree'
  fi
  if [[ "$listed" != *feature-unmerged* && "$listed" != *feature-dirty* ]]; then
    pass_ 'the delete part holds neither the unmerged nor the dirty worktree'
  else
    fail_ 'the delete part includes a worktree that must not be deleted'
  fi
  local dirty_part="${out#*Has changes}"
  dirty_part="${dirty_part%%Outside .worktrees*}"
  if [[ "$dirty_part" == *feature-dirty* ]]; then
    pass_ 'the worktree with changes is in the report-only list'
  else
    fail_ 'the worktree with changes is not reported'
  fi
  local outside_part="${out#*Outside .worktrees}"
  if [[ "$outside_part" == *outside* && "$outside_part" == *'bin/wt adopt'* ]]; then
    pass_ 'the unmerged worktree outside the standard location suggests adopt'
  else
    fail_ 'missing the adopt hint for the outside worktree'
  fi
  assert_dir "$ROOT/.worktrees/feature-merged" 'dry run deleted nothing (merged)'
  assert_dir "$ROOT/.worktrees/review-mr7" 'dry run deleted nothing (review)'

  wt prune
  assert_status 0 'prune exits 0'
  assert_absent "$ROOT/.worktrees/feature-merged" 'prune deletes the clean merged worktree'
  assert_absent "$ROOT/.worktrees/review-mr7" 'prune deletes the review worktree'
  assert_dir "$ROOT/.worktrees/feature-unmerged" 'prune keeps the unmerged worktree'
  assert_dir "$ROOT/.worktrees/feature-dirty" 'prune keeps the worktree with changes'
  assert_dir "$ROOT/outside" 'prune leaves the worktree outside the standard location alone'
  assert_equals "$before_branches" "$(git -C "$SRC" branch --format='%(refname:short)' | sort)" 'prune keeps every branch'
}

test_prune_skips_dirty_review_and_active() {
  new_root
  make_commit_wt feature/active
  merge_into_staging feature/active
  wt create --review-mr 9 --ref staging
  printf 'x\n' >> "$ROOT/.worktrees/review-mr9/composer.json"
  wt use feature-active
  wt prune
  assert_status 0 'prune exits 0'
  assert_dir "$ROOT/.worktrees/feature-active" 'the active worktree is not deleted even when merged'
  assert_dir "$ROOT/.worktrees/review-mr9" 'the review worktree with uncommitted changes is not deleted'
}

test_prune_needs_git_keys() {
  new_root no-git-keys
  wt prune --dry-run
  assert_status_nonzero 'prune stops when the Git keys are missing'
  assert_contains 'KIT_GIT_REMOTE' 'it names the key to fix'
  new_root
  set_profile KIT_GIT_TARGET_BRANCH no-such-branch
  wt prune --dry-run
  assert_status_nonzero 'it stops when the target ref does not exist'
  assert_contains 'KIT_GIT_TARGET_BRANCH' 'it names the key to fix when the ref is missing'
  wt prune --nope
  assert_status_nonzero 'prune refuses an unknown argument'
}

test_doctor_mount_mismatch() {
  new_root
  set_docker_online
  wt create feature/one
  wt use feature-one
  export KIT_TEST_MOUNT_SRC="$SRC"
  export KIT_TEST_BASE_URL='https://shop.test/'
  wt doctor
  assert_status_nonzero 'doctor exits nonzero when the mount is wrong'
  assert_contains "mounts $SRC" 'doctor names the real mount'
  assert_contains "$ROOT/.worktrees/feature-one" 'doctor names the target of .active-src'
  export KIT_TEST_MOUNT_SRC="$ROOT/.worktrees/feature-one"
  : > "$KIT_LOG_DIR/docker.log"
  wt doctor
  assert_status 0 'doctor exits 0 when the mount is right and base_url matches'
  assert_contains 'phpfpm mounts the right path' 'doctor confirms the mount'
  assert_contains 'base_url matches KIT_DOMAIN' 'doctor confirms base_url'
  assert_contains 'docker inspect' 'doctor uses docker inspect' "$(cat "$KIT_LOG_DIR/docker.log")"
  assert_equals 1 "$(grep -c '^docker inspect' "$KIT_LOG_DIR/docker.log")" 'doctor calls docker inspect once'
  unset KIT_TEST_MOUNT_SRC KIT_TEST_BASE_URL
}

test_doctor_base_url_mismatch() {
  new_root
  set_docker_online
  export KIT_TEST_MOUNT_SRC="$SRC"
  export KIT_TEST_BASE_URL='https://old.example.com:8443/'
  wt doctor
  assert_status_nonzero 'doctor exits nonzero when base_url differs'
  assert_contains 'old.example.com' 'doctor names the base_url in the DB'
  assert_contains 'KIT_DOMAIN=shop.test' 'doctor names KIT_DOMAIN'
  unset KIT_TEST_MOUNT_SRC KIT_TEST_BASE_URL
}

test_doctor_profile_keys() {
  new_root
  printf 'KIT_TYPO_KEY=1\n' >> "$ROOT/project/profile.env"
  set_profile KIT_GIT_TARGET_BRANCH ''
  wt doctor
  assert_status_nonzero 'doctor exits nonzero on an unknown key and a missing key'
  assert_contains 'Unknown key KIT_TYPO_KEY' 'doctor reports the unknown key'
  assert_contains 'Missing required key KIT_GIT_TARGET_BRANCH' 'doctor reports the missing required key'
  assert_docker_not_called 'doctor stops before the Docker checks when the profile is invalid'
}

test_doctor_clean_offline() {
  new_root
  wt doctor
  assert_status 0 'doctor exits 0 when the profile is complete and docker is off'
  assert_contains 'SKIPPED: Docker daemon is off' 'doctor says what was skipped'
}

run_tests
finish
