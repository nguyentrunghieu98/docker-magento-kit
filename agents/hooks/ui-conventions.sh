#!/usr/bin/env bash
# PreToolUse hook (Claude Edit|Write|MultiEdit, Codex apply_patch): when an edit targets a
# UI file under app/code or app/design, inject the project's UI rules into the agent
# context. Full text once per session, a one-line reminder afterwards. Silent otherwise.
#
#   ui-conventions.sh <rules path relative to the Magento root>
#   e.g. "$CLAUDE_PROJECT_DIR"/.agents/hooks/ui-conventions.sh docs/agents/ui-conventions.md
#
# The rules come from the checkout being edited, else from <project>/src. Missing rules
# print a warning on stderr and never block the edit.
rules="${1:-}"
if [ -z "$rules" ]; then
  echo "Usage: ui-conventions.sh <rules path relative to the Magento root>" >&2
  exit 1
fi

input=$(cat)
sid=$(jq -r '.session_id // "nosession"' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
project="${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}"

# Claude: tool_input.file_path. Codex apply_patch: patch text in tool_input.command.
files=$(jq -r '.tool_input.file_path // empty' <<<"$input")
if [ -z "$files" ]; then
  files=$(jq -r '.tool_input.command // empty | if type=="string" then . else "" end' <<<"$input" \
    | sed -nE 's/^\*\*\* (Add|Update) File: (.+)$/\2/p')
fi
[ -z "$files" ] && exit 0

is_ui() {
  case "$1" in
    */app/code/*|*/app/design/*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    */Test/*|*/Setup/*) return 1 ;;
  esac
  case "$1" in
    *.phtml|*.less|*.css|*/requirejs-config.js) return 0 ;;
    */view/*/ui_component/*.xml|*/view/*/layout/*.xml) return 0 ;;
    */view/*/web/js/*|*/view/*/web/template/*.html) return 0 ;;
    */app/design/*/web/*|*/app/design/*/templates/*|*/app/design/*/layout/*.xml) return 0 ;;
  esac
  return 1
}

file=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in /*) ;; *) f="${cwd:-$PWD}/$f" ;; esac
  if is_ui "$f"; then file="$f"; break; fi
done <<<"$files"
[ -z "$file" ] && exit 0

doc="${file%%/app/*}/$rules"
[ -f "$doc" ] || doc="$project/src/$rules"
if [ ! -f "$doc" ]; then
  echo "ui-conventions hook: $rules not found in the edited checkout or in $project/src, no UI rules injected" >&2
  exit 0
fi

marker="${TMPDIR:-/tmp}/ui-conventions-$sid"
if [ -f "$marker" ]; then
  msg="Reminder: this is a UI file. Follow $rules."
else
  : >"$marker"
  msg="You are editing a UI file. Follow these rules, even when the request does not mention the UI:

$(cat "$doc")"
fi

jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
