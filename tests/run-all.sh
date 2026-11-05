#!/usr/bin/env bash
# Chạy mọi tests/test-*.sh, không cần mạng. Thoát 1 nếu có file nào lỗi.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2

failed=()
for t in test-*.sh; do
  printf '=== %s\n' "$t"
  if ! bash "$t"; then
    failed+=("$t")
  fi
done

if [[ "${#failed[@]}" -gt 0 ]]; then
  printf 'LỖI: %s\n' "${failed[*]}" >&2
  exit 1
fi
printf 'Tất cả test đạt\n'
