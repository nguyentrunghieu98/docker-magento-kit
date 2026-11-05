#!/usr/bin/env bash
# S1 tests for `bin/self-update`: Docker root sandbox installed with --source,
# upgrading and downgrading between two package builds in the sandbox, no network needed.
#
# Usage:  bash tests/test-self-update.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Build a new package version at $SANDBOX/<name> from the current checkout: dist/,
# tools/release and (optionally) CHANGELOG.md. Call kit_seal after editing dist/files.
kit_make() {
  local name="$1" version="$2" dir="$SANDBOX/$1"
  mkdir -p "$dir"
  cp -a "$KIT_REPO_ROOT/dist" "$dir/dist"
  cp -a "$KIT_REPO_ROOT/tools" "$dir/tools"
  printf '%s\n' "$version" > "$dir/dist/version"
  kit_seal "$name"
}

# Regenerate the package manifest after editing dist/files.
kit_seal() {
  "$SANDBOX/$1/tools/release" manifest >/dev/null
}

# Install the old build (v1.0.0) into $SANDBOX/shop, prepare the new build (v1.1.0) in $SANDBOX/new.
setup_pair() {
  sandbox_new
  kit_make old v1.0.0
  run_cmd "$KIT_REPO_ROOT/install.sh" new "$SANDBOX/shop" --source "$SANDBOX/old"
  kit_make new v1.1.0
  OLD="$SANDBOX/old"
  NEW="$SANDBOX/new"
  SHOP="$SANDBOX/shop"
}

selfupdate() {
  run_in "$SHOP" bin/self-update "$@"
}

# Tree of the Docker root, excluding backups.
shop_digest() {
  tree_digest "$SHOP" | grep -v '\.kit/backup/'
}

test_update_clean() {
  setup_pair
  printf '# added in v1.1.0\n' >> "$NEW/dist/files/Makefile"
  printf '# v1.1.0\n' >> "$NEW/dist/files/bin/self-update"
  printf '#!/usr/bin/env bash\necho hi\n' > "$NEW/dist/files/bin/newcmd"
  chmod 755 "$NEW/dist/files/bin/newcmd"
  kit_seal new
  printf 'MYSQL_USER=mine\n' > "$SHOP/env/db.env"
  printf 'KIT_DOMAIN=mine.test\n' > "$SHOP/project/profile.env"
  selfupdate --source "$NEW"
  assert_status 0 'a clean update exits 0'
  assert_files_equal "$NEW/dist/files/Makefile" "$SHOP/Makefile" 'an untouched package file is overwritten with the new version'
  assert_files_equal "$NEW/dist/files/bin/self-update" "$SHOP/bin/self-update" 'bin/self-update can replace itself while running'
  assert_executable "$SHOP/bin/newcmd" 'a new package file is written with its mode'
  assert_files_equal "$NEW/dist/manifest" "$SHOP/.kit/manifest" '.kit/manifest becomes the new manifest'
  assert_file_line "$SHOP/.kit/version" 'v1.1.0' '.kit/version becomes the new version'
  assert_file_line "$SHOP/env/db.env" 'MYSQL_USER=mine' 'a project template file is never overwritten'
  assert_file_line "$SHOP/project/profile.env" 'KIT_DOMAIN=mine.test' 'the profile file is never overwritten'
  assert_contains 'Makefile' 'the plan names the changed file'
  assert_contains 'bin/newcmd' 'the plan names the new file'
  assert_absent "$SHOP/.kit/backup" 'a clean update makes no backup'
  assert_docker_not_called 'update never calls docker'
}

test_update_same_version_is_noop() {
  setup_pair
  local before
  before="$(shop_digest)"
  selfupdate --source "$OLD"
  assert_status 0 'updating to the installed version exits 0'
  assert_equals "$before" "$(shop_digest)" 'updating to the installed version changes nothing'
}

test_local_edit_of_unchanged_file_is_kept() {
  setup_pair
  printf '# mine\n' >> "$SHOP/Makefile"
  printf '# v1.1.0\n' >> "$NEW/dist/files/compose.yaml"
  kit_seal new
  selfupdate --source "$NEW"
  assert_status 0 'a local edit to a file the new version did not change is not a conflict'
  assert_file_line "$SHOP/Makefile" '# mine' 'that local edit is kept'
  assert_file_line "$SHOP/compose.yaml" '# v1.1.0' 'other files still update'
}

test_update_conflict_writes_nothing() {
  setup_pair
  printf '# manual edit\n' >> "$SHOP/Makefile"
  printf '# new version\n' >> "$NEW/dist/files/Makefile"
  printf '# new version\n' >> "$NEW/dist/files/compose.yaml"
  kit_seal new
  local before
  before="$(shop_digest)"
  selfupdate --source "$NEW"
  assert_status_nonzero 'a conflict exits non-zero'
  assert_contains 'CONFLICT' 'the plan marks the conflict'
  assert_contains '-# manual edit' 'the conflict prints a diff of the local file against the new version'
  assert_equals "$before" "$(shop_digest)" 'a conflict writes nothing, not even the files without conflict'
  assert_file_line "$SHOP/.kit/version" 'v1.0.0' 'the version is unchanged after a conflict'
}

test_removed_files() {
  setup_pair
  rm -f "$NEW/dist/files/bin/stopall" "$NEW/dist/files/bin/removeall"
  kit_seal new
  printf '# manual edit\n' >> "$SHOP/bin/removeall"
  selfupdate --source "$NEW"
  assert_status 0 'dropped files do not make a conflict'
  assert_absent "$SHOP/bin/stopall" 'a dropped file that was not edited is deleted'
  assert_file_line "$SHOP/bin/removeall" '# manual edit' 'a dropped file that was edited is kept'
  assert_contains 'bin/removeall' 'the warning names the kept file'
  assert_contains 'warning' 'the kept file is reported as a warning'
  assert_not_contains 'bin/removeall' 'the manifest no longer tracks the kept file' "$(cat "$SHOP/.kit/manifest")"
}

test_dry_run_writes_nothing() {
  setup_pair
  printf '# new version\n' >> "$NEW/dist/files/Makefile"
  printf '#!/usr/bin/env bash\n' > "$NEW/dist/files/bin/newcmd"
  chmod 755 "$NEW/dist/files/bin/newcmd"
  rm -f "$NEW/dist/files/bin/stopall"
  kit_seal new
  local before
  before="$(tree_digest "$SHOP")"
  selfupdate --dry-run --source "$NEW"
  assert_status 0 '--dry-run exits 0 when there is no conflict'
  assert_contains 'bin/newcmd' '--dry-run prints the plan'
  assert_equals "$before" "$(tree_digest "$SHOP")" '--dry-run writes nothing'
  printf '# manual edit\n' >> "$SHOP/Makefile"
  before="$(tree_digest "$SHOP")"
  selfupdate --dry-run --source "$NEW"
  assert_status_nonzero '--dry-run still reports a conflict with a non-zero status'
  assert_equals "$before" "$(tree_digest "$SHOP")" '--dry-run with a conflict writes nothing'
}

test_force_backs_up_conflicts() {
  setup_pair
  printf '# manual edit\n' >> "$SHOP/Makefile"
  printf '# new version\n' >> "$NEW/dist/files/Makefile"
  kit_seal new
  selfupdate --force --source "$NEW"
  assert_status 0 '--force finishes despite a conflict'
  assert_files_equal "$NEW/dist/files/Makefile" "$SHOP/Makefile" '--force writes the new version'
  local backup
  backup="$(find "$SHOP/.kit/backup" -type f -name Makefile 2>/dev/null | head -n 1)"
  assert_file_matches "$backup" '^# manual edit$' '--force keeps the local version under .kit/backup/<time>/'
  assert_file_line "$SHOP/.kit/version" 'v1.1.0' '--force records the new version'
  assert_contains '.kit/backup/' 'the backup location is reported'
}

test_rerun_after_interruption() {
  setup_pair
  printf '# new version\n' >> "$NEW/dist/files/Makefile"
  printf '# new version\n' >> "$NEW/dist/files/compose.yaml"
  printf '#!/usr/bin/env bash\n' > "$NEW/dist/files/bin/newcmd"
  chmod 755 "$NEW/dist/files/bin/newcmd"
  rm -f "$NEW/dist/files/bin/stopall"
  kit_seal new
  run_cmd "$KIT_REPO_ROOT/install.sh" new "$SANDBOX/fresh" --source "$NEW"
  # fake mv: let two calls through, then fail, as if interrupted midway.
  # String for the child shell or a fixture, keep the $ characters as they are.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nn=$(cat "%s/mv.count" 2>/dev/null || echo 0)\nn=$((n + 1)); echo "$n" > "%s/mv.count"\n[[ "$n" -le 2 ]] || exit 1\nPATH="%s" exec mv "$@"\n' "$KIT_LOG_DIR" "$KIT_LOG_DIR" "$ORIG_PATH" > "$SANDBOX/.fakebin/mv"
  chmod 755 "$SANDBOX/.fakebin/mv"
  selfupdate --source "$NEW"
  assert_status_nonzero 'an interrupted update fails'
  assert_file_line "$SHOP/.kit/version" 'v1.0.0' 'an interrupted update leaves the old version recorded'
  assert_files_equal "$OLD/dist/manifest" "$SHOP/.kit/manifest" 'an interrupted update leaves the old manifest'
  rm -f "$SANDBOX/.fakebin/mv"
  selfupdate --source "$NEW"
  assert_status 0 'running again after an interruption succeeds with no conflict'
  find "$SHOP" -name '*.kit-tmp.*' -delete
  assert_equals "$(tree_digest "$SANDBOX/fresh")" "$(shop_digest)" 'the rerun gives the same tree as a fresh install of the new version'
}

test_downgrade() {
  setup_pair
  local before
  before="$(shop_digest)"
  printf '# new version\n' >> "$NEW/dist/files/Makefile"
  printf '#!/usr/bin/env bash\n' > "$NEW/dist/files/bin/newcmd"
  chmod 755 "$NEW/dist/files/bin/newcmd"
  rm -f "$NEW/dist/files/bin/stopall"
  kit_seal new
  selfupdate --source "$NEW"
  assert_status 0 'the upgrade works'
  selfupdate --source "$OLD"
  assert_status 0 'downgrading uses the same algorithm and exits 0'
  assert_file_line "$SHOP/.kit/version" 'v1.0.0' 'the downgrade records the old version'
  assert_absent "$SHOP/bin/newcmd" 'a file added by the newer version is removed on downgrade'
  assert_equals "$before" "$(shop_digest)" 'a downgrade restores the old tree'
}

test_compose_reminder() {
  setup_pair
  printf '# v1.1.0\n' >> "$NEW/dist/files/Makefile"
  kit_seal new
  selfupdate --dry-run --source "$NEW"
  assert_not_contains 'bin/restart' 'no restart reminder when no Compose file changes'
  printf '# v1.1.0\n' >> "$NEW/dist/files/compose.yaml"
  kit_seal new
  selfupdate --source "$NEW"
  assert_status 0 'update with a Compose change succeeds'
  assert_contains 'bin/restart' 'a restart is suggested when a Compose file changes'
}

test_changelog_between_versions() {
  setup_pair
  printf '# Changelog\n\n## v1.2.0\n- three\n\n## v1.1.0\n- two\n\n## v1.0.0\n- one\n' > "$NEW/CHANGELOG.md"
  printf '# v1.1.0\n' >> "$NEW/dist/files/Makefile"
  kit_seal new
  selfupdate --source "$NEW"
  assert_status 0 'update with a changelog succeeds'
  assert_contains '- two' 'the changelog shows the target version'
  assert_not_contains '- one' 'the changelog omits the installed version and older'
  assert_not_contains '- three' 'the changelog omits versions newer than the target'
}

test_profile_missing_keys() {
  setup_pair
  printf '\n# New port.\n# KIT_NEW_PORT=4242\nKIT_NEW_REQUIRED=\n' >> "$NEW/dist/templates/project/profile.env"
  printf '# v1.1.0\n' >> "$NEW/dist/files/Makefile"
  kit_seal new
  local before
  before="$(cat "$SHOP/project/profile.env")"
  selfupdate --source "$NEW"
  assert_status 0 'update with new template keys succeeds'
  assert_contains 'KIT_NEW_PORT=4242' 'a missing key is printed with its default'
  assert_contains 'KIT_NEW_REQUIRED=' 'a missing required key is printed'
  assert_not_contains 'KIT_PHP_VERSION' 'keys already in the profile are not reported'
  assert_equals "$before" "$(cat "$SHOP/project/profile.env")" 'the profile file is not written'
}

test_new_template_created_only_when_missing() {
  setup_pair
  printf 'X=1\n' > "$NEW/dist/templates/env/extra.env"
  printf 'MYSQL_USER=new\n' > "$NEW/dist/templates/env/db.env"
  printf 'MYSQL_USER=mine\n' > "$SHOP/env/db.env"
  printf '# v1.1.0\n' >> "$NEW/dist/files/Makefile"
  kit_seal new
  selfupdate --source "$NEW"
  assert_status 0 'update with new templates succeeds'
  assert_file_line "$SHOP/env/extra.env" 'X=1' 'a template that is missing is created'
  assert_file_line "$SHOP/env/db.env" 'MYSQL_USER=mine' 'a template that exists is never overwritten'
}

test_requires_managed_root() {
  sandbox_new
  mkdir -p "$SANDBOX/plain/bin/lib"
  cp "$KIT_REPO_ROOT/dist/files/bin/self-update" "$SANDBOX/plain/bin/self-update"
  cp "$KIT_REPO_ROOT/dist/files/bin/lib/kit-core.sh" "$SANDBOX/plain/bin/lib/kit-core.sh"
  run_in "$SANDBOX/plain" bin/self-update --source "$KIT_REPO_ROOT"
  assert_status_nonzero 'self-update fails outside a managed Docker root'
  assert_contains 'adopt' 'the failure points to install.sh adopt'
}

test_argument_errors() {
  setup_pair
  selfupdate --nope
  assert_status_nonzero 'an unknown option fails'
  selfupdate --version 1.2
  assert_status_nonzero 'a malformed --version fails'
  selfupdate --source "$SANDBOX/missing"
  assert_status_nonzero 'a missing --source fails'
}

test_tampered_source_is_rejected() {
  setup_pair
  printf '# new version\n' >> "$NEW/dist/files/Makefile"
  kit_seal new
  printf '# sneaky\n' >> "$NEW/dist/files/Makefile"
  local before
  before="$(tree_digest "$SHOP")"
  selfupdate --source "$NEW"
  assert_status_nonzero 'a source that differs from its manifest is rejected'
  assert_equals "$before" "$(tree_digest "$SHOP")" 'nothing is written for a bad source'
}

run_tests
finish
