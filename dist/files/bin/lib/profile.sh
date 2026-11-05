#!/usr/bin/env bash
# bin/lib/profile.sh - thư viện đọc file profile (project/profile.env) và
# trạng thái runtime (.kit/runtime.env). Chỉ để `source`, không chạy trực tiếp.
#
# Định dạng: KEY=value, mỗi dòng một khóa.
#   - Dòng trống và dòng bắt đầu bằng # là comment. Phần ` # ...` ở cuối dòng
#     (có khoảng trắng đứng trước dấu #) cũng là comment.
#   - Không nháy, không $ hay `, không khoảng trắng quanh dấu =.
#   - Mọi khóa có tiền tố KIT_. Giá trị được có khoảng trắng ở giữa.
#   - Giá trị rỗng coi như thiếu khóa và dùng mặc định của gói.
# File được parse từng dòng, không bao giờ `source`. Biến KIT_* có sẵn trong
# shell bị bỏ qua, giá trị chỉ lấy từ file hoặc từ mặc định của gói.

# Các khóa mà gói đọc (không tính KIT_MODEL_<HARNESS>_<HẠNG>).
KIT_PROFILE_KEYS='KIT_PROJECT_NAME KIT_DOMAIN KIT_GIT_REMOTE KIT_GIT_BASE_BRANCH KIT_GIT_TARGET_BRANCH
KIT_PHP_VERSION KIT_DB_ENGINE KIT_DB_VERSION KIT_REDIS_IMAGE
KIT_HTTP_PORT KIT_HTTPS_PORT KIT_DB_PORT KIT_REDIS_PORT KIT_OPENSEARCH_PORT KIT_OPENSEARCH_HEAP
KIT_RABBITMQ_PORT KIT_RABBITMQ_MANAGEMENT_PORT KIT_STATIC_LOCALES KIT_COMPOSE_PROFILES KIT_PHP_VARIANT'

# Khóa không có mặc định, dự án phải tự điền (trừ KIT_PROJECT_NAME lấy theo tên thư mục).
KIT_REQUIRED_KEYS='KIT_PROJECT_NAME KIT_DOMAIN KIT_GIT_REMOTE KIT_GIT_BASE_BRANCH KIT_GIT_TARGET_BRANCH'

# kit_profile_default <KEY> [<root>]: in mặc định của khóa, rỗng nếu không có.
# KIT_DB_VERSION phụ thuộc engine nên đọc KIT_DB_ENGINE đã nạp.
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

# kit_profile_parse <file>: in `KEY=value` đã kiểm tra, mỗi khóa một dòng.
# Trả 1 và báo `<file>:<dòng>: <lý do>` ra stderr khi có dòng sai. File không
# tồn tại thì không in gì và trả 0.
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
      printf '%s:%d: dòng không có dạng KEY=value: %s\n' "$file" "$lineno" "$line" >&2
      bad=1
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    if [[ ! "$key" =~ ^KIT_[A-Z0-9_]+$ ]]; then
      printf '%s:%d: khóa phải có dạng KIT_XXX, không có khoảng trắng quanh dấu =: [%s]\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    # Bỏ comment cuối dòng (khoảng trắng rồi #) và khoảng trắng thừa ở cuối.
    value="$(printf '%s' "$value" | sed -e 's/[[:space:]][[:space:]]*#.*$//' -e 's/[[:space:]]*$//')"
    if [[ "$value" == [[:space:]]* ]]; then
      printf '%s:%d: không được có khoảng trắng sau dấu = (%s)\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    if [[ "$value" == *'"'* || "$value" == *"'"* ]]; then
      printf '%s:%d: không dùng nháy trong giá trị (%s)\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    if [[ "$value" == *'$'* || "$value" == *'`'* ]]; then
      printf '%s:%d: không dùng ${...} hay $(...) trong giá trị (%s)\n' "$file" "$lineno" "$key" >&2
      bad=1
      continue
    fi
    printf '%s=%s\n' "$key" "$value"
  done < "$file"
  [[ "$bad" -eq 0 ]]
}

# _kit_profile_apply <file>: gán các khóa của file vào biến shell, khóa sau
# thắng khóa trước. Giá trị rỗng bị bỏ qua để rơi về mặc định.
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

# kit_profile_load [<root>]: nạp project/profile.env rồi .kit/runtime.env vào
# các biến KIT_*, điền mặc định cho khóa còn thiếu. Đặt KIT_PROFILE_FILE và
# KIT_PROFILE_UNKNOWN (khóa KIT_* không có trong bảng). Trả 1 nếu file sai cú pháp.
kit_profile_load() {
  local root="${1:-$PWD}" key known
  KIT_PROFILE_FILE="$root/project/profile.env"
  _KIT_SEEN_KEYS=''
  for key in $KIT_PROFILE_KEYS; do
    unset "$key"
  done
  _kit_profile_apply "$KIT_PROFILE_FILE" || return 1
  _kit_profile_apply "$root/.kit/runtime.env" || return 1
  # KIT_DB_ENGINE phải có trước để KIT_DB_VERSION chọn đúng mặc định.
  for key in KIT_DB_ENGINE $KIT_PROFILE_KEYS; do
    if [[ -z "${!key:-}" ]]; then
      printf -v "$key" '%s' "$(kit_profile_default "$key" "$root")"
    fi
  done
  KIT_PROFILE_UNKNOWN=''
  # KIT_PROFILE_KEYS xuống dòng cho dễ đọc, đổi về một dòng để so theo từng khóa.
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

# kit_profile_require <KEY>...: trả 1 và báo rõ từng khóa bắt buộc còn trống.
# Phải gọi sau kit_profile_load.
kit_profile_require() {
  local key bad=0
  for key in "$@"; do
    if [[ -z "${!key:-}" ]]; then
      printf 'thiếu khóa bắt buộc %s, hãy điền vào %s\n' "$key" "${KIT_PROFILE_FILE:-project/profile.env}" >&2
      bad=1
    fi
  done
  [[ "$bad" -eq 0 ]]
}

# kit_profile_missing_required: in các khóa bắt buộc còn trống, mỗi khóa một dòng.
kit_profile_missing_required() {
  local key
  for key in $KIT_REQUIRED_KEYS; do
    if [[ -z "${!key:-}" ]]; then printf '%s\n' "$key"; fi
  done
}

# kit_profile_export: export mọi khóa đã nạp để Compose nội suy ${KIT_*}.
kit_profile_export() {
  local key
  for key in $KIT_PROFILE_KEYS; do
    export "${key?}"
  done
}
