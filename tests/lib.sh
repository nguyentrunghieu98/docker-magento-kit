#!/usr/bin/env bash
# tests/lib.sh - shared bash test library, depending on nothing but bash,
# coreutils and git. Source this file from each tests/test-*.sh.
#
# Seam S1 (Docker root sandbox): sandbox_new creates a temp directory, puts a fake
# `docker` at the front of PATH to log each command, and (when needed) sets up a
# bare git remote with `master` and `staging`. Tests only look at outside behavior:
# files created, exit codes, stdout and the docker commands called.
#
# Lifted from tests/test-magento-wt.sh of the Format project (assert_* functions,
# mktemp sandbox, fake docker).

KIT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORIG_PATH="$PATH"

CHECKS=0
PASSED=0
FAILED=0
SANDBOXES=()
SANDBOX=''
OUTPUT=''
STATUS=0

# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

_snippet() {
  local text="${1:-}"
  text="${text//$'\n'/ | }"
  printf '%s' "${text:0:400}"
}

pass_() {
  CHECKS=$((CHECKS + 1))
  PASSED=$((PASSED + 1))
  printf 'ok %d - %s\n' "$CHECKS" "$1"
}

fail_() {
  local desc="$1" detail="${2:-}"
  CHECKS=$((CHECKS + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CHECKS" "$desc"
  if [[ -n "$detail" ]]; then
    printf '#   %s\n' "${detail//$'\n'/$'\n'#   }"
  fi
  return 0
}

# Print the summary and return an exit code: 0 when every check passes, 1 otherwise.
finish() {
  printf '1..%d\n# %d passed, %d failed\n' "$CHECKS" "$PASSED" "$FAILED"
  [[ "$FAILED" -eq 0 ]]
}

# --------------------------------------------------------------------------
# assert_*
# --------------------------------------------------------------------------

assert_status() {
  local want="$1" desc="$2"
  if [[ "$STATUS" -eq "$want" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "expected exit status $want, got $STATUS; output: $(_snippet "$OUTPUT")"
  fi
}

assert_status_nonzero() {
  local desc="$1"
  if [[ "$STATUS" -ne 0 ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "expected a non-zero exit status, got 0; output: $(_snippet "$OUTPUT")"
  fi
}

assert_equals() {
  local want="$1" got="$2" desc="$3"
  if [[ "$want" == "$got" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "expected [$want], got [$got]"
  fi
}

assert_contains() {
  local needle="$1" desc="$2" hay="${3-$OUTPUT}"
  if [[ "$hay" == *"$needle"* ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "expected [$needle] in: $(_snippet "$hay")"
  fi
}

assert_not_contains() {
  local needle="$1" desc="$2" hay="${3-$OUTPUT}"
  if [[ "$hay" != *"$needle"* ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "did not expect [$needle] in: $(_snippet "$hay")"
  fi
}

assert_file() {
  local path="$1" desc="$2"
  if [[ -f "$path" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "missing file: $path"
  fi
}

assert_dir() {
  local path="$1" desc="$2"
  if [[ -d "$path" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "missing directory: $path"
  fi
}

assert_absent() {
  local path="$1" desc="$2"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "unexpected path exists: $path"
  fi
}

assert_executable() {
  local path="$1" desc="$2"
  if [[ -f "$path" && -x "$path" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "not an executable file: $path"
  fi
}

assert_not_executable() {
  local path="$1" desc="$2"
  if [[ -f "$path" && ! -x "$path" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "missing or executable: $path"
  fi
}

assert_symlink_to() {
  local link="$1" want="$2" desc="$3" got=''
  [[ -L "$link" ]] && got="$(readlink "$link")"
  if [[ "$got" == "$want" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "symlink $link -> [$got], expected [$want]"
  fi
}

assert_files_equal() {
  local left="$1" right="$2" desc="$3"
  if [[ -f "$left" && -f "$right" ]] && cmp -s "$left" "$right"; then
    pass_ "$desc"
  else
    fail_ "$desc" "$left and $right differ or are missing"
  fi
}

assert_cmd_status() {
  local want="$1" desc="$2"
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  assert_equals "$want" "$got" "$desc"
}

assert_file_line() {
  local file="$1" line="$2" desc="$3"
  if [[ -f "$file" ]] && grep -Fxq -- "$line" "$file"; then
    pass_ "$desc"
  else
    fail_ "$desc" "expected line [$line] in $file; content: $(_snippet "$(cat "$file" 2>/dev/null || true)")"
  fi
}

assert_file_matches() {
  local file="$1" regex="$2" desc="$3"
  if [[ -f "$file" ]] && grep -Eq -- "$regex" "$file"; then
    pass_ "$desc"
  else
    fail_ "$desc" "expected /$regex/ in $file; content: $(_snippet "$(cat "$file" 2>/dev/null || true)")"
  fi
}

assert_file_does_not_match() {
  local file="$1" regex="$2" desc="$3"
  if [[ ! -f "$file" ]] || ! grep -Eq -- "$regex" "$file"; then
    pass_ "$desc"
  else
    fail_ "$desc" "unexpected /$regex/ in $file; content: $(_snippet "$(cat "$file" 2>/dev/null || true)")"
  fi
}

assert_file_line_count() {
  local want="$1" file="$2" regex="$3" desc="$4" got=0
  if [[ -f "$file" ]]; then
    got="$(grep -Ec -- "$regex" "$file" || true)"
  fi
  assert_equals "$want" "$got" "$desc"
}

# Assert a docker command (through the fake docker) was called / was not called.
assert_docker_called() {
  local needle="$1" desc="$2"
  assert_file_matches "$KIT_LOG_DIR/docker.log" "$(printf '%s' "$needle" | sed 's/[][\.*^$/]/\\&/g')" "$desc"
}

assert_docker_not_called() {
  local desc="$1"
  if [[ ! -s "$KIT_LOG_DIR/docker.log" ]]; then
    pass_ "$desc"
  else
    fail_ "$desc" "docker was called: $(_snippet "$(cat "$KIT_LOG_DIR/docker.log")")"
  fi
}

# --------------------------------------------------------------------------
# Sandbox
# --------------------------------------------------------------------------

cleanup_sandboxes() {
  local dir
  for dir in "${SANDBOXES[@]}"; do
    if [[ -n "$dir" && -d "$dir" ]]; then
      rm -rf "$dir"
    fi
  done
  SANDBOXES=()
  return 0
}
trap cleanup_sandboxes EXIT

# Temp directory with a fake .fakebin/docker and .logs/. Sets SANDBOX, KIT_LOG_DIR, PATH.
# The fake docker writes `docker <args>` to .logs/docker.log and never talks to the
# daemon. `docker info` exits 0 while $KIT_DOCKER_ONLINE exists.
sandbox_new() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/kit-test.XXXXXX")"
  SANDBOX="$(realpath "$SANDBOX")"
  SANDBOXES+=("$SANDBOX")

  mkdir -p "$SANDBOX/.fakebin" "$SANDBOX/.logs"
  export KIT_LOG_DIR="$SANDBOX/.logs"
  export KIT_DOCKER_ONLINE="$SANDBOX/.docker-online"
  export PATH="$SANDBOX/.fakebin:$ORIG_PATH"

  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
# Fake docker: log the command, never talk to the daemon.
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
if [[ "${1:-}" == 'info' ]]; then
  [[ -e "${KIT_DOCKER_ONLINE:?}" ]] && exit 0
  exit 1
fi
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
}

set_docker_online() { : > "$KIT_DOCKER_ONLINE"; }
set_docker_offline() { rm -f "$KIT_DOCKER_ONLINE"; }
reset_calls() { rm -f "$KIT_LOG_DIR"/*.log; }

# Set up a bare git remote in the sandbox with master and staging branches, one
# commit each. Sets BARE_REMOTE. Uses real git.
git_remote_new() {
  BARE_REMOTE="$SANDBOX/remote.git"
  local seed="$SANDBOX/.seed"
  git -c init.defaultBranch=master init -q --bare "$BARE_REMOTE"
  git -c init.defaultBranch=master init -q "$seed"
  git -C "$seed" config user.name 'kit tests'
  git -C "$seed" config user.email 'tests@example.invalid'
  git -C "$seed" config commit.gpgsign false
  printf 'seed\n' > "$seed/README"
  git -C "$seed" add README
  git -C "$seed" commit -q -m 'seed'
  git -C "$seed" branch staging
  git -C "$seed" remote add origin "$BARE_REMOTE"
  git -C "$seed" push -q origin master staging
  rm -rf "$seed"
}

# Run a command, collect stdout+stderr into OUTPUT and the exit status into STATUS.
run_cmd() {
  if OUTPUT="$("$@" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi
  return 0
}

# Like run_cmd but runs in the <dir> directory.
run_in() {
  local dir="$1"
  shift
  # String for the child shell or a fixture, keep the $ characters as they are.
  # shellcheck disable=SC2016
  run_cmd bash -c 'cd "$1" && shift && exec "$@"' _ "$dir" "$@"
}

# Run this repo's install.sh.
run_installer() {
  run_cmd "$KIT_REPO_ROOT/install.sh" "$@"
}

# Install a new Docker root into $SANDBOX/<name> using the package checkout as the source.
kit_new() {
  local name="${1:-root}"
  shift || true
  run_installer new "$SANDBOX/$name" --source "$KIT_REPO_ROOT" "$@"
}

# Fingerprint of a directory tree: path, executable bit and content sha256.
tree_digest() {
  local dir="$1" rel
  (
    cd "$dir" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r rel; do
      if [[ -x "$rel" ]]; then printf 'x '; else printf -- '- '; fi
      printf '%s  %s\n' "$(sha256sum "$rel" | cut -d' ' -f1)" "$rel"
    done
  )
}

# Run every defined test_* function, in alphabetical order.
run_tests() {
  local fn
  while IFS= read -r fn; do
    "$fn"
  done < <(declare -F | awk '{print $3}' | grep '^test_' || true)
}
