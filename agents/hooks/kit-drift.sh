#!/usr/bin/env bash
# SessionStart hook: warn when the project is behind the kit.
#
#   kit-drift.sh <kit path> [skip path...]
#   e.g. "$CLAUDE_PROJECT_DIR"/.agents/hooks/kit-drift.sh /path/to/kit compose.worktree.yaml
#
# Runs the kit's `sync --quiet` in report mode and adds one line of context when the
# project is behind. Silent when the project is in sync, when the kit path is not a
# kit, and when sync reports a usage error: a broken path must never block a session.
set -Eeuo pipefail

kit="${1:-}"
[ -n "$kit" ] || exit 0
shift || true
[ -d "$kit" ] && [ -x "$kit/sync" ] || exit 0

input=$(cat || true)
project="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$project" ] && [ -n "$input" ]; then
  project="$(jq -r '.cwd // empty' 2>/dev/null <<<"$input" || true)"
fi
project="${project:-$PWD}"

args=(--quiet --target "$project")
for skip in "$@"; do
  args+=(--skip "$skip")
done

status=0
summary="$("$kit/sync" "${args[@]}" 2>/dev/null)" || status=$?
[[ "$status" -eq 1 ]] || exit 0
summary="$(printf '%s\n' "$summary" | grep -m1 -E '^[0-9]+ added,' || true)"
[ -n "$summary" ] || exit 0

jq -n --arg m "The kit at $kit is ahead of this project: $summary. Run the project-update skill to review the diff and copy it with --apply." \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
