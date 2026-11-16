#!/usr/bin/env bash
# PreToolUse hook (Claude Edit|Write|MultiEdit, Codex apply_patch): refuse a write into
# build output, and warn when a write lands in the main checkout while it sits on a
# protected branch.
#
#   guard-paths.sh
#
# vendor/, generated/ and pub/static/ are build output: the write is denied with a
# reason, because no edit there is ever the right fix. A write to a file in the main
# checkout (src/) that Git does not ignore, while it is on master or staging, is allowed
# but carries a reminder: the rule is in AGENTS.md, and a hook cannot tell an intentional
# exception from a mistake.
#
# The main checkout is found from this script, <main checkout>/.agents/hooks/, so the
# answer is the same when the harness is opened in a worktree that links .agents.
set -Eeuo pipefail

input=$(cat)
# A payload the hook cannot parse is not a reason to block the edit: fail open.
jq -e . >/dev/null 2>&1 <<<"$input" || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
project="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"

# Claude: tool_input.file_path. Codex apply_patch: patch text in tool_input.command.
files=$(jq -r '.tool_input.file_path // empty' <<<"$input")
if [ -z "$files" ]; then
  files=$(jq -r '.tool_input.command // empty | if type=="string" then . else "" end' <<<"$input" \
    | sed -nE 's/^\*\*\* (Add|Update) File: (.+)$/\2/p')
fi
[ -z "$files" ] && exit 0

denied=''
warned=''
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    /*) path="$file" ;;
    *) path="${cwd:-$PWD}/$file" ;;
  esac
  path="$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")"
  case "$path" in
    */vendor/* | */generated/* | */pub/static/*)
      denied="$path"
      break
      ;;
  esac
  case "$path" in
    "$project"/*) warned="$path" ;;
  esac
done <<<"$files"

if [ -n "$denied" ]; then
  jq -n --arg r "Blocked: $denied is inside build output (vendor/, generated/ or pub/static/). Those directories are generated, never edited by hand. Edit the source and let the project regenerate them." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

if [ -n "$warned" ] && ! git -C "$project" check-ignore -q "$warned" 2>/dev/null; then
  branch="$(git -C "$project" symbolic-ref --short HEAD 2>/dev/null || true)"
  case "$branch" in
    master | staging)
      jq -n --arg m "Reminder: $warned is in the main checkout and it is on $branch. AGENTS.md keeps the main checkout clean on $branch: create a worktree with the project's checkout command and make the change there. The write was allowed." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
      exit 0
      ;;
  esac
fi

exit 0
