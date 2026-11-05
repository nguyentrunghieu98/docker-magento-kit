#!/usr/bin/env bash
# Run every tests/test-*.sh, no network needed. Exit 1 if any file fails.
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
  printf 'FAILED: %s\n' "${failed[*]}" >&2
  exit 1
fi
printf 'All tests passed\n'
