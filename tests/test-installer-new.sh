#!/usr/bin/env bash
# S1 test for `install.sh new`: a sandbox Docker root installed from --source, no network.
#
# Usage:  bash tests/test-installer-new.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

DIST="$KIT_REPO_ROOT/dist"

# The paths `new` must create, sorted.
expected_files() {
  {
    awk '{print $3}' "$DIST/manifest"
    (cd "$DIST/templates" && find . -type f | sed 's|^\./||')
    printf '%s\n' .kit/version .kit/manifest
  } | LC_ALL=C sort
}

actual_files() {
  (cd "$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

# Fake `curl` for the download path: log the URL, serve a prepared tag list and tarball.
fake_curl_install() {
  cat > "$SANDBOX/.fakebin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "${KIT_LOG_DIR:?}/curl.log"
out=''
url=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  *"/tags?"*) cat "${KIT_FAKE_TAGS:?}" ;;
  *"/archive/refs/tags/"*) cp "${KIT_FAKE_TARBALL:?}" "$out" ;;
  *) exit 22 ;;
esac
STUB
  chmod 755 "$SANDBOX/.fakebin/curl"
}

make_tarball() {
  local top="$1" out="$2" stage="$SANDBOX/.tarstage"
  rm -rf "$stage"
  mkdir -p "$stage/$top"
  cp -a "$DIST" "$stage/$top/dist"
  tar -czf "$out" -C "$stage" "$top"
}

test_new_writes_exact_file_list() {
  sandbox_new
  kit_new shop
  assert_status 0 'new exits 0 into a fresh directory'
  assert_equals "$(expected_files)" "$(actual_files "$SANDBOX/shop")" 'new writes exactly package files, templates and .kit state'
  assert_absent "$SANDBOX/shop/.git" 'new does not git init the Docker root'
  assert_absent "$SANDBOX/shop/src" 'new does not create src/'
  assert_docker_not_called 'new never calls docker'
}

test_new_file_modes() {
  sandbox_new
  kit_new shop
  local sum mode path bad=''
  while read -r sum mode path; do
    if [[ "$mode" == 755 && ! -x "$SANDBOX/shop/$path" ]]; then bad+=" $path(x)"; fi
    if [[ "$mode" == 644 && -x "$SANDBOX/shop/$path" ]]; then bad+=" $path(-x)"; fi
  done < "$DIST/manifest"
  assert_equals '' "$bad" 'every package file has the executable bit given by the manifest'
  assert_executable "$SANDBOX/shop/bin/magento" 'bin/magento is executable'
  assert_executable "$SANDBOX/shop/bin/docker-compose" 'bin/docker-compose is executable'
  assert_not_executable "$SANDBOX/shop/compose.yaml" 'compose.yaml is not executable'
  assert_not_executable "$SANDBOX/shop/env/db.env" 'templates are not executable'
}

test_new_manifest_matches_checksums() {
  sandbox_new
  kit_new shop
  local sum mode path bad=''
  while read -r sum mode path; do
    if [[ "$(sha256sum "$SANDBOX/shop/$path" | cut -d' ' -f1)" != "$sum" ]]; then bad+=" $path"; fi
  done < "$SANDBOX/shop/.kit/manifest"
  assert_equals '' "$bad" 'every installed file matches its checksum in .kit/manifest'
  assert_files_equal "$DIST/manifest" "$SANDBOX/shop/.kit/manifest" '.kit/manifest is the release manifest'
  assert_equals "$(tr -d '[:space:]' < "$DIST/version")" "$(tr -d '[:space:]' < "$SANDBOX/shop/.kit/version")" '.kit/version defaults to dist/version'
}

test_new_template_files() {
  sandbox_new
  kit_new shop
  assert_file "$SANDBOX/shop/.gitignore" 'new creates the .gitignore template'
  assert_file_line "$SANDBOX/shop/.gitignore" '.kit/backup/' '.gitignore ignores .kit/backup/'
  assert_file_line "$SANDBOX/shop/.gitignore" 'src/' '.gitignore ignores src/'
  assert_file "$SANDBOX/shop/env/db.env" 'new creates env/db.env from the template'
  assert_file "$SANDBOX/shop/project/profile.env" 'new creates project/profile.env from the template'
}

test_new_keeps_existing_template_files() {
  sandbox_new
  mkdir -p "$SANDBOX/shop/env" "$SANDBOX/shop/src"
  printf 'MYSQL_USER=mine\n' > "$SANDBOX/shop/env/db.env"
  printf 'keep\n' > "$SANDBOX/shop/src/index.php"
  kit_new shop
  assert_status 0 'new accepts a directory with only project files'
  assert_file_line "$SANDBOX/shop/env/db.env" 'MYSQL_USER=mine' 'an existing template target is never overwritten'
  assert_file_line "$SANDBOX/shop/src/index.php" 'keep' 'new does not touch src/'
}

test_new_prints_next_steps() {
  sandbox_new
  kit_new shop
  assert_contains 'bin/download' 'new prints the download step'
  assert_contains 'bin/setup' 'new prints the setup step'
  assert_contains "$SANDBOX/shop" 'new names the target directory'
}

test_new_refuses_existing_package_files() {
  sandbox_new
  kit_new shop
  local before after
  before="$(tree_digest "$SANDBOX/shop")"
  kit_new shop
  assert_status_nonzero 'a second new into the same directory fails'
  assert_contains 'adopt' 'the refusal suggests adopt'
  assert_contains 'Makefile' 'the refusal names package files'
  after="$(tree_digest "$SANDBOX/shop")"
  assert_equals "$before" "$after" 'a refused new changes nothing'
}

test_new_refuses_partial_package() {
  sandbox_new
  mkdir -p "$SANDBOX/shop/bin"
  printf 'custom\n' > "$SANDBOX/shop/bin/start"
  kit_new shop
  assert_status_nonzero 'new refuses when even one package file exists'
  assert_contains 'adopt' 'partial refusal suggests adopt'
  assert_file_line "$SANDBOX/shop/bin/start" 'custom' 'the existing file is left as it was'
  assert_absent "$SANDBOX/shop/.kit" 'a refused new writes no .kit state'
}

test_new_is_deterministic() {
  sandbox_new
  kit_new one
  kit_new two
  assert_equals "$(tree_digest "$SANDBOX/one")" "$(tree_digest "$SANDBOX/two")" 'two installs give identical trees'
}

test_new_version_flag() {
  sandbox_new
  kit_new shop --version v1.2.3
  assert_status 0 'new accepts --version with --source'
  assert_file_line "$SANDBOX/shop/.kit/version" 'v1.2.3' '--version is recorded in .kit/version'
  kit_new bad --version 1.2
  assert_status_nonzero 'a malformed --version is rejected'
  assert_absent "$SANDBOX/bad" 'a rejected --version writes nothing'
}

test_new_from_tarball_source() {
  sandbox_new
  make_tarball magento-docker-kit-1.0.0 "$SANDBOX/kit.tar.gz"
  run_installer new "$SANDBOX/shop" --source "$SANDBOX/kit.tar.gz"
  assert_status 0 'new accepts a tarball as --source'
  assert_equals "$(expected_files)" "$(actual_files "$SANDBOX/shop")" 'a tarball source gives the same file list'
  assert_executable "$SANDBOX/shop/bin/magento" 'a tarball source keeps the executable bit'
}

test_new_rejects_tampered_source() {
  sandbox_new
  mkdir -p "$SANDBOX/kitsrc"
  cp -a "$DIST" "$SANDBOX/kitsrc/dist"
  printf '# tampered\n' >> "$SANDBOX/kitsrc/dist/files/Makefile"
  run_installer new "$SANDBOX/shop" --source "$SANDBOX/kitsrc"
  assert_status_nonzero 'a source that differs from its manifest is rejected'
  assert_contains 'Makefile' 'the mismatching file is named'
  assert_absent "$SANDBOX/shop" 'nothing is written when the source is bad'
}

test_new_argument_errors() {
  sandbox_new
  run_installer new --source "$KIT_REPO_ROOT"
  assert_status_nonzero 'new without <dir> fails'
  run_installer new "$SANDBOX/shop" --source "$SANDBOX/does-not-exist"
  assert_status_nonzero 'a missing --source fails'
  run_installer frobnicate
  assert_status_nonzero 'an unknown command fails'
  run_installer new "$SANDBOX/shop" --nope
  assert_status_nonzero 'an unknown option fails'
}

test_new_downloads_latest_tag_by_default() {
  sandbox_new
  fake_curl_install
  make_tarball magento-docker-kit-1.10.0 "$SANDBOX/kit.tar.gz"
  export KIT_FAKE_TARBALL="$SANDBOX/kit.tar.gz"
  printf '[{"name":"v1.9.0"},{"name":"v1.10.0"},{"name":"v0.3.1"},{"name":"nightly"}]\n' > "$SANDBOX/tags.json"
  export KIT_FAKE_TAGS="$SANDBOX/tags.json"
  run_installer new "$SANDBOX/shop"
  assert_status 0 'new without --source downloads the release'
  assert_file_line "$SANDBOX/shop/.kit/version" 'v1.10.0' 'the default is the highest semver tag, not the highest string'
  assert_file_matches "$KIT_LOG_DIR/curl.log" 'archive/refs/tags/v1\.10\.0\.tar\.gz' 'the tarball is fetched by tag'
  assert_equals "$(expected_files)" "$(actual_files "$SANDBOX/shop")" 'a downloaded install gives the same file list'
}

test_new_downloads_pinned_version() {
  sandbox_new
  fake_curl_install
  make_tarball magento-docker-kit-1.9.0 "$SANDBOX/kit.tar.gz"
  export KIT_FAKE_TARBALL="$SANDBOX/kit.tar.gz"
  export KIT_FAKE_TAGS="$SANDBOX/never-read"
  run_installer new "$SANDBOX/shop" --version v1.9.0
  assert_status 0 'new --version downloads that tag'
  assert_file_line "$SANDBOX/shop/.kit/version" 'v1.9.0' 'the pinned tag is recorded'
  assert_file_does_not_match "$KIT_LOG_DIR/curl.log" '/tags\?' 'a pinned version does not list tags'
}

test_new_needs_no_git() {
  sandbox_new
  # PATH holds .fakebin and a directory with only the required tools, no git.
  local tool bin="$SANDBOX/.nogit"
  mkdir -p "$bin"
  for tool in bash cat cp chmod cut dirname find grep mkdir mktemp mv pwd rm sed sha256sum sort tail tar tr awk readlink env; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  local saved="$PATH"
  PATH="$bin"
  run_cmd "$KIT_REPO_ROOT/install.sh" new "$SANDBOX/shop" --source "$KIT_REPO_ROOT"
  PATH="$saved"
  assert_status 0 'new works with no git on PATH'
  assert_file "$SANDBOX/shop/.kit/manifest" 'the install completes without git'
}

run_tests
finish
