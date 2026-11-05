#!/usr/bin/env bash
# bin/lib/profile.sh - library that reads the profile file (project/profile.env)
# and the runtime state (.kit/runtime.env). Source-only, never run directly.
#
# Format: KEY=value, one key per line.
#   - Blank lines and lines starting with # are comments. A trailing ` # ...`
#     (whitespace before the #) is also a comment.
#   - No quotes, no $ or backticks, no whitespace around the =.
#   - Every key is prefixed KIT_. A value may contain spaces.
#   - An empty value counts as a missing key and falls back to the package default.
# The file is parsed line by line and never `source`d. KIT_* variables already set
# in the shell are ignored, values come only from the file or from the package default.

# Keys the package reads (not counting KIT_MODEL_<HARNESS>_<TIER>).
KIT_PROFILE_KEYS='KIT_PROJECT_NAME KIT_DOMAIN KIT_GIT_REMOTE KIT_GIT_BASE_BRANCH KIT_GIT_TARGET_BRANCH
KIT_PHP_VERSION KIT_DB_ENGINE KIT_DB_VERSION KIT_REDIS_IMAGE
KIT_HTTP_PORT KIT_HTTPS_PORT KIT_DB_PORT KIT_REDIS_PORT KIT_OPENSEARCH_PORT KIT_OPENSEARCH_HEAP
KIT_RABBITMQ_PORT KIT_RABBITMQ_MANAGEMENT_PORT KIT_STATIC_LOCALES KIT_COMPOSE_PROFILES KIT_PHP_VARIANT'

# Keys without a default, the project has to fill them in (except KIT_PROJECT_NAME, which follows the directory name).
KIT_REQUIRED_KEYS='KIT_PROJECT_NAME KIT_DOMAIN KIT_GIT_REMOTE KIT_GIT_BASE_BRANCH KIT_GIT_TARGET_BRANCH'

# kit_profile_default <KEY> [<root>]: print the key default, empty when there is none.
# KIT_DB_VERSION depends on the engine, so it reads the already loaded KIT_DB_ENGINE.
kit_profile_default() {
  case "$1" in
    KIT_PROJECT_NAME)
      printf '%s' "$(basename "${2:-$PWD}" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_-]//g' -e 's/^[_-]*//')"
      ;;
    KIT_PHP_VERSION) printf '8.3' ;;
    KIT_DB_ENGINE) printf 'mariadb' ;;
    KIT_DB_VERSION)
      if [[ "${KIT_DB_ENGINE:-mariadb}" == 'mysql' ]]; then printf '8.4'; else printf '11.4'; fi
      ;;
    KIT_REDIS_IMAGE) printf 'valkey/valkey:8.1-alpine' ;;
    KIT_HTTP_PORT) printf '80' ;;
    KIT_HTTPS_PORT) printf '443' ;;
    KIT_DB_PORT) printf '3306' ;;
    KIT_REDIS_PORT) printf '6379' ;;
    KIT_OPENSEARCH_PORT) printf '9200' ;;
    KIT_OPENSEARCH_HEAP) printf '1g' ;;
    KIT_RABBITMQ_PORT) printf '5672' ;;
    KIT_RABBITMQ_MANAGEMENT_PORT) printf '15672' ;;
    KIT_STATIC_LOCALES) printf 'en_US' ;;
    *) printf '' ;;
  esac
}

# kit_profile_parse <file>: print validated `KEY=value`, one key per line.
# Returns 1 and reports `<file>:<line>: <reason>` on stderr for a bad line. A file
# that does not exist prints nothing and returns 0.
kit_profile_parse() {
  local file="$1" line key value lineno=0 bad=0
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    case "$line" in
      '' | '#'*) continue ;;
    esac
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
      continue
    fi
    if [[ "$line" != *=* ]]; then
      printf '%s:%d: line is not of the form KEY=value: %s\n' "$file" "$lineno" "$line" >&2
      bad=1
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    if [[ ! "$key" =~ ^KIT_[A-Z0-9_]+$ ]]; then
      printf '%s:%d: key must be of the form KIT_XXX, with no spaces around the =: [%s]\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    # Drop the trailing comment (whitespace then #) and trailing whitespace.
    value="$(printf '%s' "$value" | sed -e 's/[[:space:]][[:space:]]*#.*$//' -e 's/[[:space:]]*$//')"
    if [[ "$value" == [[:space:]]* ]]; then
      printf '%s:%d: no whitespace allowed after the = (%s)\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    if [[ "$value" == *'"'* || "$value" == *"'"* ]]; then
      printf '%s:%d: no quotes allowed in the value (%s)\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    if [[ "$value" == *'$'* || "$value" == *'`'* ]]; then
      printf '%s:%d: no ${...} or $(...) allowed in the value (%s)\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    printf '%s=%s\n' "$key" "$value"
  done < "$file"
  [[ "$bad" -eq 0 ]]
}

# _kit_profile_apply <file>: assign the file keys to shell variables, the last
# key wins. Empty values are skipped so they fall back to the default.
_kit_profile_apply() {
  local out entry key value
  out="$(kit_profile_parse "$1")" || return 1
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    key="${entry%%=*}"
    value="${entry#*=}"
    if [[ -n "$value" ]]; then
      printf -v "$key" '%s' "$value"
    else
      unset "$key"
    fi
    _KIT_SEEN_KEYS="${_KIT_SEEN_KEYS:-} $key"
  done <<< "$out"
}

# kit_profile_load [<root>]: load project/profile.env then .kit/runtime.env into
# the KIT_* variables, filling defaults for missing keys. Sets KIT_PROFILE_FILE and
# KIT_PROFILE_UNKNOWN (KIT_* keys that are not in the table). Returns 1 if the file has bad syntax.
kit_profile_load() {
  local root="${1:-$PWD}" key known
  KIT_PROFILE_FILE="$root/project/profile.env"
  _KIT_SEEN_KEYS=''
  for key in $KIT_PROFILE_KEYS; do
    unset "$key"
  done
  _kit_profile_apply "$KIT_PROFILE_FILE" || return 1
  _kit_profile_apply "$root/.kit/runtime.env" || return 1
  # KIT_DB_ENGINE must be loaded first so KIT_DB_VERSION picks the right default.
  for key in KIT_DB_ENGINE $KIT_PROFILE_KEYS; do
    if [[ -z "${!key:-}" ]]; then
      printf -v "$key" '%s' "$(kit_profile_default "$key" "$root")"
    fi
  done
  KIT_PROFILE_UNKNOWN=''
  # KIT_PROFILE_KEYS is wrapped for readability, fold it back to one line to compare key by key.
  known=" $(printf '%s' "$KIT_PROFILE_KEYS" | tr '\n' ' ') "
  for key in $_KIT_SEEN_KEYS; do
    case "$key" in
      KIT_MODEL_*) continue ;;
    esac
    case "$known $KIT_PROFILE_UNKNOWN " in
      *" $key "*) ;;
      *) KIT_PROFILE_UNKNOWN="$KIT_PROFILE_UNKNOWN $key" ;;
    esac
  done
  KIT_PROFILE_UNKNOWN="${KIT_PROFILE_UNKNOWN# }"
  return 0
}

# kit_profile_require <KEY>...: return 1 and clearly report each required key still empty.
# Must be called after kit_profile_load.
kit_profile_require() {
  local key bad=0
  for key in "$@"; do
    if [[ -z "${!key:-}" ]]; then
      printf 'missing required key %s, fill it in %s\n' "$key" "${KIT_PROFILE_FILE:-project/profile.env}" >&2
      bad=1
    fi
  done
  [[ "$bad" -eq 0 ]]
}

# kit_profile_missing_required: print the required keys that are still empty, one key per line.
kit_profile_missing_required() {
  local key
  for key in $KIT_REQUIRED_KEYS; do
    if [[ -z "${!key:-}" ]]; then printf '%s\n' "$key"; fi
  done
}

# kit_profile_export: export every loaded key so Compose can interpolate ${KIT_*}.
kit_profile_export() {
  local key
  for key in $KIT_PROFILE_KEYS; do
    export "${key?}"
  done
}
