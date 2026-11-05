#!/usr/bin/env bash
# S1 tests for bin/agent install (core): AGENTS.md carries the right profile values and is
# about 30 lines long, AGENTS.project.md is appended at the end and warns when it is over
# 20 lines, CLAUDE.md points at @AGENTS.md, project skills are installed the same way as
# package skills, a role with a colliding name stops before anything is written, an existing
# or Git-tracked file is left untouched, and a worktree after `bin/wt prepare` has the agent
# kit.
#
# Usage:  bash tests/test-agent.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

set_profile() {
  sed -i "s|^$1=.*|$1=$2|" "$ROOT/project/profile.env"
}

# Docker root `shop` with a profile that has the Git keys. No src/ unless test_worktree builds one.
new_root() {
  sandbox_new
  kit_new shop --domain shop.test > /dev/null
  ROOT="$SANDBOX/shop"
  set_profile KIT_GIT_REMOTE origin
  set_profile KIT_GIT_BASE_BRANCH master
  set_profile KIT_GIT_TARGET_BRANCH staging
}

agent() {
  run_in "$ROOT" bin/agent "$@"
}

test_agents_md_has_profile_values() {
  new_root
  agent install
  assert_status 0 'install exits 0'
  assert_file "$ROOT/AGENTS.md" 'AGENTS.md generated'
  assert_file_matches "$ROOT/AGENTS.md" 'shop\.test' 'AGENTS.md has KIT_DOMAIN'
  # String for a subshell or fixture, keep the $ characters as they are.
  # shellcheck disable=SC2016
  assert_file_matches "$ROOT/AGENTS.md" '`master` and `staging` are read-only: no push' 'AGENTS.md forbids pushing to the base and target branches'
  assert_file_matches "$ROOT/AGENTS.md" 'origin/master' 'AGENTS.md has the remote and base branch'
  assert_file_matches "$ROOT/AGENTS.md" "cd $ROOT && bin/cli" 'AGENTS.md shows how to run commands through the Docker root'
  assert_file_matches "$ROOT/AGENTS.md" 'bin/wt create' 'AGENTS.md has the worktree rules'
  assert_file_matches "$ROOT/AGENTS.md" 'project/agent/references/' 'AGENTS.md points at the project references'
  assert_file_does_not_match "$ROOT/AGENTS.md" '\{\{' 'AGENTS.md has no placeholder left'
  local lines
  lines="$(wc -l < "$ROOT/AGENTS.md")"
  assert_equals 1 "$([[ "$lines" -ge 25 && "$lines" -le 40 ]] && echo 1 || echo 0)" "AGENTS.md is about 30 lines (got $lines)"
}

test_claude_md_imports_agents() {
  new_root
  agent install
  assert_file_line "$ROOT/CLAUDE.md" '@AGENTS.md' 'CLAUDE.md has the @AGENTS.md line'
  assert_file_matches "$ROOT/CLAUDE.md" 'Claude Code' 'CLAUDE.md has the Claude Code section'
}

test_install_is_idempotent() {
  new_root
  agent install
  local before
  before="$(tree_digest "$ROOT")"
  agent install
  assert_status 0 'the second run exits 0'
  assert_not_contains 'Wrote ' 'the second run does not write files again'
  assert_equals "$before" "$(tree_digest "$ROOT")" 'the second run changes no file'
}

test_missing_git_keys_stops() {
  new_root
  set_profile KIT_GIT_TARGET_BRANCH ''
  agent install
  assert_status_nonzero 'missing Git keys exit non-zero'
  assert_contains 'KIT_GIT_TARGET_BRANCH' 'names the key that must be filled in'
  assert_absent "$ROOT/AGENTS.md" 'AGENTS.md is not written'
}

test_project_md_appended_and_capped() {
  new_root
  mkdir -p "$ROOT/project/agent"
  printf '## Format conventions\n- Use the module map\n' > "$ROOT/project/agent/AGENTS.project.md"
  agent install
  assert_status 0 'install with AGENTS.project.md exits 0'
  assert_file_line "$ROOT/AGENTS.md" '## Format conventions' 'AGENTS.project.md is appended'
  assert_equals '- Use the module map' "$(tail -n 1 "$ROOT/AGENTS.md")" 'the project part is at the end of AGENTS.md'
  assert_not_contains 'over the limit' 'below 20 lines there is no warning'

  local i
  for i in $(seq 1 25); do printf -- '- line %d\n' "$i"; done > "$ROOT/project/agent/AGENTS.project.md"
  agent install
  assert_status 0 'over 20 lines still installs'
  assert_contains 'over the limit of 20' 'over 20 lines warns'
}

test_project_skill_installed() {
  new_root
  mkdir -p "$ROOT/project/agent/skills/format-deploy" "$ROOT/agent/skills/magento-workflow"
  printf -- '---\nname: format-deploy\n---\n' > "$ROOT/project/agent/skills/format-deploy/SKILL.md"
  printf -- '---\nname: magento-workflow\n---\n' > "$ROOT/agent/skills/magento-workflow/SKILL.md"
  agent install
  assert_status 0 'install with skills exits 0'
  assert_file "$ROOT/.claude/skills/format-deploy/SKILL.md" 'project skill goes into .claude/skills'
  assert_file "$ROOT/.agents/skills/format-deploy/SKILL.md" 'project skill goes into .agents/skills'
  assert_file "$ROOT/.claude/skills/magento-workflow/SKILL.md" 'package skill is installed by the same mechanism'

  rm -rf "$ROOT/project/agent/skills/format-deploy"
  agent install
  assert_absent "$ROOT/.claude/skills/format-deploy" 'a removed project skill is cleaned up'
  assert_file "$ROOT/.claude/skills/magento-workflow/SKILL.md" 'package skill stays'
}

test_role_collision_stops() {
  new_root
  mkdir -p "$ROOT/agent/roles" "$ROOT/project/agent/roles"
  printf -- '---\nname: magento-developer\n---\n' > "$ROOT/agent/roles/magento-developer.md"
  printf -- '---\nname: magento-developer\n---\n' > "$ROOT/project/agent/roles/magento-developer.md"
  agent install
  assert_status_nonzero 'a role whose name collides with a package role stops'
  assert_contains 'magento-developer' 'names the colliding role'
  assert_absent "$ROOT/AGENTS.md" 'stops before writing AGENTS.md'
  assert_absent "$ROOT/CLAUDE.md" 'stops before writing CLAUDE.md'

  rm "$ROOT/project/agent/roles/magento-developer.md"
  printf -- '---\nname: format-qa\n---\n' > "$ROOT/project/agent/roles/format-qa.md"
  agent install
  assert_status 0 'a project role without a name collision installs'
}

test_existing_files_preserved() {
  new_root
  printf 'handwritten\n' > "$ROOT/AGENTS.md"
  agent install
  assert_status 0 'a handwritten AGENTS.md does not make install fail'
  assert_contains 'not generated by bin/agent' 'warns that the handwritten AGENTS.md is kept'
  assert_equals 'handwritten' "$(cat "$ROOT/AGENTS.md")" 'the handwritten AGENTS.md is left untouched'
  assert_file_line "$ROOT/CLAUDE.md" '@AGENTS.md' 'CLAUDE.md is still generated'
  agent install --force
  assert_file_matches "$ROOT/AGENTS.md" 'shop\.test' '--force overwrites the handwritten file'
}

test_tracked_files_preserved() {
  new_root
  local d="$SANDBOX/repo"
  git -c init.defaultBranch=master init -q "$d"
  git -C "$d" config user.name t
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config commit.gpgsign false
  printf 'from the repo\n' > "$d/AGENTS.md"
  git -C "$d" add AGENTS.md
  git -C "$d" commit -q -m 'agents'
  agent install --target "$d" --force
  assert_status 0 'install into a repo with a tracked AGENTS.md exits 0'
  assert_contains 'already tracked by Git' 'warns that the file is tracked'
  assert_equals 'from the repo' "$(cat "$d/AGENTS.md")" 'a tracked AGENTS.md is not overwritten even with --force'
  assert_file "$d/CLAUDE.md" 'CLAUDE.md that is not tracked is still generated'
}

# A worktree after bin/wt prepare has the agent kit (src/ is a clone of a bare remote with master).
test_worktree_prepare_installs_agent() {
  new_root
  git_remote_new
  git clone -q "$BARE_REMOTE" "$ROOT/src"
  git -C "$ROOT/src" config user.name t
  git -C "$ROOT/src" config user.email t@example.invalid
  git -C "$ROOT/src" config commit.gpgsign false
  printf '*\n!.gitignore\n!composer.json\n' > "$ROOT/src/.gitignore"
  printf '{"name": "kit/test"}\n' > "$ROOT/src/composer.json"
  git -C "$ROOT/src" add .gitignore composer.json
  git -C "$ROOT/src" commit -q -m 'magento'
  git -C "$ROOT/src" push -q origin master
  mkdir -p "$ROOT/project/agent/skills/format-deploy"
  printf -- '---\nname: format-deploy\n---\n' > "$ROOT/project/agent/skills/format-deploy/SKILL.md"
  printf '## Project specific\n' > "$ROOT/project/agent/AGENTS.project.md"

  run_in "$ROOT" bin/wt create feature/kit-agent
  assert_status 0 'create exits 0'
  local d="$ROOT/.worktrees/feature-kit-agent"
  assert_file "$d/AGENTS.md" 'the new worktree has AGENTS.md'
  assert_file_matches "$d/AGENTS.md" 'origin/master' 'AGENTS.md in the worktree has the profile values'
  assert_file_line "$d/AGENTS.md" '## Project specific' 'AGENTS.md in the worktree has the project part'
  assert_file_line "$d/CLAUDE.md" '@AGENTS.md' 'the worktree has CLAUDE.md'
  assert_file "$d/.claude/skills/format-deploy/SKILL.md" 'the worktree has the project skill'

  rm -f "$d/AGENTS.md" "$d/CLAUDE.md"
  rm -rf "$d/.claude" "$d/.agents"
  run_in "$ROOT" bin/wt prepare feature-kit-agent
  assert_status 0 'prepare exits 0'
  assert_file "$d/AGENTS.md" 'prepare installs the agent kit into the worktree again'
  assert_file "$d/.agents/skills/format-deploy/SKILL.md" 'prepare installs the skill into .agents/skills again'
}

run_tests
finish
