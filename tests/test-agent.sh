#!/usr/bin/env bash
# Test S1 cho bin/agent install (lõi): AGENTS.md mang đúng giá trị profile và dài khoảng
# 30 dòng, AGENTS.project.md được chèn cuối và bị cảnh báo khi quá 20 dòng, CLAUDE.md
# trỏ tới @AGENTS.md, skill của dự án được cài như của gói, role trùng tên thì dừng
# trước khi ghi gì, file đã có hoặc đã theo dõi trong Git được giữ nguyên, và worktree
# sau `bin/wt prepare` có kit agent.
#
# Usage:  bash tests/test-agent.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

set_profile() {
  sed -i "s|^$1=.*|$1=$2|" "$ROOT/project/profile.env"
}

# Docker root `shop` với profile đủ khóa Git. Không có src/ trừ khi test_worktree dựng.
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
  assert_status 0 'install thoát 0'
  assert_file "$ROOT/AGENTS.md" 'sinh AGENTS.md'
  assert_file_matches "$ROOT/AGENTS.md" 'shop\.test' 'AGENTS.md có KIT_DOMAIN'
  # Chuỗi cho shell con hoặc fixture, giữ nguyên ký tự $.
  # shellcheck disable=SC2016
  assert_file_matches "$ROOT/AGENTS.md" '`master` và `staging` chỉ đọc: không push' 'AGENTS.md cấm push nhánh gốc và nhánh đích'
  assert_file_matches "$ROOT/AGENTS.md" 'origin/master' 'AGENTS.md có remote và nhánh gốc'
  assert_file_matches "$ROOT/AGENTS.md" "cd $ROOT && bin/cli" 'AGENTS.md chỉ cách chạy lệnh qua Docker root'
  assert_file_matches "$ROOT/AGENTS.md" 'bin/wt create' 'AGENTS.md có quy tắc worktree'
  assert_file_matches "$ROOT/AGENTS.md" 'project/agent/references/' 'AGENTS.md trỏ tới references của dự án'
  assert_file_does_not_match "$ROOT/AGENTS.md" '\{\{' 'AGENTS.md không còn placeholder'
  local lines
  lines="$(wc -l < "$ROOT/AGENTS.md")"
  assert_equals 1 "$([[ "$lines" -ge 25 && "$lines" -le 40 ]] && echo 1 || echo 0)" "AGENTS.md khoảng 30 dòng (có $lines)"
}

test_claude_md_imports_agents() {
  new_root
  agent install
  assert_file_line "$ROOT/CLAUDE.md" '@AGENTS.md' 'CLAUDE.md có dòng @AGENTS.md'
  assert_file_matches "$ROOT/CLAUDE.md" 'Claude Code' 'CLAUDE.md có phần riêng cho Claude'
}

test_install_is_idempotent() {
  new_root
  agent install
  local before
  before="$(tree_digest "$ROOT")"
  agent install
  assert_status 0 'chạy lần hai thoát 0'
  assert_not_contains 'Đã ghi' 'lần hai không ghi lại file'
  assert_equals "$before" "$(tree_digest "$ROOT")" 'lần hai không đổi file nào'
}

test_missing_git_keys_stops() {
  new_root
  set_profile KIT_GIT_TARGET_BRANCH ''
  agent install
  assert_status_nonzero 'thiếu khóa Git thì thoát khác 0'
  assert_contains 'KIT_GIT_TARGET_BRANCH' 'gọi tên khóa cần điền'
  assert_absent "$ROOT/AGENTS.md" 'không ghi AGENTS.md'
}

test_project_md_appended_and_capped() {
  new_root
  mkdir -p "$ROOT/project/agent"
  printf '## Quy ước Format\n- Dùng module map\n' > "$ROOT/project/agent/AGENTS.project.md"
  agent install
  assert_status 0 'install với AGENTS.project.md thoát 0'
  assert_file_line "$ROOT/AGENTS.md" '## Quy ước Format' 'AGENTS.project.md được chèn'
  assert_equals '- Dùng module map' "$(tail -n 1 "$ROOT/AGENTS.md")" 'phần của dự án nằm cuối AGENTS.md'
  assert_not_contains 'vượt giới hạn' 'dưới 20 dòng thì không cảnh báo'

  local i
  for i in $(seq 1 25); do printf -- '- dòng %d\n' "$i"; done > "$ROOT/project/agent/AGENTS.project.md"
  agent install
  assert_status 0 'quá 20 dòng vẫn cài'
  assert_contains 'vượt giới hạn 20' 'quá 20 dòng thì cảnh báo'
}

test_project_skill_installed() {
  new_root
  mkdir -p "$ROOT/project/agent/skills/format-deploy" "$ROOT/agent/skills/magento-workflow"
  printf -- '---\nname: format-deploy\n---\n' > "$ROOT/project/agent/skills/format-deploy/SKILL.md"
  printf -- '---\nname: magento-workflow\n---\n' > "$ROOT/agent/skills/magento-workflow/SKILL.md"
  agent install
  assert_status 0 'install với skill thoát 0'
  assert_file "$ROOT/.claude/skills/format-deploy/SKILL.md" 'skill dự án vào .claude/skills'
  assert_file "$ROOT/.agents/skills/format-deploy/SKILL.md" 'skill dự án vào .agents/skills'
  assert_file "$ROOT/.claude/skills/magento-workflow/SKILL.md" 'skill của gói cài cùng cơ chế'

  rm -rf "$ROOT/project/agent/skills/format-deploy"
  agent install
  assert_absent "$ROOT/.claude/skills/format-deploy" 'skill dự án đã bỏ thì bị dọn'
  assert_file "$ROOT/.claude/skills/magento-workflow/SKILL.md" 'skill của gói còn nguyên'
}

test_role_collision_stops() {
  new_root
  mkdir -p "$ROOT/agent/roles" "$ROOT/project/agent/roles"
  printf -- '---\nname: magento-developer\n---\n' > "$ROOT/agent/roles/magento-developer.md"
  printf -- '---\nname: magento-developer\n---\n' > "$ROOT/project/agent/roles/magento-developer.md"
  agent install
  assert_status_nonzero 'role trùng tên role của gói thì dừng'
  assert_contains 'magento-developer' 'gọi tên role trùng'
  assert_absent "$ROOT/AGENTS.md" 'dừng trước khi ghi AGENTS.md'
  assert_absent "$ROOT/CLAUDE.md" 'dừng trước khi ghi CLAUDE.md'

  rm "$ROOT/project/agent/roles/magento-developer.md"
  printf -- '---\nname: format-qa\n---\n' > "$ROOT/project/agent/roles/format-qa.md"
  agent install
  assert_status 0 'role dự án không trùng tên thì cài được'
}

test_existing_files_preserved() {
  new_root
  printf 'viết tay\n' > "$ROOT/AGENTS.md"
  agent install
  assert_status 0 'AGENTS.md viết tay không làm install lỗi'
  assert_contains 'không do bin/agent sinh' 'cảnh báo giữ AGENTS.md viết tay'
  assert_equals 'viết tay' "$(cat "$ROOT/AGENTS.md")" 'AGENTS.md viết tay được giữ nguyên'
  assert_file_line "$ROOT/CLAUDE.md" '@AGENTS.md' 'CLAUDE.md vẫn được sinh'
  agent install --force
  assert_file_matches "$ROOT/AGENTS.md" 'shop\.test' '--force ghi đè file viết tay'
}

test_tracked_files_preserved() {
  new_root
  local d="$SANDBOX/repo"
  git -c init.defaultBranch=master init -q "$d"
  git -C "$d" config user.name t
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config commit.gpgsign false
  printf 'của repo\n' > "$d/AGENTS.md"
  git -C "$d" add AGENTS.md
  git -C "$d" commit -q -m 'agents'
  agent install --target "$d" --force
  assert_status 0 'install vào repo có AGENTS.md đã theo dõi thoát 0'
  assert_contains 'đã được Git theo dõi' 'cảnh báo file đã theo dõi'
  assert_equals 'của repo' "$(cat "$d/AGENTS.md")" 'AGENTS.md đã theo dõi không bị ghi đè kể cả --force'
  assert_file "$d/CLAUDE.md" 'CLAUDE.md chưa theo dõi vẫn được sinh'
}

# Worktree sau bin/wt prepare có kit agent (src/ là clone của bare remote có master).
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
  printf '## Riêng\n' > "$ROOT/project/agent/AGENTS.project.md"

  run_in "$ROOT" bin/wt create feature/kit-agent
  assert_status 0 'create thoát 0'
  local d="$ROOT/.worktrees/feature-kit-agent"
  assert_file "$d/AGENTS.md" 'worktree mới có AGENTS.md'
  assert_file_matches "$d/AGENTS.md" 'origin/master' 'AGENTS.md trong worktree có giá trị profile'
  assert_file_line "$d/AGENTS.md" '## Riêng' 'AGENTS.md trong worktree có phần của dự án'
  assert_file_line "$d/CLAUDE.md" '@AGENTS.md' 'worktree có CLAUDE.md'
  assert_file "$d/.claude/skills/format-deploy/SKILL.md" 'worktree có skill dự án'

  rm -f "$d/AGENTS.md" "$d/CLAUDE.md"
  rm -rf "$d/.claude" "$d/.agents"
  run_in "$ROOT" bin/wt prepare feature-kit-agent
  assert_status 0 'prepare thoát 0'
  assert_file "$d/AGENTS.md" 'prepare cài lại kit agent vào worktree'
  assert_file "$d/.agents/skills/format-deploy/SKILL.md" 'prepare cài lại skill vào .agents/skills'
}

run_tests
finish
