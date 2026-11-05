#!/usr/bin/env bash
# Test cho tools/release: sinh manifest, phát hiện manifest lệch, phát hành tag.
#
# Usage:  bash tests/test-release.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Một bản sao nhỏ của repo gói trong sandbox, là repo git có một commit.
release_repo_new() {
  sandbox_new
  REPO="$SANDBOX/repo"
  mkdir -p "$REPO/tools" "$REPO/dist/files/bin"
  cp "$KIT_REPO_ROOT/tools/release" "$REPO/tools/release"
  printf '#!/bin/sh\necho hi\n' > "$REPO/dist/files/bin/tool"
  chmod 755 "$REPO/dist/files/bin/tool"
  printf 'x: 1\n' > "$REPO/dist/files/compose.yaml"
  git -c init.defaultBranch=main init -q "$REPO"
  git -C "$REPO" config user.name 'kit tests'
  git -C "$REPO" config user.email 'tests@example.invalid'
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m init
}

test_manifest_lists_path_sha_and_mode() {
  release_repo_new
  run_cmd "$REPO/tools/release" manifest
  assert_status 0 'manifest exits 0'
  local sha
  sha="$(sha256sum "$REPO/dist/files/compose.yaml" | cut -d' ' -f1)"
  assert_file_line "$REPO/dist/manifest" "$sha  644  compose.yaml" 'a plain file is listed with sha256 and mode 644'
  sha="$(sha256sum "$REPO/dist/files/bin/tool" | cut -d' ' -f1)"
  assert_file_line "$REPO/dist/manifest" "$sha  755  bin/tool" 'an executable file is listed with mode 755'
  assert_equals '2' "$(wc -l < "$REPO/dist/manifest" | tr -d ' ')" 'the manifest has one line per file'
}

test_manifest_is_stable() {
  release_repo_new
  "$REPO/tools/release" manifest >/dev/null
  local first
  first="$(cat "$REPO/dist/manifest")"
  "$REPO/tools/release" manifest >/dev/null
  assert_equals "$first" "$(cat "$REPO/dist/manifest")" 'regenerating gives the same manifest'
}

test_check_detects_drift() {
  release_repo_new
  "$REPO/tools/release" manifest >/dev/null
  run_cmd "$REPO/tools/release" check
  assert_status 0 'check passes on a fresh manifest'

  printf 'x: 2\n' > "$REPO/dist/files/compose.yaml"
  run_cmd "$REPO/tools/release" check
  assert_status_nonzero 'check fails when a file content changes'
  assert_contains 'compose.yaml' 'the drifting file is shown'

  "$REPO/tools/release" manifest >/dev/null
  chmod 755 "$REPO/dist/files/compose.yaml"
  run_cmd "$REPO/tools/release" check
  assert_status_nonzero 'check fails when a file mode changes'

  chmod 644 "$REPO/dist/files/compose.yaml"
  printf 'new\n' > "$REPO/dist/files/extra"
  run_cmd "$REPO/tools/release" check
  assert_status_nonzero 'check fails when a file is added'

  rm "$REPO/dist/files/extra" "$REPO/dist/files/compose.yaml"
  run_cmd "$REPO/tools/release" check
  assert_status_nonzero 'check fails when a file is removed'
}

test_check_needs_a_manifest() {
  release_repo_new
  run_cmd "$REPO/tools/release" check
  assert_status_nonzero 'check fails when dist/manifest is missing'
}

test_release_commits_and_tags() {
  release_repo_new
  run_cmd "$REPO/tools/release" v1.2.3
  assert_status 0 'release exits 0'
  assert_equals 'v1.2.3' "$(git -C "$REPO" tag --list)" 'release creates the tag'
  assert_file_line "$REPO/dist/version" 'v1.2.3' 'release writes dist/version'
  assert_equals "$(git -C "$REPO" rev-parse HEAD)" "$(git -C "$REPO" rev-parse 'v1.2.3^{commit}')" 'the tag points at the release commit'
  assert_equals '' "$(git -C "$REPO" status --porcelain)" 'the manifest is committed'
  assert_equals 'dist/manifest
dist/version' "$(git -C "$REPO" show --name-only --format= HEAD | LC_ALL=C sort)" 'the release commit holds only manifest and version'
  assert_cmd_status 0 'check passes after release' "$REPO/tools/release" check
}

test_release_rejects_bad_input() {
  release_repo_new
  run_cmd "$REPO/tools/release" 1.2.3
  assert_status_nonzero 'a version without v is rejected'
  run_cmd "$REPO/tools/release" v1.2
  assert_status_nonzero 'a short version is rejected'
  assert_equals '' "$(git -C "$REPO" tag --list)" 'rejected versions create no tag'

  "$REPO/tools/release" v1.0.0 >/dev/null
  run_cmd "$REPO/tools/release" v1.0.0
  assert_status_nonzero 'an existing tag is not overwritten'

  printf 'dirty\n' >> "$REPO/dist/files/compose.yaml"
  run_cmd "$REPO/tools/release" v1.0.1
  assert_status_nonzero 'release refuses a dirty tracked tree'
  assert_equals 'v1.0.0' "$(git -C "$REPO" tag --list)" 'a refused release creates no tag'
}

test_real_repo_manifest_is_current() {
  run_cmd "$KIT_REPO_ROOT/tools/release" check
  assert_status 0 'dist/manifest of this repo matches dist/files'
}

run_tests
finish
